//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
import LibSignalClient
import SignalServiceKit

public class QuickRestoreManager {
    public typealias RestoreMethodToken = String

    private let accountKeyStore: AccountKeyStore
    private let backupNonceStore: BackupNonceMetadataStore
    private let backupSettingsStore: BackupSettingsStore
    private let db: any DB
    private let deviceProvisioningService: DeviceProvisioningService
    private let identityManager: OWSIdentityManager
    private let networkManager: any NetworkManagerProtocol
    private let tsAccountManager: TSAccountManager

    init(
        accountKeyStore: AccountKeyStore,
        backupNonceStore: BackupNonceMetadataStore,
        backupSettingsStore: BackupSettingsStore,
        db: any DB,
        deviceProvisioningService: DeviceProvisioningService,
        identityManager: OWSIdentityManager,
        networkManager: any NetworkManagerProtocol,
        tsAccountManager: TSAccountManager,
    ) {
        self.accountKeyStore = accountKeyStore
        self.backupNonceStore = backupNonceStore
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.deviceProvisioningService = deviceProvisioningService
        self.identityManager = identityManager
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager
    }

    public func register(deviceProvisioningUrl: DeviceProvisioningURL) async throws -> RestoreMethodToken {
        let (
            localIdentifiers,
            accountEntropyPool,
            aciIdentityKeyPair,
            pniIdentityKeyPair,
            pinCode,
            backupTier,
            lastBackupDate,
            lastBackupSizeBytes,
            lastBackupForwardSecrecyToken,
            nextBackupSecretData,
        ) = try db.read { tx in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                throw OWSAssertionError("Can't quick restore without local identifiers")
            }
            guard let accountEntropyPool = accountKeyStore.getAccountEntropyPool(tx: tx) else {
                // This should be impossible; the only times you don't have
                // a AEP are during registration.
                throw OWSAssertionError("Can't quick restore without AccountEntropyPool")
            }
            guard let aciIdentityKeyPair = identityManager.identityKeyPair(for: .aci, tx: tx) else {
                throw OWSAssertionError("Can't quick restore without local identity key")
            }
            guard let pniIdentityKeyPair = identityManager.identityKeyPair(for: .pni, tx: tx) else {
                throw OWSAssertionError("Can't quick restore without local identity key")
            }
            let pinCode = SSKEnvironment.shared.ows2FAManagerRef.pinCode(transaction: tx)

            let backupTier: RegistrationProvisioningMessage.BackupTier? = switch backupSettingsStore.backupPlan(tx: tx) {
            case .free: .free
            case .paid, .paidExpiringSoon, .paidAsTester: .paid
            case .disabled, .disabling: nil
            }

            let lastBackupTime: UInt64?
            let lastBackupSizeBytes: UInt64?
            if backupTier != nil {
                let lastBackupDetails = backupSettingsStore.lastBackupDetails(tx: tx)
                lastBackupTime = lastBackupDetails?.date.ows_millisecondsSince1970
                lastBackupSizeBytes = lastBackupDetails?.backupTotalSizeBytes
            } else {
                lastBackupTime = nil
                lastBackupSizeBytes = nil
            }

            let backupKey = MessageRootBackupKey(
                accountEntropyPool: accountEntropyPool,
                aci: localIdentifiers.aci,
            )
            let lastBackupForwardSecrecyToken = try backupNonceStore.getLastForwardSecrecyToken(
                for: backupKey,
                tx: tx,
            )
            let nextBackupSecretData = backupNonceStore.getNextSecretMetadata(
                for: backupKey,
                tx: tx,
            )

            return (
                localIdentifiers,
                accountEntropyPool,
                aciIdentityKeyPair,
                pniIdentityKeyPair,
                pinCode,
                backupTier,
                lastBackupTime,
                lastBackupSizeBytes,
                lastBackupForwardSecrecyToken,
                nextBackupSecretData,
            )
        }

