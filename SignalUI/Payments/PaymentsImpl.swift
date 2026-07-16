//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BigNumber
public import BreezSdkSpark
import CryptoKit
import Foundation
public import LibSignalClient
import MnemonicSwift
public import MobileCoin
public import SignalServiceKit

public class PaymentsImpl: NSObject, PaymentsSwift {
    public static let maxPaymentMemoMessageLength: Int = 32

    public var walletAddressLNURL: String? {
        guard let url = currentWalletAddress?.lnurl.url, !url.isEmpty else {
            return nil
        }
        return url
    }

    public var walletLightningAddress: String? {
        currentWalletAddress?.lightningAddress
    }

    public var walletLightningAddressUsername: String? {
        currentWalletAddress?.username
    }

    fileprivate let paymentsReconciliation: PaymentsReconciliation

    // NOTE: This k-v store is shared by PaymentsHelperImpl and PaymentsImpl.
    fileprivate static var keyValueStore: KeyValueStore {
        SSKEnvironment.shared.paymentsHelperRef.keyValueStore
    }
    fileprivate var keyValueStore: KeyValueStore {
        SSKEnvironment.shared.paymentsHelperRef.keyValueStore
    }

    private let appReadiness: AppReadiness

    private var refreshBalanceEvent: RefreshEvent?

    private let paymentsProcessor: PaymentsProcessor

    private var onIncommingTransactionNotificationProcessing: NotificationCenter.Observer?

    private var onRegistrationStateChange: NotificationCenter.Observer?

    private var onWalletAddressDidLoad: NotificationCenter.Observer?
    private var onLocalProfileDidUpdateOnService: NotificationCenter.Observer?

    private let inflightReupload = AtomicOptional<Task<Void, Error>>(nil, lock: .sharedGlobal)

    private var currentSdk: BreezSdk?

    private var currentWalletAddress: LightningAddressInfo?

    public static func isSatoshiAmountTypeEnabled() -> Bool {
        PaymentsDisplayPreferences.shared.isSatoshiEnabled
    }

    @MainActor
    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        self.paymentsReconciliation = PaymentsReconciliation(appReadiness: appReadiness)
        self.paymentsProcessor = PaymentsProcessor(appReadiness: appReadiness)
        super.init()

