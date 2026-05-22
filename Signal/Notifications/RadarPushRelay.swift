//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit
import UIKit
import UserNotifications

/// Provisions the Radar push relay as a Signal linked device and keeps its
/// APNs token in sync. The relay opens its own WebSocket to chat.signal.org,
/// observes incoming envelopes for our account, and pings APNs so the iOS
/// NSE wakes — even when the host app has been force-quit.
///
/// This is purely additive: it does not change the existing primary-device
/// push-token sync, so Signal's chat-server push path still runs in parallel.
///
/// All mutating operations are serialized through `RelayWorker` so that
/// callers (app-ready, APNs token receipt, settings toggle, logout) cannot
/// race each other into orphaned phantoms or inconsistent state.
public enum RadarPushRelay {

    private static let baseURLString = "https://push.radar.chat"

    public enum RelayError: Error {
        case http(status: Int, body: String)
        case malformedResponse
        case missingPrimaryState(String)
        case provisioning(String)
        case linkRejected
    }

    // MARK: - Public surface

    /// Whether the relay is currently enabled by the user. Defaults to `false`
    /// — the user must opt in via the onboarding prompt or the Settings toggle.
    public static func isEnabled() -> Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            Store.isEnabled(tx: tx)
        }
    }

    /// Flip the user's preference. On `false`, tears down the relay and
    /// unlinks the phantom Signal device. On `true`, runs `ensure(...)`.
    public static func setEnabled(_ enabled: Bool) async {
        await RelayWorker.shared.setEnabled(enabled)
    }

    /// Idempotent: ensures the relay is registered, the phantom linked device
    /// has been provisioned, and the relay's APNs token is up to date. Safe
    /// to call multiple times; no-ops when nothing needs doing.
    /// Best-effort — errors are logged, not thrown.
    public static func ensure(apnsHexToken: String?) async {
        await RelayWorker.shared.ensure(apnsHexToken: apnsHexToken)
    }

    /// Tear down the relay registration on logout. The Signal account
    /// itself is going away, so we don't bother unlinking the phantom —
    /// the chat server will drop it as part of the account deletion.
    public static func unregister() async {
        await RelayWorker.shared.unregister()
    }

    // MARK: - Permission prompt

    /// Whether the user has been shown the Allow/Disable relay prompt yet.
    static func hasAskedAboutRelay() -> Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            Store.hasAskedAboutRelay(tx: tx)
        }
    }

    /// Set while the relay popup is on screen so we don't double-present from
    /// concurrent callers (e.g. onboarding finishing + app becoming active).
    @MainActor private static var isPresentingPrompt = false

    /// If the user hasn't been asked yet AND OS notifications are authorized,
    /// presents the Allow/Disable relay popup from `viewController`. The user's
    /// choice is persisted and `setEnabled(_:)` is called accordingly.
    /// Gated on OS notification authorization — relay is only useful when the
    /// OS allows us to deliver notifications.
    @MainActor
    static func askIfNeeded(from viewController: UIViewController) async {
        guard !isPresentingPrompt else { return }

        let alreadyAsked = SSKEnvironment.shared.databaseStorageRef.read { tx in
            Store.hasAskedAboutRelay(tx: tx)
        }
        guard !alreadyAsked else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
            return
        }

        isPresentingPrompt = true
        defer { isPresentingPrompt = false }

        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let alert = UIAlertController(
                title: OWSLocalizedString(
                    "RELAY_PERMISSION_ALERT_TITLE",
                    comment: "Title of the alert asking the user whether to enable the Radar notification relay."
                ),
                message: OWSLocalizedString(
                    "RELAY_PERMISSION_ALERT_MESSAGE",
                    comment: "Body of the alert asking the user whether to enable the Radar notification relay."
                ),
                preferredStyle: .alert
            )
            // Match iOS system permission alerts: "Don't Allow"-equivalent on the
            // left (cancel), preferred "Allow"-equivalent on the right (bold).
            alert.addAction(UIAlertAction(
                title: OWSLocalizedString(
                    "RELAY_PERMISSION_ALERT_DISABLE",
                    comment: "Button title to disable the Radar notification relay."
                ),
                style: .cancel
            ) { _ in
                continuation.resume(returning: false)
            })
            let allowAction = UIAlertAction(
                title: OWSLocalizedString(
                    "RELAY_PERMISSION_ALERT_ALLOW",
                    comment: "Button title to allow / enable the Radar notification relay."
                ),
                style: .default
            ) { _ in
                continuation.resume(returning: true)
            }
            alert.addAction(allowAction)
            alert.preferredAction = allowAction
            viewController.present(alert, animated: true)
        }

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            Store.setHasAskedAboutRelay(true, tx: tx)
        }
        // Don't block the rest of the onboarding flow on the relay setup —
        // `setEnabled(true)` may take seconds to register with the relay
        // server and provision the phantom linked device. The RelayWorker
        // actor already serializes these operations safely.
        Task { await setEnabled(granted) }
    }

    // MARK: - Implementation (called only from the worker)

    fileprivate static func doEnsure(apnsHexToken: String?) async {
        do {
            try await runEnsure(apnsHexToken: apnsHexToken)
        } catch {
            Logger.warn("RadarPushRelay ensure failed: \(error)")
        }
    }

    fileprivate static func doSetEnabled(_ enabled: Bool) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            Store.setEnabled(enabled, tx: tx)
        }
        if enabled {
            await doEnsure(apnsHexToken: nil)
        } else {
            await tearDown(unlinkPhantomFromSignal: true)
        }
    }

    fileprivate static func doUnregister() async {
        await tearDown(unlinkPhantomFromSignal: false)
    }

    private static func runEnsure(apnsHexToken: String?) async throws {
        let dependencies = try captureDependencies()

        let isEnabled = dependencies.db.read { tx in Store.isEnabled(tx: tx) }
        guard isEnabled else {
            Logger.info("RadarPushRelay: disabled by user; skipping")
            return
        }

        let resolvedApnsHex = apnsHexToken ?? dependencies.db.read { tx in
            SSKEnvironment.shared.preferencesRef.getPushToken(tx: tx)
        }
        guard let apnsHex = resolvedApnsHex, !isAllZeroHex(apnsHex) else {
            // All-zero token comes from the simulator's debug-only fallback
            // (AppDelegate.didFailToRegisterForRemoteNotifications) — useless
            // to register and would pollute the relay.
            Logger.info("RadarPushRelay: no usable APNs token yet; deferring")
            return
        }

        var (storedRelayToken, hasLinked) = dependencies.db.read { tx in
            return (Store.getRelayToken(tx: tx), Store.isLinked(tx: tx))
        }

        // 1. If we believe we're linked, double-check via /status. If the
        //    relay's bridge has stopped or the relay no longer considers us
        //    linked, drop our local belief and fall through to re-link —
        //    also unlinking the stale phantom from chat.signal.org so it
        //    doesn't pile up in the user's Linked Devices list.
        if hasLinked, let token = storedRelayToken {
            do {
                let status = try await API.status(relayToken: token)
                if !status.linked || status.bridge?.state == "Stopped" {
                    Logger.warn("RadarPushRelay: relay reports not-linked or Stopped (\(status.bridge?.reason ?? "?")); re-linking")
                    await unlinkStalePhantom(dependencies: dependencies)
                    hasLinked = false
                    await dependencies.db.awaitableWrite { tx in
                        Store.setIsLinked(false, tx: tx)
                    }
                }
            } catch RelayError.http(status: 404, _) {
                Logger.warn("RadarPushRelay: relay does not know our token; re-registering")
                await unlinkStalePhantom(dependencies: dependencies)
                storedRelayToken = nil
                hasLinked = false
                await dependencies.db.awaitableWrite { tx in
                    Store.setRelayToken(nil, tx: tx)
                    Store.setIsLinked(false, tx: tx)
                }
            }
        }

        // 2. Register device with relay if we haven't yet.
        let relayToken: String
        if let storedRelayToken {
            relayToken = storedRelayToken
        } else {
            relayToken = try await retrying { try await API.register(apnsHex: apnsHex) }
            await dependencies.db.awaitableWrite { tx in
                Store.setRelayToken(relayToken, tx: tx)
            }
            Logger.info("RadarPushRelay: registered device with relay")
        }

        // 3. Provision phantom linked device + link, if we haven't yet.
        if !hasLinked {
            let credentials = try await Linker.provisionPhantomLinkedDevice(dependencies: dependencies)
            // Persist deviceId immediately so we can unlink later even if the
            // subsequent link call fails permanently.
            await dependencies.db.awaitableWrite { tx in
                Store.setPhantomDeviceId(credentials.deviceId, tx: tx)
            }
            do {
                try await retrying {
                    try await API.link(relayToken: relayToken, credentials: credentials)
                }
            } catch {
                Logger.warn("RadarPushRelay: link failed after retries — unlinking phantom: \(error)")
                if let deviceId = DeviceId(validating: credentials.deviceId) {
                    _ = try? await DependenciesBridge.shared.deviceService.unlinkDevice(deviceId: deviceId)
                }
                await dependencies.db.awaitableWrite { tx in
                    Store.setPhantomDeviceId(nil, tx: tx)
                }
                throw error
            }
            await dependencies.db.awaitableWrite { tx in
                Store.setIsLinked(true, tx: tx)
            }
            Logger.info("RadarPushRelay: linked phantom device id=\(credentials.deviceId)")
        }

        // 4. Always refresh the APNs token on the relay — cheap, and covers
        //    the case where iOS rotated it while we were offline.
        try await retrying {
            try await API.updateAPNsToken(relayToken: relayToken, apnsHex: apnsHex)
        }
    }

    /// Shared teardown path used by both logout and explicit user-disable.
    /// Best-effort: each step logs and proceeds independently so local
    /// state always ends up clean.
    private static func tearDown(unlinkPhantomFromSignal: Bool) async {
        let (storedRelayToken, phantomDeviceId) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (Store.getRelayToken(tx: tx), Store.getPhantomDeviceId(tx: tx))
        }

        guard storedRelayToken != nil || phantomDeviceId != nil else {
            // Nothing to tear down — common on fresh install before the user
            // has registered for the first time.
            return
        }

        if let storedRelayToken {
            do {
                try await API.unregister(relayToken: storedRelayToken)
                Logger.info("RadarPushRelay: unregistered from relay")
            } catch {
                Logger.warn("RadarPushRelay unregister failed: \(error)")
            }
        }

        if unlinkPhantomFromSignal, let phantomDeviceId,
           let deviceId = DeviceId(validating: phantomDeviceId) {
            do {
                try await DependenciesBridge.shared.deviceService.unlinkDevice(deviceId: deviceId)
                Logger.info("RadarPushRelay: unlinked phantom Signal device id=\(phantomDeviceId)")
            } catch {
                Logger.warn("RadarPushRelay phantom unlink failed: \(error)")
            }
        }

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            Store.setRelayToken(nil, tx: tx)
            Store.setIsLinked(false, tx: tx)
            Store.setPhantomDeviceId(nil, tx: tx)
        }
    }

    /// Best-effort cleanup of the phantom Signal device we provisioned in a
    /// previous link cycle. Called before re-linking, to keep the user's
    /// Linked Devices list from accumulating orphans.
    private static func unlinkStalePhantom(dependencies: Dependencies) async {
        let phantomDeviceId = dependencies.db.read { tx in
            Store.getPhantomDeviceId(tx: tx)
        }
        guard let phantomDeviceId, let deviceId = DeviceId(validating: phantomDeviceId) else {
            return
        }
        do {
            try await DependenciesBridge.shared.deviceService.unlinkDevice(deviceId: deviceId)
            Logger.info("RadarPushRelay: unlinked stale phantom device id=\(phantomDeviceId)")
        } catch {
            Logger.warn("RadarPushRelay stale phantom unlink failed: \(error)")
        }
        await dependencies.db.awaitableWrite { tx in
            Store.setPhantomDeviceId(nil, tx: tx)
        }
    }

    // MARK: - Retry

    private static func retrying<T>(maxAttempts: Int = 3, _ block: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await block()
            } catch let error as RelayError {
                if case .http(let status, _) = error, status < 500 && status != 429 {
                    // Logical 4xx error — retrying won't help.
                    throw error
                }
                if attempt >= maxAttempts { throw error }
            } catch {
                if attempt >= maxAttempts { throw error }
            }
            try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
        }
    }

    private static func isAllZeroHex(_ hex: String) -> Bool {
        return !hex.isEmpty && hex.allSatisfy { $0 == "0" }
    }

    // MARK: - HTTP

    private enum API {
        struct RegisterResponse: Decodable {
            let relayToken: String
        }

        static func register(apnsHex: String) async throws -> String {
            struct Body: Encodable {
                let apnsToken: String
                let environment: String
            }
            let body = try encoder.encode(Body(apnsToken: apnsHex, environment: environmentString))
            let response: RegisterResponse = try await send(
                method: "POST",
                path: "/api/v1/devices",
                body: body,
                relayToken: nil
            )
            return response.relayToken
        }

        struct LinkResponse: Decodable {
            let linked: Bool
        }

        static func link(relayToken: String, credentials: Linker.Credentials) async throws {
            struct Body: Encodable {
                let signalAci: String
                let signalDeviceId: UInt32
                let signalPassword: String
            }
            let body = try encoder.encode(Body(
                signalAci: credentials.aci,
                signalDeviceId: credentials.deviceId,
                signalPassword: credentials.password
            ))
            let response: LinkResponse = try await send(
                method: "POST",
                path: "/api/v1/link",
                body: body,
                relayToken: relayToken
            )
            guard response.linked else {
                throw RelayError.linkRejected
            }
        }

        static func updateAPNsToken(relayToken: String, apnsHex: String) async throws {
            struct Body: Encodable {
                let newApnsToken: String
                let environment: String
            }
            let body = try encoder.encode(Body(newApnsToken: apnsHex, environment: environmentString))
            let _: EmptyResponse = try await send(
                method: "PUT",
                path: "/api/v1/devices/token",
                body: body,
                relayToken: relayToken
            )
        }

        struct StatusResponse: Decodable {
            let linked: Bool
            let bridge: Bridge?

            struct Bridge: Decodable {
                let state: String
                let reason: String?
                let nextAttemptInSecs: Int?
            }
        }

        static func status(relayToken: String) async throws -> StatusResponse {
            return try await send(
                method: "GET",
                path: "/api/v1/devices/\(relayToken)/status",
                body: nil,
                relayToken: relayToken
            )
        }

        static func unregister(relayToken: String) async throws {
            let _: EmptyResponse = try await send(
                method: "DELETE",
                path: "/api/v1/devices",
                body: nil,
                relayToken: relayToken
            )
        }

        private struct EmptyResponse: Decodable {}

        private static func send<T: Decodable>(
            method: String,
            path: String,
            body: Data?,
            relayToken: String?
        ) async throws -> T {
            guard let url = URL(string: "\(baseURLString)\(path)") else {
                throw RelayError.malformedResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let relayToken {
                request.setValue(relayToken, forHTTPHeaderField: "X-Relay-Token")
            }
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RelayError.malformedResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw RelayError.http(
                    status: http.statusCode,
                    body: String(data: data, encoding: .utf8) ?? ""
                )
            }
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            return try decoder.decode(T.self, from: data)
        }
    }

    // MARK: - Linker

    private enum Linker {
        struct Credentials {
            let aci: String
            let deviceId: UInt32
            let password: String
        }

        struct PrimaryState {
            let aci: Aci
            let pni: Pni
            let phoneNumber: String
            let aciIdentityKeyPair: ECKeyPair
            let pniIdentityKeyPair: ECKeyPair
            let profileKey: Aes256Key
        }

        static func readPrimaryState(_ dependencies: Dependencies) throws -> PrimaryState {
            return try dependencies.db.read { tx -> PrimaryState in
                guard let localIdentifiers = dependencies.tsAccountManager.localIdentifiers(tx: tx) else {
                    throw RelayError.missingPrimaryState("no local identifiers")
                }
                guard let pni = localIdentifiers.pni else {
                    throw RelayError.missingPrimaryState("no pni")
                }
                guard let aciIdentityKeyPair = dependencies.identityManager.identityKeyPair(for: .aci, tx: tx) else {
                    throw RelayError.missingPrimaryState("no aci identity")
                }
                guard let pniIdentityKeyPair = dependencies.identityManager.identityKeyPair(for: .pni, tx: tx) else {
                    throw RelayError.missingPrimaryState("no pni identity")
                }
                guard let profileKey = SSKEnvironment.shared.profileManagerRef.localUserProfile(tx: tx)?.profileKey else {
                    throw RelayError.missingPrimaryState("no profile key")
                }
                return PrimaryState(
                    aci: localIdentifiers.aci,
                    pni: pni,
                    phoneNumber: localIdentifiers.phoneNumber,
                    aciIdentityKeyPair: aciIdentityKeyPair,
                    pniIdentityKeyPair: pniIdentityKeyPair,
                    profileKey: profileKey
                )
            }
        }

        static func provisionPhantomLinkedDevice(dependencies: Dependencies) async throws -> Credentials {
            let primary = try readPrimaryState(dependencies)

            let provisioningCode = try await dependencies.deviceProvisioningService
                .requestDeviceProvisioningCode()

            let prekeyBundles = try await dependencies.preKeyManager
                .createPreKeysForProvisioning(
                    aciIdentityKeyPair: primary.aciIdentityKeyPair,
                    pniIdentityKeyPair: primary.pniIdentityKeyPair
                )
                .value

            let aciRegistrationId = RegistrationIdGenerator.generate()
            let pniRegistrationId = RegistrationIdGenerator.generate()
            let authPassword = Randomness.generateRandomBytes(16).hexadecimalString

            let encryptedDeviceName = try OWSDeviceNames.encryptDeviceName(
                plaintext: "Radar Push Relay",
                identityKeyPair: primary.aciIdentityKeyPair.identityKeyPair
            )

            let attributes = buildAccountAttributes(
                dependencies: dependencies,
                primary: primary,
                encryptedDeviceName: encryptedDeviceName,
                aciRegistrationId: aciRegistrationId,
                pniRegistrationId: pniRegistrationId
            )

            let response = await ProvisioningCoordinatorImpl.Service.makeVerifySecondaryDeviceRequest(
                verificationCode: provisioningCode.verificationCode,
                phoneNumber: primary.phoneNumber,
                authPassword: authPassword,
                accountAttributes: attributes,
                apnRegistrationId: nil,
                prekeyBundles: prekeyBundles,
                signalService: SSKEnvironment.shared.signalServiceRef
            )

            // Discard the scratchpad prekeys regardless of outcome. We don't
            // want the phantom's prekeys leaking into the primary's stores.
            _ = try? await dependencies.preKeyManager
                .finalizeRegistrationPreKeys(prekeyBundles, uploadDidSucceed: false)
                .value

            switch response {
            case .success(let resp):
                return Credentials(
                    aci: primary.aci.serviceIdString,
                    deviceId: resp.deviceId.uint32Value,
                    password: authPassword
                )
            case .obsoleteLinkedDevice:
                throw RelayError.provisioning("obsolete linked device")
            case .deviceLimitExceeded:
                throw RelayError.provisioning("device limit exceeded")
            case .genericError(let error):
                throw RelayError.provisioning("\(error)")
            }
        }

        private static func buildAccountAttributes(
            dependencies: Dependencies,
            primary: PrimaryState,
            encryptedDeviceName: Data,
            aciRegistrationId: UInt32,
            pniRegistrationId: UInt32
        ) -> AccountAttributes {
            return dependencies.db.read { tx in
                let udAccessKey = SMKUDAccessKey(profileKey: primary.profileKey).keyData.base64EncodedString()
                let allowUnrestrictedUD = SSKEnvironment.shared.udManagerRef
                    .shouldAllowUnrestrictedAccessLocal(transaction: tx)
                let registrationRecoveryPassword = dependencies.accountKeyStore
                    .getMasterKey(tx: tx)?
                    .data(for: .registrationRecoveryPassword)
                    .canonicalStringRepresentation
                let phoneNumberDiscoverability = dependencies.tsAccountManager
                    .phoneNumberDiscoverability(tx: tx)
                let hasSVRBackups = dependencies.svr.hasBackedUpMasterKey(transaction: tx)

                return AccountAttributes(
                    isManualMessageFetchEnabled: true,
                    registrationId: aciRegistrationId,
                    pniRegistrationId: pniRegistrationId,
                    unidentifiedAccessKey: udAccessKey,
                    unrestrictedUnidentifiedAccess: allowUnrestrictedUD,
                    reglockToken: nil,
                    registrationRecoveryPassword: registrationRecoveryPassword,
                    encryptedDeviceName: encryptedDeviceName.base64EncodedString(),
                    discoverableByPhoneNumber: phoneNumberDiscoverability,
                    hasSVRBackups: hasSVRBackups
                )
            }
        }
    }

    // MARK: - Dependencies

    private struct Dependencies {
        let db: any DB
        let tsAccountManager: TSAccountManager
        let identityManager: OWSIdentityManager
        let preKeyManager: PreKeyManager
        let deviceProvisioningService: DeviceProvisioningService
        let accountKeyStore: AccountKeyStore
        let svr: SecureValueRecovery
    }

    /// Built once and reused — the underlying service is stateless wrapper
    /// around the existing networkManager.
    private static let sharedDeviceProvisioningService: DeviceProvisioningService = {
        DeviceProvisioningServiceImpl(
            networkManager: SSKEnvironment.shared.networkManagerRef
        )
    }()

    private static func captureDependencies() throws -> Dependencies {
        let bridge = DependenciesBridge.shared
        let tsRegistrationState = bridge.db.read { tx in
            bridge.tsAccountManager.registrationState(tx: tx)
        }
        guard tsRegistrationState.isRegistered else {
            throw RelayError.missingPrimaryState("not registered yet")
        }
        return Dependencies(
            db: bridge.db,
            tsAccountManager: bridge.tsAccountManager,
            identityManager: bridge.identityManager,
            preKeyManager: bridge.preKeyManager,
            deviceProvisioningService: sharedDeviceProvisioningService,
            accountKeyStore: bridge.accountKeyStore,
            svr: bridge.svr
        )
    }

    // MARK: - Helpers

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Resolved once at first access from the embedded mobileprovision's
    /// `aps-environment` entitlement. Production APNs tokens map to
    /// `"production"`, everything else (development profile, simulator,
    /// missing/unparseable profile) maps to `"sandbox"`.
    private static let environmentString: String = {
        guard
            let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url)
        else {
            return "sandbox"
        }
        // mobileprovision is CMS-signed but the entitlements payload is
        // a plain XML plist. Slice between the XML boundary markers.
        guard
            let xmlStart = data.range(of: Data("<?xml".utf8))?.lowerBound,
            let xmlEnd = data.range(of: Data("</plist>".utf8))?.upperBound
        else {
            return "sandbox"
        }
        let plistData = data.subdata(in: xmlStart..<xmlEnd)
        guard
            let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
            let entitlements = (plist as? [String: Any])?["Entitlements"] as? [String: Any],
            let apsEnvironment = entitlements["aps-environment"] as? String
        else {
            return "sandbox"
        }
        return apsEnvironment == "production" ? "production" : "sandbox"
    }()
}