        let myAci = localIdentifiers.aci
        let myE164: E164
        if let phoneNumber = localIdentifiers.phoneNumber {
            guard let _myE164 = E164(phoneNumber) else {
                throw OWSAssertionError("can't quick restore without e164")
            }
            myE164 = _myE164
        } else {
            // TODO: [#less] Add support for Quick Restore.
            throw OWSAssertionError("can't quick restore without e164")
        }

        let restoreMethodToken = UUID().uuidString

        let capabilities: [RegistrationProvisioningMessage.Capability]
        if
            deviceProvisioningUrl.capabilities.contains(.wifiaware),
            DeviceTransfer.platformSupportsWifiAware(),
            RemoteConfig.current.wifiAwareDeviceTransferEnabled
        {
            capabilities = [RegistrationProvisioningMessage.Capability.wifiaware]
        } else {
            capabilities = []
        }

        let registrationMessage = RegistrationProvisioningMessage(
            aci: myAci,
            aciIdentityKeyPair: aciIdentityKeyPair.identityKeyPair,
            phoneNumberState: RegistrationProvisioningMessage.PhoneNumberState(
                phoneNumber: myE164,
                pniIdentityKeyPair: pniIdentityKeyPair.identityKeyPair,
            ),
            accountEntropyPool: accountEntropyPool,
            pin: pinCode,
            tier: backupTier,
            backupVersion: BackupArchiveManagerImpl.Constants.supportedBackupVersion,
            backupTimestamp: lastBackupDate,
            backupSizeBytes: lastBackupSizeBytes,
            restoreMethodToken: restoreMethodToken,
            lastBackupForwardSecrecyToken: lastBackupForwardSecrecyToken,
            nextBackupSecretData: nextBackupSecretData,
            capabilites: capabilities,
        )

        let theirPublicKey = deviceProvisioningUrl.publicKey
        let messageBody = try registrationMessage.buildEncryptedMessageBody(theirPublicKey: theirPublicKey)
        try await deviceProvisioningService.provisionDevice(
            messageBody: messageBody,
            ephemeralDeviceId: deviceProvisioningUrl.ephemeralDeviceId,
        )