        onIncommingTransactionNotificationProcessing = NotificationCenter.default.addObserver(
            name: Notification.Name("processIncomingPaymentNotification")
        ) { _ in
            DispatchQueue.global().async { [weak self] in
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    self?.paymentsReconciliation.scheduleReconciliationNow(transaction: transaction)
                }
            }
        }

        onRegistrationStateChange = NotificationCenter.default.addObserver(
            name: RegistrationStateChangeNotifications.registrationStateDidChange
        ) { [weak self] _ in
            self?.tryToReuploadPaymentProfile()

            DispatchQueue.global().async { [weak self] in
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    self?.paymentsReconciliation.scheduleReconciliationNow(transaction: transaction)
                }
            }
        }

        onWalletAddressDidLoad = NotificationCenter.default.addObserver(
            name: Self.walletAddressDidLoad
        ) { [weak self] _ in
            self?.reuploadPaymentProfileForLoadedWalletAddress()
        }

        // A standard-version profile upload (name/avatar edit, profile-key rotation, group/UD reupload,
        // LocalProfileChecker, etc.) makes the standard version the account's current server profile,
        // which hides the Lightning payment address stored at the fixed payment profile version. Re-
        // publish at the fixed version so it becomes current again and senders can read it.
        onLocalProfileDidUpdateOnService = NotificationCenter.default.addObserver(
            name: OWSProfileManager.localProfileDidUpdateOnService
        ) { [weak self] _ in
            self?.reuploadPaymentProfileForLoadedWalletAddress()
        }

        // Note: this isn't how often we refresh the balance, it's how often we
        // check whether we should refresh the balance.
        //
        // TODO: Tune.
        let refreshCheckInterval: TimeInterval = .minute * 5
        refreshBalanceEvent = RefreshEvent(
            appReadiness: appReadiness, refreshInterval: refreshCheckInterval
        ) { [weak self] in
            self?.updateCurrentPaymentBalanceIfNecessary()
        }

        // One-shot repair: payments whose receipts older builds couldn't decode (cross-version
        // breez layouts) have a chat message but no TSPaymentModel. Recreate the missing models
        // now that BreezReceiptParser reads every known layout.
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            BreezPaymentBackfill.runIfNeeded()
        }
    }

    public func initializeComponents(warmCaches: Bool = false) async {
        do {
            if warmCaches {
                SSKEnvironment.shared.paymentsHelperRef.warmCaches()
            }
            try await initializeBreezSdk()
            try await loadWalletAddress()
            try await setFetchRateHandler()
            try await updateFiatCurrencies()

            tryToReuploadPaymentProfile()
        } catch PaymentsError.notEnabled {
            return
        } catch {
            Logger.warn("Failed initialize components with error: \(error)")
            return
        }
    }

    fileprivate func reloadComponents() async {
        switch paymentsState {
        case .enabled(_):
            await initializeComponents()
        default:
            currentSdk = nil
            currentWalletAddress = nil
            tryToReuploadPaymentProfile()
        }
    }

    private func initializeBreezSdk() async throws {
        guard currentSdk == nil else {
            return
        }

        guard case .enabled(let paymentEntropy) = paymentsState else {
            throw PaymentsError.notEnabled
        }

        LightningLogger.installIfNeeded()

        currentSdk = try await BreezSdk.build(with: paymentEntropy)
        if let newAddress = try await currentSdk?.validateInitialLightningAddress() {
            currentWalletAddress = newAddress
        }
    }

    public func deletePaymentWallet() async throws {
        // Best-effort: deregister the lightning username and disconnect the SDK
        // before wiping local state. We don't fail the whole operation if these
        // calls error, because the user has already accepted that the wallet is
        // being destroyed locally.
        if let sdk = currentSdk {
            do {
                try await sdk.deleteLightningAddress()
            } catch {
                Logger.warn("deleteLightningAddress failed during wallet deletion: \(error)")
            }
            do {
                try await sdk.disconnect()
            } catch {
                Logger.warn("Breez disconnect failed during wallet deletion: \(error)")
            }
        }

        currentSdk = nil
        currentWalletAddress = nil

        let fileManager = FileManager.default
        if let documentsDirectory = try? fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) {
            let breezDirectory = documentsDirectory.appendingPathComponent(
                BreezSdk.Constants.defaultBreezDirectoryName,
                isDirectory: true
            )
            if fileManager.fileExists(atPath: breezDirectory.path) {
                do {
                    try fileManager.removeItem(at: breezDirectory)
                } catch {
                    Logger.warn("Failed to remove Breez storage directory: \(error)")
                }
            }
        }

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            SSKEnvironment.shared.paymentsHelperRef.resetPaymentsState(transaction: transaction)
        }

        // Strip the encrypted paymentAddress from the server profile now, instead
        // of waiting for the next unrelated profile upload. The KV cache was just
        // wiped, so VersionedProfilesImpl will upload no paymentAddress field.
        await DependenciesBridge.shared.db.awaitableWrite { transaction in
            _ = SSKEnvironment.shared.profileManagerRef.reuploadLocalProfileWithProfileKeyVersion(
                PaymentsConstants.bitcoinLightningProfileKeyVersion,
                unsavedRotatedProfileKey: nil,
                mustReuploadAvatar: false,
                authedAccount: .implicit(),
                tx: transaction
            )
        }

        paymentBalanceCache.set(nil)
    }

    private func loadWalletAddress() async throws {
        if currentWalletAddress != nil {
            NotificationCenter.default.postOnMainThread(name: Self.walletAddressDidLoad, object: nil)
            return
        }
        guard let lightningAddress = try await self.getBreezSdk().getLightningAddress() else {
            Logger.warn("No lightning address available yet — user may need to register a username.")
            return
        }
        currentWalletAddress = lightningAddress
        NotificationCenter.default.postOnMainThread(name: Self.walletAddressDidLoad, object: nil)
    }

    private func setFetchRateHandler() async throws {
        guard
            let paymentsCurrencies = SSKEnvironment.shared.paymentsCurrenciesRef
                as? PaymentsCurrenciesImpl
        else {
            return
        }

        let sdk = try getBreezSdk()

        paymentsCurrencies.setFetchRateHandler { [sdk] in
            return (try await sdk.listFiatRates()).rates.map { rate in
                (rate.coin, rate.value)
            }
        }
    }

    private func updateFiatCurrencies() async throws {
        let currencies = try await getBreezSdk().listFiatCurrencies().currencies.map { fiat in
            fiat.id
        }

        PaymentsCurrenciesImpl.setSupportedCurrencyCodesList(currencies)
    }

    private func tryToReuploadPaymentProfile() {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }
        Task {
            do {
                Logger.info("Trying to reupload payment profile")
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                try await self.updateLastKnownAddressAndReuploadPaymentProfile()
            } catch {
                owsFailDebug(
                    "Failed to update last known address and re-upload profile with error: \(error)"
                )
            }
        }
    }

    private func reuploadPaymentProfileForLoadedWalletAddress() {
        guard
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction
                .isRegistered
        else {
            return
        }
        // Only meaningful when payments are enabled and not killed; otherwise
        // there is no address to publish and VersionedProfilesImpl would drop it.
        guard paymentsState.isEnabled, !isKillSwitchActive else {
            return
        }
        // The notification is posted right after currentWalletAddress is set,
        // but guard anyway so we never re-upload a profile without an address.
        guard currentWalletAddress != nil else {
            return
        }
        Task {
            do {
                try await updateLastKnownAddressAndReuploadPaymentProfile()
            } catch {
                owsFailDebug(
                    "Failed to re-upload payment profile after wallet address loaded: \(error)"
                )
            }
        }
    }

    private func updateLastKnownLocalPaymentAddressProtoDataIfNecessary() {
        guard
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction
                .isRegistered
        else {
            return
        }
        guard appReadiness.isAppReady else {
            return
        }

        let appVersionKey = "appVersion"
        let currentAppVersion = AppVersionImpl.shared.currentAppVersion

        let shouldUpdate = SSKEnvironment.shared.databaseStorageRef.read {
            (transaction: DBReadTransaction) -> Bool in
            // Check if the app version has changed.
            let lastAppVersion = self.keyValueStore.getString(
                appVersionKey, transaction: transaction)
            guard lastAppVersion == currentAppVersion else {
                return true
            }
            return false
        }
        guard shouldUpdate else {
            return
        }
        Logger.info("Updating last known local payment address.")

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)

            self.keyValueStore.setString(
                currentAppVersion, key: appVersionKey, transaction: transaction)
        }
    }

    public func didReceiveMCAuthError() {}

    func getBreezSdk() throws -> BreezSdk {
        guard !CurrentAppContext().isNSE else {
            throw OWSAssertionError("Payments disabled in NSE.")
        }

        guard case .enabled(_) = paymentsState else {
            throw PaymentsError.notEnabled
        }

        guard let sdk = currentSdk else {
            throw OWSAssertionError("Current Breez SDK is not initialized!")
        }

        return sdk
    }

    public var hasValidPhoneNumberForPayments: Bool {
        SSKEnvironment.shared.paymentsHelperRef.hasValidPhoneNumberForPayments
    }

    public var isKillSwitchActive: Bool {
        SSKEnvironment.shared.paymentsHelperRef.isKillSwitchActive
    }

    public var canEnablePayments: Bool { SSKEnvironment.shared.paymentsHelperRef.canEnablePayments }

    public var shouldShowPaymentsUI: Bool {
        arePaymentsEnabled || canEnablePayments
    }

    // MARK: - PaymentsState

    public var paymentsState: PaymentsState {
        SSKEnvironment.shared.paymentsHelperRef.paymentsState
    }

    public var arePaymentsEnabled: Bool {
        SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled
    }

    public var paymentsEntropy: Data? {
        SSKEnvironment.shared.paymentsHelperRef.paymentsEntropy
    }

    public var passphrase: PaymentsPassphrase? {
        guard let paymentsEntropy = paymentsEntropy else {
            owsFailDebug("Missing paymentsEntropy.")
            return nil
        }
        return passphrase(forPaymentsEntropy: paymentsEntropy)
    }

    public func passphrase(forPaymentsEntropy paymentsEntropy: Data) -> PaymentsPassphrase? {
        do {
            let mnemonic = try MnemonicSwift.Mnemonic.mnemonicString(from: paymentsEntropy.toHex())
            let words = mnemonic.split(separator: " ").map { String($0) }
            return try PaymentsPassphrase(words: words)
        } catch {
            owsFailDebug("Passphrase error: \(error)")
            return nil
        }
    }

    public func paymentsEntropy(forPassphrase passphrase: PaymentsPassphrase) -> Data? {
        // This must be the exact inverse of passphrase(forPaymentsEntropy:) so that
        // restoring from the displayed phrase reconstructs the original wallet.
        // Do NOT use Mnemonic.deterministicSeedBytes here: that is the one-way
        // BIP-39 PBKDF2 mnemonic->seed derivation, not the mnemonic->entropy decode.
        Self.bip39Entropy(fromMnemonicWords: passphrase.words)
    }

    /// Decodes a BIP-39 mnemonic back to its entropy: each word is an 11-bit index
    /// into the wordlist; the trailing bits are a SHA-256 checksum of the entropy.
    /// Supports 12-word (16-byte) and 24-word (32-byte) phrases.
    /// Returns nil for unknown words or a checksum mismatch (i.e. a mistyped phrase).
    private static func bip39Entropy(fromMnemonicWords words: [String]) -> Data? {
        guard words.count == 12 || words.count == 24 else {
            Logger.warn("Invalid word count: \(words.count)")
            return nil
        }
        let wordlist = MnemonicSwift.MnemonicLanguageType.english.words()
        var bits = [Bool]()
        bits.reserveCapacity(words.count * 11)
        for word in words {
            guard let index = wordlist.firstIndex(of: word.lowercased()) else {
                Logger.warn("Word not in BIP-39 wordlist.")
                return nil
            }
            for bit in (0..<11).reversed() {
                bits.append((index >> bit) & 1 == 1)
            }
        }
        let checksumBitCount = bits.count / 33
        let entropyBitCount = bits.count - checksumBitCount
        var entropy = Data(count: entropyBitCount / 8)
        for i in 0..<entropyBitCount where bits[i] {
            entropy[i / 8] |= 1 << (7 - (i % 8))
        }
        // checksumBitCount is at most 8, so only the digest's first byte is used.
        guard let checksumByte = Data(SHA256.hash(data: entropy)).first else {
            return nil
        }
        for i in 0..<checksumBitCount {
            guard bits[entropyBitCount + i] == ((checksumByte >> (7 - i)) & 1 == 1) else {
                Logger.warn("Mnemonic checksum mismatch.")
                return nil
            }
        }
        return entropy
    }

    public func isValidPassphraseWord(_ word: String?) -> Bool {
        guard let word = word else {
            return false
        }

        return MnemonicSwift.MnemonicLanguageType.english.words().contains(word.lowercased())
    }

    public func clearState(transaction: DBWriteTransaction) {
        paymentBalanceCache.set(nil)
    }

    // MARK: - Public Keys

    public func isValidMobileCoinPublicAddress(_ publicAddressData: Data) -> Bool {
        return false
    }

    // MARK: - Balance

    public static let currentPaymentBalanceDidChange = Notification.Name(
        "currentPaymentBalanceDidChange")
    public static let incomingPaymentReceived = Notification.Name("incomingPaymentReceived")
    public static let walletAddressDidLoad = Notification.Name("walletAddressDidLoad")

    private let paymentBalanceCache = AtomicOptional<PaymentBalance>(nil, lock: .sharedGlobal)

    public var currentPaymentBalance: PaymentBalance? {
        paymentBalanceCache.get()
    }

    private func setCurrentPaymentBalance(amount: TSPaymentAmount) {
        owsAssertDebug(amount.isValidAmount(canBeEmpty: true))

        let balance = PaymentBalance(amount: amount, date: Date())

        let oldBalance = paymentBalanceCache.get()

        paymentBalanceCache.set(balance)

        if let oldAmount = oldBalance?.amount,
            oldAmount != amount
        {
            // When the balance changes, there might be new transactions
            // that aren't accounted for in the database yet. Perform
            // reconciliation to ensure we're up-to-date.
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
                self.scheduleReconciliationNow(transaction: transaction)
            }
        }

        // TODO: We could only fire if the value actually changed.
        NotificationCenter.default.postOnMainThread(
            name: Self.currentPaymentBalanceDidChange, object: nil)
    }

    private var canUsePayments: Bool {
        arePaymentsEnabled && !CurrentAppContext().isNSE
    }

    // We need to update our balance:
    //
    // * On launch.
    // * Periodically.
    // * After making or receiving payments.
    // * When user navigates into a view that displays the balance.
    public func updateCurrentPaymentBalance() {
        guard canUsePayments else {
            return
        }
        guard
            appReadiness.isAppReady,
            CurrentAppContext().isMainAppAndActive,
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction
                .isRegistered
        else {
            return
        }

        Task { @MainActor in
            do {
                _ = try await _updateCurrentPaymentBalance()
            } catch {
                let paymentsError = error as? PaymentsError
                let outdated =
                    paymentsError == .outdatedClient
                    || paymentsError == .attestationVerificationFailed
                SSKEnvironment.shared.paymentsHelperRef.setPaymentsVersionOutdated(outdated)
                owsFailDebug("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    private func _updateCurrentPaymentBalance() async throws -> TSPaymentAmount {
        let balance = try await self.getCurrentBalance()
        self.setCurrentPaymentBalance(amount: balance)
        return balance
    }

    private func updateCurrentPaymentBalanceIfNecessary() {
        guard CurrentAppContext().isMainApp else {
            return
        }
        if let lastUpdateDate = paymentBalanceCache.get()?.date {
            // Don't bother updating if we've already updated in the last N hours.
            guard abs(lastUpdateDate.timeIntervalSinceNow) > 4 * .hour else {
                return
            }
        }

        updateCurrentPaymentBalance()
    }

    public func clearCurrentPaymentBalance() {
        paymentBalanceCache.set(nil)
    }

    // MARK: -

    public func findPaymentModels(
        withMCLedgerBlockIndex mcLedgerBlockIndex: UInt64,
        mcIncomingTransactionPublicKey: Data,
        transaction: DBReadTransaction
    ) -> [TSPaymentModel] {
        PaymentFinder.paymentModels(
            forMcLedgerBlockIndex: mcLedgerBlockIndex,
            transaction: transaction
        ).filter {
            let publicKeys = $0.mobileCoin?.incomingTransactionPublicKeys ?? []
            return publicKeys.contains(mcIncomingTransactionPublicKey)
        }
    }
}

// MARK: - Operations

extension PaymentsImpl {

    private func fetchAddress(for recipientAci: Aci) async throws -> String {
        let profileFetcher = SSKEnvironment.shared.profileFetcherRef
        let fetchedProfile = try await profileFetcher.fetchProfileWithLightningBitcoinAddress(
            for: recipientAci)

        guard let decryptedProfile = fetchedProfile.decryptedProfile else {
            throw PaymentsError.userHasNoPublicAddress
        }

        // We don't need to persist this value in the cache; the ProfileFetcher
        // will take care of that.
        guard
            let paymentAddress = decryptedProfile.paymentAddress(
                identityKey: fetchedProfile.identityKey),
            paymentAddress.isValid,
            paymentAddress.currency == .bitcoin
        else {
            throw PaymentsError.userHasNoPublicAddress
        }
        do {
            return try paymentAddress.asAddress()
        } catch {
            owsFailDebug("Can't parse public address: \(error)")
            throw PaymentsError.userHasNoPublicAddress
        }
    }

    private func upsertNewOutgoingPaymentModel(
        recipientAci: Aci?,
        recipientAddress: InputType,
        paymentAmount: TSPaymentAmount,
        preparedTransaction: PreparedTransaction,
        memoMessage: String?,
        isOutgoingTransfer: Bool
    ) async throws -> TSPaymentModel {
        guard !isKillSwitchActive else {
            throw PaymentsError.killSwitch
        }
        guard paymentAmount.currency == .bitcoin, paymentAmount.isValidAmount(canBeEmpty: false)
        else {
            throw OWSAssertionError("Invalid amount.")
        }
        guard
            TSPaymentAmount(currency: .bitcoin, picoMob: preparedTransaction.feeSats).isValidAmount(
                canBeEmpty: false)
        else {
            throw OWSAssertionError("Invalid fee.")
        }

        let paymentType: TSPaymentType = isOutgoingTransfer ? .outgoingTransfer : .outgoingPayment
        let recipientAddressData = recipientAddress.serializeData()
        let transactionData = preparedTransaction.serializeData()
        let feeAmount = TSPaymentAmount(currency: .bitcoin, picoMob: preparedTransaction.feeSats)
        let hash = preparedTransaction.paymentHash.data(using: .utf8) ?? Data()

        let mobileCoin = MobileCoinPayment(
            recipientPublicAddressData: recipientAddressData,
            transactionData: transactionData,
            receiptData: nil,
            incomingTransactionPublicKeys: nil,
            spentKeyImages: [hash],
            outputPublicKeys: [hash],
            ledgerBlockTimestamp: 0,
            ledgerBlockIndex: 0,
            feeAmount: feeAmount,
        )

        let paymentModel = TSPaymentModel(
            paymentType: paymentType,
            paymentState: .outgoingUnsubmitted,
            paymentAmount: paymentAmount,
            createdDate: Date(),
            senderOrRecipientAci: recipientAci.map { AciObjC($0) },
            memoMessage: memoMessage?.nilIfEmpty,
            isUnread: false,
            interactionUniqueId: nil,
            mobileCoin: mobileCoin,
        )

        guard paymentModel.isValid else {
            throw OWSAssertionError("Invalid paymentModel.")
        }

        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            try SSKEnvironment.shared.paymentsHelperRef.tryToInsertPaymentModel(
                paymentModel, transaction: transaction)
        }

        return paymentModel
    }
}

// MARK: - TSPaymentAddress

extension PaymentsImpl {

    private func localMobileCoinAccount(paymentsState: PaymentsState) -> MobileCoinAPI
        .MobileCoinAccount?
    {
        guard let paymentsEntropy = paymentsState.paymentsEntropy else {
            owsFailDebug("Missing paymentsEntropy.")
            return nil
        }

        do {
            return try MobileCoinAPI.buildLocalAccount(paymentsEntropy: paymentsEntropy)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    /// The amount carried by a payment receipt, or nil when the receipt cannot be decoded.
    ///
    /// Radar receipts are breez `LnurlPayResponse` blobs (current-SDK layout, or the frozen
    /// 0.14.0 layout for receipts from old-breez senders); the amount is plaintext, so this
    /// works for sender and recipient alike. The MobileCoin receipt unmasking this replaced
    /// predates the fork and never matched breez bytes, which left recipient bubbles dependent
    /// on a TSPaymentModel that cross-version receipts could not create ("UNAVAILABLE sats").
    public func unmaskReceiptAmount(data: Data?) -> ParsedBreezReceipt? {
        return BreezReceiptParser.parse(data)
    }

    public func buildLocalPaymentAddress(paymentsState: PaymentsState) -> TSPaymentAddress? {
        owsAssertDebug(paymentsState.isEnabled)

        guard let addressData = walletAddressLNURL?.data(using: .utf8) else {
            Logger.warn("Missing wallet address — Breez SDK not yet initialized.")
            return nil
        }

        return TSPaymentAddress(currency: .bitcoin, mobileCoinPublicAddressData: addressData)
    }

    public func isUsernameAvailable(_ username: String) async throws -> Bool {
        return try await getBreezSdk().checkLightningAddressAvailable(
            req: CheckLightningAddressRequest(username: username))
    }

    public func fetchBitcoinTaprootAddress() async throws -> ReceivePaymentResponse {
        let sdk = try getBreezSdk()
        let response = try await sdk.receivePayment(
            request: ReceivePaymentRequest(
                paymentMethod: .bitcoinAddress(newAddress: nil)
            )
        )
        return response
    }


    public func registerUsername(_ username: String) async throws {
        let paymentsState = self.paymentsState
        owsAssertDebug(paymentsState.isEnabled)

        currentWalletAddress = try await self.getBreezSdk().registerLightningAddress(
            request: RegisterLightningAddressRequest(username: username))
        NotificationCenter.default.postOnMainThread(name: Self.walletAddressDidLoad, object: nil)
        try await updateLastKnownAddressAndReuploadPaymentProfile()
    }

    public func localPaymentAddressProtoData(paymentsState: PaymentsState, tx: DBReadTransaction)
        -> Data?
    {
        owsAssertDebug(paymentsState.isEnabled)

        guard let localPaymentAddress = buildLocalPaymentAddress(paymentsState: paymentsState)
        else {
            return nil
        }
        guard localPaymentAddress.isValid, localPaymentAddress.currency == .bitcoin else {
            owsFailDebug("Invalid localPaymentAddress.")
            return nil
        }

        do {
            let proto = try localPaymentAddress.buildProto(tx: tx)
            return try proto.serializedData()
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    public func updateLastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction) {
        // Never clear the cache from this opportunistic refresh path. Transient
        // states (unwarmed paymentStateCache at startup, unregistered ripples,
        // Breez SDK still loading) would otherwise wipe a perfectly good address
        // and cause the next unrelated profile upload to drop it from the server.
        // Explicit clearing on disable is handled in PaymentsHelperImpl.setPaymentsState.
        let paymentsState = self.paymentsState
        guard paymentsState.isEnabled else {
            return
        }
        guard let data = localPaymentAddressProtoData(paymentsState: paymentsState, tx: transaction) else {
            return
        }
        SSKEnvironment.shared.paymentsHelperRef.setLastKnownLocalPaymentAddressProtoData(
            data, transaction: transaction)
    }
}

extension PaymentsImpl {
    private func updateLastKnownAddressAndReuploadPaymentProfile() async throws {
        let task: Task<Void, Error> = inflightReupload.map { previous in
            Task<Void, Error> {
                _ = try? await previous?.value
                try await self.performBitcoinLightningProfileReupload()
            }
        }!
        try await task.value
    }

    private func performBitcoinLightningProfileReupload() async throws {
        if paymentsState.isEnabled, currentWalletAddress == nil {
            Logger.warn("Skipping payment profile re-upload: wallet address not loaded yet.")
            return
        }
        Logger.info("Re-uploading local profile as bitcoin lightning profile")
        _ = await DependenciesBridge.shared.db.awaitableWrite { transaction in
            updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)
            return SSKEnvironment.shared.profileManagerRef
                .reuploadLocalProfileWithProfileKeyVersion(
                    PaymentsConstants.bitcoinLightningProfileKeyVersion,
                    unsavedRotatedProfileKey: nil,
                    mustReuploadAvatar: false,
                    authedAccount: .implicit(),
                    tx: transaction
                )
        }
    }
}

// MARK: - Current Balance

extension PaymentsImpl {
    public func getCurrentBalance() async throws -> TSPaymentAmount {
        let info = try await self.getBreezSdk().getInfo(request: GetInfoRequest(ensureSynced: true))
        return TSPaymentAmount(currency: TSPaymentCurrency.bitcoin, picoMob: info.balanceSats)
    }
}

// MARK: - PaymentTransaction

extension PaymentsImpl {

    public func maximumPaymentAmount() async throws -> TSPaymentAmount {
        try await getCurrentBalance()
    }

    public func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) async throws
        -> TSPaymentAmount
    {
        let recommendedFees = try await self.getBreezSdk().recommendedFees()

        return TSPaymentAmount(currency: .bitcoin, picoMob: recommendedFees.fastestFee)
    }

    public func prepareOutgoingPayment(
        recipient: SendPaymentRecipient,
        paymentAmount: TSPaymentAmount,
        memoMessage: String?,
        isOutgoingTransfer: Bool,
        canDefragment: Bool
    ) async throws -> PreparedPayment {
        guard !isKillSwitchActive else {
            throw PaymentsError.killSwitch
        }
        guard let recipient = recipient as? SendPaymentRecipientImpl else {
            throw OWSAssertionError("Invalid recipient.")
        }

        switch recipient {
        case .address(let recipientAddress):
            // Cannot send "user-to-user" payment if kill switch is active.
            guard !SUIEnvironment.shared.paymentsRef.isKillSwitchActive else {
                throw PaymentsError.killSwitch
            }

            guard let recipientAci = recipientAddress.serviceId as? Aci else {
                throw PaymentsError.userHasNoPublicAddress
            }

            let recipientAddress = try await self.fetchAddress(for: recipientAci)
            let recipentAddress = try await self.getBreezSdk().parse(input: recipientAddress)

            return try await self.prepareOutgoingPayment(
                recipientAci: recipientAci,
                recipientAddress: recipentAddress,
                paymentAmount: paymentAmount,
                memoMessage: memoMessage,
                isOutgoingTransfer: isOutgoingTransfer,
                canDefragment: canDefragment
            )
        case .publicAddress(let recipientAddress):
            return try await prepareOutgoingPayment(
                recipientAci: nil,
                recipientAddress: recipientAddress,
                paymentAmount: paymentAmount,
                memoMessage: memoMessage,
                isOutgoingTransfer: isOutgoingTransfer,
                canDefragment: canDefragment
            )
        }
    }

    private func prepareOutgoingPayment(
        recipientAci: Aci?,
        recipientAddress: InputType,
        paymentAmount: TSPaymentAmount,
        memoMessage: String?,
        isOutgoingTransfer: Bool,
        canDefragment: Bool
    ) async throws -> PreparedPayment {
        guard !isKillSwitchActive else {
            throw PaymentsError.killSwitch
        }
        guard paymentAmount.currency == .bitcoin else {
            throw OWSAssertionError("Invalid currency.")
        }
        guard
            recipientAci
                != DependenciesBridge.shared.tsAccountManager
                .localIdentifiersWithMaybeSneakyTransaction?.aci
        else {
            throw OWSAssertionError("Can't make payment to yourself.")
        }

        let sdk = try self.getBreezSdk()

        switch recipientAddress {
        case .lnurlPay(let payRequest):
            let amountSats: UInt64 = paymentAmount.picoMob
            let optionalComment: String? = nil
            let optionalValidateSuccessActionUrl = true

            let request = PrepareLnurlPayRequest(
                amount: BInt(amountSats),
                payRequest: payRequest,
                comment: optionalComment,
                validateSuccessActionUrl: optionalValidateSuccessActionUrl,
                tokenIdentifier: nil
            )

            let preparedPayment = try await sdk.prepareLnurlPay(request: request)

            return PreparedPaymentImpl(
                recipientAci: recipientAci,
                recipientAddress: recipientAddress,
                paymentAmount: paymentAmount,
                memoMessage: memoMessage,
                isOutgoingTransfer: isOutgoingTransfer,
                preparedTransaction: .lnurlPay(preparedPayment)
            )
        case .lightningAddress(v1: let details):
            let amountSats: UInt64 = paymentAmount.picoMob
            let optionalComment: String? = nil
            let payRequest = details.payRequest
            let optionalValidateSuccessActionUrl = true

            let request = PrepareLnurlPayRequest(
                amount: BInt(amountSats),
                payRequest: payRequest,
                comment: optionalComment,
                validateSuccessActionUrl: optionalValidateSuccessActionUrl,
                tokenIdentifier: nil
            )

            let preparedPayment = try await sdk.prepareLnurlPay(request: request)

            return PreparedPaymentImpl(
                recipientAci: recipientAci,
                recipientAddress: recipientAddress,
                paymentAmount: paymentAmount,
                memoMessage: memoMessage,
                isOutgoingTransfer: isOutgoingTransfer,
                preparedTransaction: .lnurlPay(preparedPayment)
            )
        case .bolt11Invoice(let details):
            let isAmountless = details.amountMsat == nil
            let amount: U128? = isAmountless ? BInt(paymentAmount.picoMob) : nil

            let request = PrepareSendPaymentRequest(
                paymentRequest: PaymentRequest.input(input: details.invoice.bolt11),
                amount: amount,
                tokenIdentifier: nil,
                conversionOptions: nil,
                feePolicy: nil
            )

            let preparedPayment = try await sdk.prepareSendPayment(request: request)

            let resolvedAmount: TSPaymentAmount
            if let resolvedSats = UInt64(preparedPayment.amount.asString(radix: 10)) {
                resolvedAmount = TSPaymentAmount(currency: .bitcoin, picoMob: resolvedSats)
            } else {
                resolvedAmount = paymentAmount
            }

            return PreparedPaymentImpl(
                recipientAci: recipientAci,
                recipientAddress: recipientAddress,
                paymentAmount: resolvedAmount,
                memoMessage: memoMessage,
                isOutgoingTransfer: isOutgoingTransfer,
                preparedTransaction: .bolt11(preparedPayment)
            )
        default:
            throw PaymentsError.invalidInput
        }
    }

    private func defragmentIfNecessary(
        forPaymentAmount paymentAmount: TSPaymentAmount,
        mobileCoinAPI: MobileCoinAPI,
        canDefragment: Bool,
    ) async throws {
        let shouldDefragment = try await mobileCoinAPI.requiresDefragmentation(
            forPaymentAmount: paymentAmount
        ).awaitable()
        guard shouldDefragment else {
            return
        }
        guard canDefragment else {
            throw PaymentsError.defragmentationRequired
        }
        return try await self.defragment(
            forPaymentAmount: paymentAmount, mobileCoinAPI: mobileCoinAPI)
    }

    private func defragment(
        forPaymentAmount paymentAmount: TSPaymentAmount, mobileCoinAPI: MobileCoinAPI
    ) async throws {
        Logger.info("")

        // 1. Prepare defragmentation transactions.
        // 2. Record defragmentation transactions in database.
        //   3. Submit defragmentation transactions (payment processor will do this).
        //   4. Verify defragmentation transactions (payment processor will do this).
        // 5. Block on verification of defragmentation transactions.
        let mcTransactions = try await mobileCoinAPI.prepareDefragmentationStepTransactions(
            forPaymentAmount: paymentAmount
        ).awaitable()
        Logger.info("mcTransactions: \(mcTransactions.count)")

        // To initiate the defragmentation transactions, all we need to do
        // is save TSPaymentModels to the database. The PaymentsProcessor
        // will observe this and take responsibility for their submission,
        // verification.
        let paymentModels = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite {
            dbTransaction in
            return try mcTransactions.map { mcTransaction in
                let paymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: 0)
                let feeAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: mcTransaction.fee)
                let mcTransactionData = mcTransaction.serializedData
                let inputKeyImages = Array(Set(mcTransaction.inputKeyImages))
                owsAssertDebug(inputKeyImages.count == mcTransaction.inputKeyImages.count)
                let outputPublicKeys = Array(Set(mcTransaction.outputPublicKeys))
                owsAssertDebug(outputPublicKeys.count == mcTransaction.outputPublicKeys.count)
                let mobileCoin = MobileCoinPayment(
                    recipientPublicAddressData: nil,
                    transactionData: mcTransactionData,
                    receiptData: nil,
                    incomingTransactionPublicKeys: nil,
                    spentKeyImages: inputKeyImages,
                    outputPublicKeys: outputPublicKeys,
                    ledgerBlockTimestamp: 0,
                    ledgerBlockIndex: 0,
                    feeAmount: feeAmount,
                )

                let paymentModel = TSPaymentModel(
                    paymentType: .outgoingDefragmentation,
                    paymentState: .outgoingUnsubmitted,
                    paymentAmount: paymentAmount,
                    createdDate: Date(),
                    senderOrRecipientAci: nil,
                    memoMessage: nil,
                    isUnread: false,
                    interactionUniqueId: nil,
                    mobileCoin: mobileCoin,
                )

                guard paymentModel.isValid else {
                    throw OWSAssertionError("Invalid paymentModel.")
                }

                try SSKEnvironment.shared.paymentsHelperRef.tryToInsertPaymentModel(
                    paymentModel, transaction: dbTransaction)

                return paymentModel
            }
        }

        return try await self.blockOnVerificationOfDefragmentation(paymentModels: paymentModels)
    }

    public func initiateOutgoingPayment(preparedPayment: PreparedPayment) async throws
        -> TSPaymentModel
    {
        guard !isKillSwitchActive else {
            throw PaymentsError.killSwitch
        }
        guard let preparedPayment = preparedPayment as? PreparedPaymentImpl else {
            throw OWSAssertionError("Invalid preparedPayment.")
        }

        // To initiate the outgoing payment, all we need to do is save
        // the TSPaymentModel to the database. The PaymentsProcessor
        // will observe this and take responsibility for the submission,
        // verification and notification of the payment.
        return try await self.upsertNewOutgoingPaymentModel(
            recipientAci: preparedPayment.recipientAci,
            recipientAddress: preparedPayment.recipientAddress,
            paymentAmount: preparedPayment.paymentAmount,
            preparedTransaction: preparedPayment.preparedTransaction,
            memoMessage: preparedPayment.memoMessage,
            isOutgoingTransfer: preparedPayment.isOutgoingTransfer
        )
    }

    private func blockOnVerificationOfDefragmentation(paymentModels: [TSPaymentModel]) async throws
    {
        let maxBlockInterval: TimeInterval = .second * 30

        do {
            try await withCooperativeTimeout(seconds: maxBlockInterval) {
                try await withThrowingTaskGroup { taskGroup in
                    for paymentModel in paymentModels {
                        taskGroup.addTask {
                            guard
                                try await self.blockOnOutgoingVerification(
                                    paymentModel: paymentModel)
                            else {
                                throw PaymentsError.defragmentationFailed
                            }
                        }
                    }
                    try await taskGroup.waitForAll()
                }
            }
        } catch is CooperativeTimeoutError {
            throw PaymentsError.timeout
        }
    }

    public func blockOnOutgoingVerification(paymentModel: TSPaymentModel) async throws -> Bool {
        while true {
            let paymentModelLatest = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId, transaction: transaction)
            }
            guard let paymentModel = paymentModelLatest else {
                throw PaymentsError.missingModel
            }

            switch paymentModel.paymentState {
            case .outgoingUnsubmitted,
                .outgoingUnverified:
                // Not yet verified, wait then try again.
                try await Task.sleep(nanoseconds: 50_000_000)
            // loop by not returning
            case .outgoingVerified,
                .outgoingSending,
                .outgoingSent,
                .outgoingComplete:
                // Success: Verified.
                return true
            case .outgoingFailed:
                // Success: Failed.
                return false
            case .incomingUnverified,
                .incomingVerified,
                .incomingComplete,
                .incomingFailed:
                owsFailDebug("Unexpected paymentState: \(paymentModel.descriptionForLogs)")
                throw PaymentsError.invalidModel
            @unknown default:
                owsFailDebug("Invalid paymentState: \(paymentModel.descriptionForLogs)")
                throw PaymentsError.invalidModel
            }
        }
    }

    public class func sendDefragmentationSyncMessage(
        paymentModel: TSPaymentModel,
        transaction: DBWriteTransaction
    ) {
        guard paymentModel.isDefragmentation else {
            owsFailDebug("Invalid paymentType.")
            return
        }
        guard let paymentAmount = paymentModel.paymentAmount,
            paymentAmount.currency == .mobileCoin,
            paymentAmount.isValidAmount(canBeEmpty: true),
            paymentAmount.picoMob == 0
        else {
            owsFailDebug("Missing or invalid paymentAmount.")
            return
        }
        guard let feeAmount = paymentModel.mobileCoin?.feeAmount,
            feeAmount.currency == .mobileCoin,
            feeAmount.isValidAmount(canBeEmpty: false)
        else {
            owsFailDebug("Missing or invalid feeAmount.")
            return
        }
        guard let mcTransactionData = paymentModel.mcTransactionData,
            !mcTransactionData.isEmpty,
            let mcTransaction = MobileCoin.Transaction(serializedData: mcTransactionData)
        else {
            owsFailDebug("Missing or invalid mcTransactionData.")
            return
        }
        guard let mcReceiptData = paymentModel.mcReceiptData,
            !mcReceiptData.isEmpty,
            (try? LnurlPayResponse.deserialize(from: mcReceiptData)) != nil
        else {
            owsFailDebug("Missing or invalid mcReceiptData.")
            return
        }
        let mcSpentKeyImages = Array(mcTransaction.inputKeyImages)
        guard !mcSpentKeyImages.isEmpty else {
            owsFailDebug("Missing or invalid mcSpentKeyImages.")
            return
        }
        let mcOutputPublicKeys = Array(mcTransaction.outputPublicKeys)
        guard !mcOutputPublicKeys.isEmpty else {
            owsFailDebug("Missing or invalid mcOutputPublicKeys.")
            return
        }

        _ = sendOutgoingPaymentSyncMessage(
            recipientAci: nil,
            recipientAddress: nil,
            paymentAmount: paymentAmount,
            feeAmount: feeAmount,
            mcLedgerBlockTimestamp: paymentModel.mcLedgerBlockTimestamp,
            mcLedgerBlockIndex: paymentModel.mcLedgerBlockIndex,
            memoMessage: nil,
            mcSpentKeyImages: mcSpentKeyImages,
            mcOutputPublicKeys: mcOutputPublicKeys,
            mcReceiptData: mcReceiptData,
            isDefragmentation: true,
            transaction: transaction)
    }

    public class func sendPaymentNotificationMessage(
        paymentModel: TSPaymentModel,
        messageBody: ValidatedMessageBody?,
        transaction: DBWriteTransaction
    ) throws -> OWSOutgoingPaymentMessage {
        guard paymentModel.paymentType == .outgoingPayment else {
            owsFailDebug("Invalid paymentType.")
            throw PaymentsError.invalidModel
        }
        guard paymentModel.paymentState == .outgoingVerified else {
            owsFailDebug("Invalid paymentState: \(paymentModel.paymentState.formatted).")
            throw PaymentsError.invalidModel
        }
        guard let paymentAmount = paymentModel.paymentAmount else {
            owsFailDebug("Missing paymentAmount.")
            throw PaymentsError.invalidModel
        }
        guard paymentAmount.currency == .mobileCoin || paymentAmount.currency == .bitcoin else {
            owsFailDebug("Invalid currency.")
            throw PaymentsError.invalidModel
        }
        guard paymentAmount.picoMob > 0 else {
            owsFailDebug("Invalid amount.")
            throw PaymentsError.invalidModel
        }
        guard let recipientAci = paymentModel.senderOrRecipientAci?.wrappedAciValue else {
            owsFailDebug("Invalid recipientAci.")
            throw PaymentsError.invalidModel
        }
        guard let mcTransactionData = paymentModel.mcTransactionData,
            mcTransactionData.count > 0
        else {
            owsFailDebug("Missing mcTransactionData.")
            throw PaymentsError.invalidModel
        }
        guard let mcReceiptData = paymentModel.mcReceiptData,
            mcReceiptData.count > 0
        else {
            owsFailDebug("Missing mcReceiptData.")
            throw PaymentsError.invalidModel
        }

        let message = self.sendPaymentNotificationMessage(
            paymentModel: paymentModel,
            recipientAci: recipientAci,
            messageBody: messageBody,
            mcReceiptData: mcReceiptData,
            transaction: transaction
        )
        return message
    }

    public class func sendOutgoingPaymentSyncMessage(
        paymentModel: TSPaymentModel,
        transaction: DBWriteTransaction
    ) {

        guard let recipientAci = paymentModel.senderOrRecipientAci else {
            owsFailDebug("Missing recipientAci.")
            return
        }
        guard let recipientAddress = paymentModel.mobileCoin?.recipientPublicAddressData else {
            owsFailDebug("Missing recipientAddress.")
            return
        }
        guard paymentModel.paymentType == .outgoingPayment else {
            owsFailDebug("Invalid paymentType.")
            return
        }
        guard let paymentAmount = paymentModel.paymentAmount,
            paymentAmount.currency == .bitcoin,
            paymentAmount.isValidAmount(canBeEmpty: false)
        else {
            owsFailDebug("Missing or invalid paymentAmount.")
            return
        }
        guard let feeAmount = paymentModel.mobileCoin?.feeAmount,
            feeAmount.currency == .bitcoin,
            feeAmount.isValidAmount(canBeEmpty: false)
        else {
            owsFailDebug("Missing or invalid feeAmount.")
            return
        }
        guard let mcReceiptData = paymentModel.mcReceiptData,
            !mcReceiptData.isEmpty,
            (try? LnurlPayResponse.deserialize(from: mcReceiptData)) != nil
        else {
            owsFailDebug("Missing mcReceiptData.")
            return
        }
        guard let transactionData = paymentModel.mcTransactionData,
            !transactionData.isEmpty,
            (try? PrepareLnurlPayResponse.deserialize(from: transactionData)) != nil
        else {
            owsFailDebug("Missing or invalid mcTransactionData.")
            return
        }

        _ = sendOutgoingPaymentSyncMessage(
            recipientAci: recipientAci.wrappedAciValue,
            recipientAddress: recipientAddress,
            paymentAmount: paymentAmount,
            feeAmount: feeAmount,
            mcLedgerBlockTimestamp: paymentModel.mcLedgerBlockTimestamp,
            mcLedgerBlockIndex: paymentModel.mcLedgerBlockIndex,
            memoMessage: paymentModel.memoMessage,
            mcSpentKeyImages: [],
            mcOutputPublicKeys: [],
            mcReceiptData: mcReceiptData,
            isDefragmentation: false,
            transaction: transaction)

    }
}