// MARK: - Serialization

/// All mutating relay operations queue through here so they execute strictly
/// in order, even if invoked concurrently from app-ready, settings toggle,
/// APNs token receipt, or logout.
private actor RelayWorker {
    static let shared = RelayWorker()
    private init() {}

    private var tail: Task<Void, Never>?

    private func enqueue(_ block: @Sendable @escaping () async -> Void) async {
        let previous = tail
        let task = Task { [previous] in
            _ = await previous?.value
            await block()
        }
        tail = task
        _ = await task.value
    }

    func ensure(apnsHexToken: String?) async {
        await enqueue {
            await RadarPushRelay.doEnsure(apnsHexToken: apnsHexToken)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        await enqueue {
            await RadarPushRelay.doSetEnabled(enabled)
        }
    }

    func unregister() async {
        await enqueue {
            await RadarPushRelay.doUnregister()
        }
    }
}

// MARK: - Store

private enum Store {
    private static let kvStore = KeyValueStore(collection: "RadarPushRelay")
    private static let relayTokenKey = "relayToken"
    private static let isLinkedKey = "isLinked"
    private static let isEnabledKey = "isEnabled"
    private static let phantomDeviceIdKey = "phantomDeviceId"
    private static let hasAskedAboutRelayKey = "hasAskedAboutRelay"

    static func getRelayToken(tx: DBReadTransaction) -> String? {
        return kvStore.getString(relayTokenKey, transaction: tx)
    }

    static func setRelayToken(_ value: String?, tx: DBWriteTransaction) {
        if let value {
            kvStore.setString(value, key: relayTokenKey, transaction: tx)
        } else {
            kvStore.removeValue(forKey: relayTokenKey, transaction: tx)
        }
    }

    static func isLinked(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(isLinkedKey, defaultValue: false, transaction: tx)
    }

    static func setIsLinked(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(value, key: isLinkedKey, transaction: tx)
    }

    /// Defaults to `false`: relay is off until the user explicitly opts in via
    /// the onboarding Allow/Don't-Allow prompt or the Settings toggle.
    static func isEnabled(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(isEnabledKey, defaultValue: false, transaction: tx)
    }

    static func setEnabled(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(value, key: isEnabledKey, transaction: tx)
    }

    static func getPhantomDeviceId(tx: DBReadTransaction) -> UInt32? {
        return kvStore.getUInt32(phantomDeviceIdKey, transaction: tx)
    }

    static func setPhantomDeviceId(_ value: UInt32?, tx: DBWriteTransaction) {
        if let value {
            kvStore.setUInt32(value, key: phantomDeviceIdKey, transaction: tx)
        } else {
            kvStore.removeValue(forKey: phantomDeviceIdKey, transaction: tx)
        }
    }

    static func hasAskedAboutRelay(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(hasAskedAboutRelayKey, defaultValue: false, transaction: tx)
    }

    static func setHasAskedAboutRelay(_ value: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(value, key: hasAskedAboutRelayKey, transaction: tx)
    }
}