        return restoreMethodToken
    }

    public enum RestoreMethodType {
        case remoteBackup
        case localBackup
        case deviceTransfer(URL)
        case decline

        fileprivate init?(response: Requests.WaitForRestoreMethodChoice.Response) {
            switch response.method {
            case .decline: self = .decline
            case .localBackup: self = .localBackup
            case .remoteBackup: self = .remoteBackup
            case .deviceTransfer:
                guard
                    let bootstrapData = response.deviceTransferBootstrap,
                    let stringData = Data(base64EncodedWithoutPadding: bootstrapData),
                    let urlString = String(data: stringData, encoding: .utf8),
                    let transferURL = URL(string: urlString)
                else {
                    Logger.error("Missing device transfer data")
                    return nil
                }
                self = .deviceTransfer(transferURL)
            }
        }
    }

    public func reportRestoreMethodChoice(method: RestoreMethodType, restoreMethodToken: RestoreMethodToken) async throws {
        try await Retry.performWithMinimumBackoff(
            maxAttempts: .max,
            block: {
                let response = try await networkManager.asyncRequest(
                    Requests.ChooseRestoreMethod.buildRequest(
                        token: restoreMethodToken,
                        method: method,
                    ),
                )
                guard response.responseStatusCode == 200 || response.responseStatusCode == 204 else {
                    throw response.asError()
                }
            },
            onError: {
                if $0.httpStatusCode == 429 {
                    return .retryAfterAtLeast($0.httpResponseHeaders?.retryAfterTimeInterval ?? Constants.defaultRetryTime)
                }
                throw $0
            },
        )
    }

    public func waitForRestoreMethodChoice(restoreMethodToken: RestoreMethodToken) async throws -> RestoreMethodType {
        // The outer "Retry" is for 204 handling where we want to immediately try
        // again without any backoff. It means our polling timeout expired, and we
        // need to issue a new request.
        return try await Retry.performRepeatedly(
            block: {
                // The inner "Retry" is for general-purpose retries and includes
                // exponential backoff. (Note: The exponential backoff gets reset each time
                // the outer "Retry" loop iterates because we invoke
                // performWithMinimumBackoff with fresh state. This is intentional.)
                return try await Retry.performWithMinimumBackoff(
                    maxAttempts: .max,
                    block: {
                        let request = Requests.WaitForRestoreMethodChoice.buildRequest(token: restoreMethodToken)
                        let response = try await networkManager.asyncRequest(request)
                        guard response.responseStatusCode == 200 else {
                            throw response.asError()
                        }
                        let parsedResponse = try JSONDecoder().decode(
                            Requests.WaitForRestoreMethodChoice.Response.self,
                            from: response.responseBodyData ?? Data(),
                        )
                        guard let restoreType = RestoreMethodType(response: parsedResponse) else {
                            throw OWSGenericError("unsupported restore method")
                        }
                        return restoreType
                    },
                    onError: {
                        if $0.httpStatusCode == 429 {
                            return .retryAfterAtLeast($0.httpResponseHeaders?.retryAfterTimeInterval ?? Constants.defaultRetryTime)
                        }
                        throw $0
                    },
                )
            },
            onError: { error, _ in
                /// The timeout elapsed without the device linking; clients can request again.
                if error.httpStatusCode == 204 {
                    return
                }
                throw error
            },
        )
    }

    private enum Constants {
        static let longPollRequestTimeoutSeconds: UInt32 = 60 * 5
        static let defaultRetryTime: TimeInterval = 15
    }

    fileprivate enum Requests {
        enum RestoreMethod: String, Codable {
            case remoteBackup = "REMOTE_BACKUP"
            case localBackup = "LOCAL_BACKUP"
            case deviceTransfer = "DEVICE_TRANSFER"
            case decline = "DECLINE"
        }

        enum WaitForRestoreMethodChoice {
            struct Response: Codable {
                /// The method of restore chosen by the new device
                let method: RestoreMethod
                /// Additional data used to bootstrap device transfer
                let deviceTransferBootstrap: String?
            }

            static func buildRequest(token: RestoreMethodToken) -> TSRequest {
                var urlComponents = URLComponents(string: "v1/devices/restore_account/\(token)")!
                urlComponents.queryItems = [URLQueryItem(
                    name: "timeout",
                    value: "\(Constants.longPollRequestTimeoutSeconds)",
                )]
                var request = TSRequest(
                    url: urlComponents.url!,
                    method: "GET",
                    parameters: nil,
                )

                request.auth = .anonymous
                request.applyRedactionStrategy(.redactURL(sensitiveValues: ["\(token)"]))
                // The timeout is server side; apply wiggle room for our local clock.
                request.timeoutInterval = 10 + TimeInterval(Constants.longPollRequestTimeoutSeconds)
                return request
            }
        }

        enum ChooseRestoreMethod {
            static func buildRequest(token: RestoreMethodToken, method: RestoreMethodType) -> TSRequest {
                var deviceTransferBootstrap: URL?
                let method: RestoreMethod = {
                    switch method {
                    case .decline: return .decline
                    case .deviceTransfer(let data):
                        deviceTransferBootstrap = data
                        return .deviceTransfer
                    case .remoteBackup:
                        return .remoteBackup
                    case .localBackup:
                        return .localBackup
                    }
                }()

                var parameters: [String: Any] = ["method": method.rawValue]
                // `deviceTransferBootstrap` contains unpadded base64 encoded data that is used by
                // the other device to initiate device transfer. Note that server enforces a
                // 4096 bytes limit on this field.
                deviceTransferBootstrap.map {
                    parameters["deviceTransferBootstrap"] = Data($0.absoluteString.utf8).base64EncodedStringWithoutPadding()
                }

                let urlComponents = URLComponents(string: "v1/devices/restore_account/\(token)")!
                var request = TSRequest(
                    url: urlComponents.url!,
                    method: "PUT",
                    parameters: parameters,
                )

                request.auth = .anonymous
                request.applyRedactionStrategy(.redactURL(sensitiveValues: ["\(token)"]))
                return request
            }
        }
    }
}