// MARK: - Messages

extension PaymentsImpl {
    private class func sendPaymentNotificationMessage(
        paymentModel: TSPaymentModel,
        recipientAci: Aci,
        messageBody: ValidatedMessageBody?,
        mcReceiptData: Data,
        transaction: DBWriteTransaction
    ) -> OWSOutgoingPaymentMessage {

        if let paymentModel = TSPaymentModel.anyFetch(
            uniqueId: paymentModel.uniqueId, transaction: transaction),
            let interactionUniqueId = paymentModel.interactionUniqueId
        {
            if let existingInteraction = TSInteraction.anyFetch(
                uniqueId: interactionUniqueId, transaction: transaction),
                let message = existingInteraction as? OWSOutgoingPaymentMessage
            {
                // We already have a message, no need to send anything.
                return message
            } else {
                owsFailBeta("Missing or incorrect interaction type")
            }
        }

        let thread = TSContactThread.getOrCreateThread(
            withContactAddress: SignalServiceAddress(recipientAci),
            transaction: transaction
        )
        let paymentNotification = TSPaymentNotification(
            memoMessage: paymentModel.memoMessage,
            mcReceiptData: mcReceiptData
        )
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let dmConfig = dmConfigurationStore.fetchOrBuildDefault(
            for: .thread(thread), tx: transaction)

        let message = OWSOutgoingPaymentMessage(
            thread: thread,
            messageBody: messageBody,
            paymentNotification: paymentNotification,
            expiresInSeconds: dmConfig.durationSeconds,
            expireTimerVersion: dmConfig.timerVersion,
            tx: transaction
        )

        paymentModel.update(withInteractionUniqueId: message.uniqueId, transaction: transaction)
        // No attachments to add.
        let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(
            message,
            body: messageBody,
        )

        ThreadUtil.enqueueMessage(
            unpreparedMessage,
            thread: thread
        )

        return message
    }

    public class func sendOutgoingPaymentSyncMessage(
        recipientAci: Aci?,
        recipientAddress: Data?,
        paymentAmount: TSPaymentAmount,
        feeAmount: TSPaymentAmount,
        mcLedgerBlockTimestamp: UInt64?,
        mcLedgerBlockIndex: UInt64?,
        memoMessage: String?,
        mcSpentKeyImages: [Data],
        mcOutputPublicKeys: [Data],
        mcReceiptData: Data,
        isDefragmentation: Bool,
        transaction: DBWriteTransaction
    ) -> TSOutgoingMessage? {

        guard let thread = TSContactThread.getOrCreateLocalThread(transaction: transaction) else {
            owsFailDebug("Missing local thread.")
            return nil
        }
        let mobileCoin = OutgoingPaymentMobileCoin(
            recipientAci: recipientAci.map { AciObjC($0) },
            recipientAddress: recipientAddress,
            amountPicoMob: paymentAmount.picoMob,
            feePicoMob: feeAmount.picoMob,
            blockIndex: mcLedgerBlockIndex ?? 0,
            blockTimestamp: mcLedgerBlockTimestamp ?? 0,
            memoMessage: memoMessage?.nilIfEmpty,
            spentKeyImages: mcSpentKeyImages,
            outputPublicKeys: mcOutputPublicKeys,
            receiptData: mcReceiptData,
            isDefragmentation: isDefragmentation
        )
        let message = OutgoingPaymentSyncMessage(
            localThread: thread,
            mobileCoin: mobileCoin,
            transaction: transaction
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: message
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(
            message: preparedMessage, transaction: transaction)
        return message
    }
}

// MARK: -

public class PaymentsEventsMainApp: NSObject, PaymentsEvents {
    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction) {
        let payments = SUIEnvironment.shared.paymentsRef as! PaymentsImpl

        payments.paymentsReconciliation.willInsertPayment(paymentModel, transaction: transaction)

        // If we're inserting a new payment of any kind, our balance may have changed.
        payments.updateCurrentPaymentBalance()

        if paymentModel.isIncoming {
            let picoMob = paymentModel.paymentAmount?.picoMob ?? 0
            transaction.addSyncCompletion {
                NotificationCenter.default.postOnMainThread(
                    name: PaymentsImpl.incomingPaymentReceived,
                    object: nil,
                    userInfo: ["picoMob": picoMob]
                )
            }
        }
    }

    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction) {
        let payments = SUIEnvironment.shared.paymentsRef as! PaymentsImpl
        payments.paymentsReconciliation.willUpdatePayment(paymentModel, transaction: transaction)
    }

    public func updateLastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction) {
        guard let paymentsImpl = SUIEnvironment.shared.paymentsRef as? PaymentsImpl else {
            Logger.warn("Skipping payment address refresh: PaymentsImpl not ready yet.")
            return
        }
        paymentsImpl.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)
    }

    public func paymentsStateDidChange() {
        Task {
            await SUIEnvironment.shared.paymentsImplRef.reloadComponents()
            SUIEnvironment.shared.paymentsImplRef.updateCurrentPaymentBalance()
        }
    }

    public func clearState(transaction: DBWriteTransaction) {
        SSKEnvironment.shared.paymentsHelperRef.clearState(transaction: transaction)
        SUIEnvironment.shared.paymentsRef.clearState(transaction: transaction)
    }
}

// MARK: -

extension PaymentsImpl {

    public func scheduleReconciliationNow(transaction: DBWriteTransaction) {
        paymentsReconciliation.scheduleReconciliationNow(transaction: transaction)
    }

    public func replaceAsUnidentified(
        paymentModel oldPaymentModel: TSPaymentModel,
        transaction: DBWriteTransaction
    ) {
        paymentsReconciliation.replaceAsUnidentified(
            paymentModel: oldPaymentModel,
            transaction: transaction)
    }

    // MARK: - URLs

    public static func format(inputType: InputType) -> String {
        switch inputType {
        case .lightningAddress(let details):
            return details.address
        case .bolt11Invoice(let details):
            return details.invoice.bolt11
        default:
            owsFailDebug("Unsupported input type")
            return ""
        }
    }

    public static func formatForDisplay(inputType: InputType) -> String {
        switch inputType {
        case .bolt11Invoice(let details):
            return Self.abbreviate(details.invoice.bolt11)
        default:
            return format(inputType: inputType)
        }
    }

    private static func abbreviate(_ value: String) -> String {
        let prefixLength = 10
        let suffixLength = 9
        guard value.count > prefixLength + suffixLength + 1 else {
            return value
        }
        return "\(value.prefix(prefixLength))…\(value.suffix(suffixLength))"
    }

    public static func parse(url: URL) -> InputType? {
        return parse(input: url.absoluteString)
    }

    public static func parse(input: String) -> InputType? {
        let semaphore = DispatchSemaphore(value: 0)
        var inputType: InputType? = nil

        Task {
            let sdk = try? SUIEnvironment.shared.paymentsImplRef.getBreezSdk()
            inputType = try? await sdk?.parse(input: input)
            semaphore.signal()
        }

        semaphore.wait()
        return inputType
    }
}

// MARK: -

public enum SendPaymentRecipientImpl: SendPaymentRecipient {
    case address(address: SignalServiceAddress)
    case publicAddress(inputType: InputType)

    public var address: SignalServiceAddress? {
        switch self {
        case .address(let address):
            return address
        case .publicAddress:
            return nil
        }
    }

    public var isIdentifiedPayment: Bool {
        address != nil
    }
}

// MARK: -

public struct PreparedPaymentImpl: PreparedPayment {
    fileprivate let recipientAci: Aci?
    fileprivate let recipientAddress: InputType
    fileprivate let paymentAmount: TSPaymentAmount
    fileprivate let memoMessage: String?
    fileprivate let isOutgoingTransfer: Bool

    public let preparedTransaction: PreparedTransaction

    public var feeAmount: TSPaymentAmount {
        return TSPaymentAmount(currency: .bitcoin, picoMob: preparedTransaction.feeSats)
    }
}

extension MobileCoin.Amount {
    public var tsPaymentAmount: TSPaymentAmount? {
        TSPaymentAmount(
            currency: self.tokenId == .MOB ? .mobileCoin : .unknown,
            picoMob: self.value
        )
    }
}

extension PrepareLnurlPayResponse {
    public static func deserialize(from data: Data) throws -> Self {
        var input = (data: data, offset: 0)
        return try FfiConverterTypePrepareLnurlPayResponse.read(from: &input)
    }

    public func serializeData() -> Data {
        var bytes = [UInt8]()
        FfiConverterTypePrepareLnurlPayResponse.write(self, into: &bytes)
        return Data(bytes)
    }
}

extension LnurlPayResponse {
    public static func deserialize(from data: Data) throws -> Self {
        var input = (data: data, offset: 0)
        return try FfiConverterTypeLnurlPayResponse.read(from: &input)
    }

    public func serializeData() -> Data {
        var bytes = [UInt8]()
        FfiConverterTypeLnurlPayResponse.write(self, into: &bytes)
        return Data(bytes)
    }
}

extension PrepareSendPaymentResponse {
    public static func deserialize(from data: Data) throws -> Self {
        var input = (data: data, offset: 0)
        return try FfiConverterTypePrepareSendPaymentResponse.read(from: &input)
    }

    public func serializeData() -> Data {
        var bytes = [UInt8]()
        FfiConverterTypePrepareSendPaymentResponse.write(self, into: &bytes)
        return Data(bytes)
    }
}

extension SendPaymentResponse {
    public static func deserialize(from data: Data) throws -> Self {
        var input = (data: data, offset: 0)
        return try FfiConverterTypeSendPaymentResponse.read(from: &input)
    }

    public func serializeData() -> Data {
        var bytes = [UInt8]()
        FfiConverterTypeSendPaymentResponse.write(self, into: &bytes)
        return Data(bytes)
    }
}

extension InputType {
    public static func deserialize(from data: Data) throws -> Self {
        var input = (data: data, offset: 0)
        return try FfiConverterTypeInputType.read(from: &input)
    }

    public func serializeData() -> Data {
        var bytes = [UInt8]()
        FfiConverterTypeInputType.write(self, into: &bytes)
        return Data(bytes)
    }
}

// MARK: -

public enum PreparedTransaction {
    case lnurlPay(PrepareLnurlPayResponse)
    case bolt11(PrepareSendPaymentResponse)

    fileprivate static let bolt11Magic = Data("BOLT".utf8)

    public var feeSats: UInt64 {
        switch self {
        case .lnurlPay(let response):
            return response.feeSats
        case .bolt11(let response):
            switch response.paymentMethod {
            case .bolt11Invoice(_, let sparkTransferFeeSats, let lightningFeeSats):
                return sparkTransferFeeSats ?? lightningFeeSats
            case .bitcoinAddress, .sparkAddress, .sparkInvoice, .crossChainAddress:
                owsFailDebug("Unexpected payment method for BOLT11 invoice.")
                return 0
            }
        }
    }

    public var paymentHash: String {
        switch self {
        case .lnurlPay(let response):
            return response.invoiceDetails.paymentHash
        case .bolt11(let response):
            switch response.paymentMethod {
            case .bolt11Invoice(let invoiceDetails, _, _):
                return invoiceDetails.paymentHash
            case .bitcoinAddress, .sparkAddress, .sparkInvoice, .crossChainAddress:
                owsFailDebug("Unexpected payment method for BOLT11 invoice.")
                return ""
            }
        }
    }

    public func serializeData() -> Data {
        switch self {
        case .lnurlPay(let response):
            return response.serializeData()
        case .bolt11(let response):
            return Self.bolt11Magic + response.serializeData()
        }
    }

    public static func deserialize(from data: Data) -> PreparedTransaction? {
        if data.starts(with: bolt11Magic) {
            let payload = data.suffix(from: data.startIndex + bolt11Magic.count)
            guard let response = try? PrepareSendPaymentResponse.deserialize(from: Data(payload)) else {
                return nil
            }
            return .bolt11(response)
        } else {
            guard let response = try? PrepareLnurlPayResponse.deserialize(from: data) else {
                return nil
            }
            return .lnurlPay(response)
        }
    }
}

public enum PaymentReceipt {
    case lnurlPay(LnurlPayResponse)
    case bolt11(SendPaymentResponse)

    fileprivate static let bolt11Magic = Data("BOLT".utf8)

    public var paymentId: String {
        switch self {
        case .lnurlPay(let response):
            return response.payment.id
        case .bolt11(let response):
            return response.payment.id
        }
    }

    public func serializeData() -> Data {
        switch self {
        case .lnurlPay(let response):
            return response.serializeData()
        case .bolt11(let response):
            return Self.bolt11Magic + response.serializeData()
        }
    }

    public static func deserialize(from data: Data) -> PaymentReceipt? {
        if data.starts(with: bolt11Magic) {
            let payload = data.suffix(from: data.startIndex + bolt11Magic.count)
            guard let response = try? SendPaymentResponse.deserialize(from: Data(payload)) else {
                return nil
            }
            return .bolt11(response)
        } else {
            guard let response = try? LnurlPayResponse.deserialize(from: data) else {
                return nil
            }
            return .lnurlPay(response)
        }
    }
}

extension BreezSdk {
    func payment(by hash: String) async throws -> Payment? {
        let payments = try await listPayments(request: ListPaymentsRequest()).payments

        return payments.first(where: { payment in
            switch payment.details {
            case .lightning(_, _, _, let htlcDetails, _, _, _, _):
                return htlcDetails.paymentHash == hash
            case .spark(_, let htlcDetails, _):
                return htlcDetails?.paymentHash == hash
            default:
                return false
            }
        })
    }
}

extension Payment {
    var hash: String? {
        switch details {
        case .lightning(_, _, _, let htlcDetails, _, _, _, _):
            return htlcDetails.paymentHash
        case .spark(_, let htlcDetails, _):
            return htlcDetails?.paymentHash
        default:
            return nil
        }
    }
}
