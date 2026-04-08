//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient
import MnemonicSwift
public import MobileCoin
public import SignalServiceKit
import BigNumber
public import BreezSdkSpark
import CryptoKit

public class PaymentsImpl: NSObject, PaymentsSwift {

    private let appReadiness: AppReadiness
    private var refreshBalanceEvent: RefreshEvent?

    fileprivate let paymentsReconciliation: PaymentsReconciliation

    private let paymentsProcessor: PaymentsProcessor
    
    private var onIncommingTransactionNotificationProcessing: NotificationCenter.Observer?

    public static let maxPaymentMemoMessageLength: Int = 32
    
    public static func isSatoshiAmountTypeEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: PaymentsConstants.satoshiAmountTypeEnabledKey)
    }
    
    public static func toggleSatoshiAmountType() -> Bool {
        let value = !UserDefaults.standard.bool(forKey: PaymentsConstants.satoshiAmountTypeEnabledKey)
        UserDefaults.standard.set(value, forKey: PaymentsConstants.satoshiAmountTypeEnabledKey)
        
        return value
    }

    @MainActor
    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        self.paymentsReconciliation = PaymentsReconciliation(appReadiness: appReadiness)
        self.paymentsProcessor = PaymentsProcessor(appReadiness: appReadiness)
        self.currentSdk = SetOnce<BreezSdk>()
        super.init()
        
        self.onIncommingTransactionNotificationProcessing = NotificationCenter.default.addObserver(name: Notification.Name("processIncomingPaymentNotification")) { _ in
            DispatchQueue.global().async { [weak self] in
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    self?.paymentsReconciliation.scheduleReconciliationNow(transaction: transaction)
                }
            }
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
    }
    
    public func initializeAsyncComponents() async {
        do {
            _ = try await getBreezSdk()
        } catch {
            owsFailDebug("Failed initialize async breez sdk with error: \(error)")
        }
        
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { [weak self] in
            guard self?.arePaymentsEnabled ?? false else {
                return
            }
            
            Task { [weak self] in
                do {
                    try await self?.updateLastKnownAddressAndReuploadProfile()
                } catch {
                    owsFailDebug("Failed to re-uploading local bitcoin lightning profile: \(error)")
                    DispatchQueue.main.async {
                        OWSActionSheets.showErrorAlert(message: "Failed to re-uploading local bitcoin lightning profile: \(error)")
                    }
                }
            }
            
            Task { [weak self] in
                do {
                    try await self?.setFetchRateHandler()
                } catch {
                    owsFailDebug("Set fetch rate handler has failed with error: \(error)")
                }
            }
            
            Task { [weak self] in
                do {
                    try await self?.updateFiatCurrencies()
                } catch {
                    owsFailDebug("Update fiat currencies list has failed with error: \(error)")
                }
            }
        }
    }

    // NOTE: This k-v store is shared by PaymentsHelperImpl and PaymentsImpl.
    fileprivate static var keyValueStore: KeyValueStore {
        SSKEnvironment.shared.paymentsHelperRef.keyValueStore
    }
    fileprivate var keyValueStore: KeyValueStore {
        SSKEnvironment.shared.paymentsHelperRef.keyValueStore
    }

    private func setFetchRateHandler() async throws {
        let sdk = try await getBreezSdk()
        
        guard let paymentsCurrencies = SSKEnvironment.shared.paymentsCurrenciesRef as? PaymentsCurrenciesImpl else {
            return
        }
        
        paymentsCurrencies.setFetchRateHandler { [sdk] in
            return (try await sdk.listFiatRates()).rates.map { rate in
                (rate.coin, rate.value)
            }
        }
    }
    
    private func updateFiatCurrencies() async throws {
        let sdk = try await getBreezSdk()
        let currencies = try await sdk.listFiatCurrencies().currencies.map { fiat in
            fiat.id
        }
        
        PaymentsCurrenciesImpl.setSupportedCurrencyCodesList(currencies)
    }

    private func updateLastKnownLocalPaymentAddressProtoDataIfNecessary() {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }
        guard appReadiness.isAppReady else {
            return
        }

        let appVersionKey = "appVersion"
        let currentAppVersion = AppVersionImpl.shared.currentAppVersion

        let shouldUpdate = SSKEnvironment.shared.databaseStorageRef.read { (transaction: DBReadTransaction) -> Bool in
            // Check if the app version has changed.
            let lastAppVersion = self.keyValueStore.getString(appVersionKey, transaction: transaction)
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

            self.keyValueStore.setString(currentAppVersion, key: appVersionKey, transaction: transaction)
        }
    }

    private var currentSdk: SetOnce<BreezSdk>

    public func didReceiveMCAuthError() {}
    
    private static func buildBreezSdkWith(paymentsEntropy: Data) async throws -> BreezSdk {
        let config = breezSdkConfig
        let seed = Seed.entropy(paymentsEntropy)
        let fileManager = FileManager.default
        let documentsDirectory = try fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let breezDirectory = documentsDirectory.appendingPathComponent(
            "breez",
            isDirectory: true
        )

        if !fileManager.fileExists(atPath: breezDirectory.path) {
            try fileManager.createDirectory(atPath: breezDirectory.path, withIntermediateDirectories: true)
        }

        let builder = SdkBuilder(config: config, seed: seed)
        await builder.withDefaultStorage(storageDir: breezDirectory.path)

        return try await builder.build()
    }

    private func getOrBuildBreezSdkWith(paymentsEntropy: Data) async throws -> BreezSdk {
        if let sdk = currentSdk.value {
            return sdk
        }
        
        do {
            let sdk = try await Self.buildBreezSdkWith(paymentsEntropy: paymentsEntropy)
            currentSdk.setOnce(sdk)
            try await validateInitialLightningAddress()

            return sdk
        } catch {
            owsFailDebug("Failed to build Breez SDK: \(error)")
            DispatchQueue.main.async {
                OWSActionSheets.showErrorAlert(message: "Failed to build Breez SDK: \(error)")
            }
            throw error
        }
    }
    
    private func validateInitialLightningAddress() async throws {
        let lightningAddress = try await self.getBreezSdk().getLightningAddress()

        if let lightningAddress = lightningAddress {
            if let lnurlDomain = breezSdkConfig.lnurlDomain,
               !lightningAddress.lightningAddress.contains("@\(lnurlDomain)") {
                await self.tryToRegisterLightningAddress()
            }
        } else {
            await self.tryToRegisterLightningAddress()
        }
    }
    
    private func tryToRegisterLightningAddress(rateLimit: Int = 5) async {
        for _ in 0...rateLimit {
            do {
                let username = generateUsername()
                let isAvailable = try await self.getBreezSdk()
                    .checkLightningAddressAvailable(req: CheckLightningAddressRequest(username: username))
                
                if isAvailable {
                    _ = try await self.getBreezSdk()
                        .registerLightningAddress(request: RegisterLightningAddressRequest(username: username))
                    updateLastKnownLocalPaymentAddressProtoDataIfNecessary()
                    return
                }
            } catch {
                owsFailDebug("Cannot to register lightning address. Error: \(error)")
                DispatchQueue.main.async {
                    OWSActionSheets.showErrorAlert(message: "Cannot to register lightning address. Error: \(error)")
                }
            }
        }
        
        owsFailDebug("Cannot to register lightning address. Out of rate limit: \(rateLimit)")
        DispatchQueue.main.async {
            OWSActionSheets.showErrorAlert(message: "Cannot to register lightning address. Out of rate limit: \(rateLimit)")
        }
    }
    
    private func generateUsername(withAci aci: String, prefixLength: Int = 10) throws -> String {
        guard let aciData = aci.data(using: .utf8) else {
            throw OWSAssertionError("Cannot get UTF-8 encoded data from ACI")
        }
        
        let hash = SHA256.hash(data: aciData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return String(hashString.prefix(prefixLength))
    }
    
    private func generateUsername(length: Int = 16) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            owsFailDebug("Failed to generate secure random bytes")
            return ""
        }
        
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func getBreezSdk() async throws -> BreezSdk {
        guard !CurrentAppContext().isNSE else {
            throw OWSAssertionError("Payments disabled in NSE.")
        }
        switch paymentsState {
        case .enabled(let paymentsEntropy):
            return try await getOrBuildBreezSdkWith(paymentsEntropy: paymentsEntropy)
        case .disabled, .disabledWithPaymentsEntropy:
            throw PaymentsError.notEnabled
        }
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
        do {
            let bytes = try MnemonicSwift.Mnemonic.deterministicSeedBytes(
                from: passphrase.asPassphrase)
            return Data(bytes)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
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

    public func findPaymentModels(withMCLedgerBlockIndex mcLedgerBlockIndex: UInt64,
                                  mcIncomingTransactionPublicKey: Data,
                                  transaction: DBReadTransaction) -> [TSPaymentModel] {
        PaymentFinder.paymentModels(forMcLedgerBlockIndex: mcLedgerBlockIndex,
                                    transaction: transaction).filter {
                                        let publicKeys = $0.mobileCoin?.incomingTransactionPublicKeys ?? []
                                        return publicKeys.contains(mcIncomingTransactionPublicKey)
                                    }
    }
}

// MARK: - Operations

public extension PaymentsImpl {

    private func fetchAddress(for recipientAci: Aci) async throws -> String {
        let profileFetcher = SSKEnvironment.shared.profileFetcherRef
        let fetchedProfile = try await profileFetcher.fetchProfileWithLightningBitcoinAddress(for: recipientAci)

        guard let decryptedProfile = fetchedProfile.decryptedProfile else {
            throw PaymentsError.userHasNoPublicAddress
        }

        // We don't need to persist this value in the cache; the ProfileFetcher
        // will take care of that.
        guard
            let paymentAddress = decryptedProfile.paymentAddress(identityKey: fetchedProfile.identityKey),
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
        preparedPayment: PrepareLnurlPayResponse,
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
        guard TSPaymentAmount(currency: .bitcoin, picoMob: preparedPayment.feeSats).isValidAmount(canBeEmpty: false) else {
            throw OWSAssertionError("Invalid fee.")
        }

        let paymentType: TSPaymentType = isOutgoingTransfer ? .outgoingTransfer : .outgoingPayment
        let recipientAddressData = recipientAddress.serializeData()
        let transactionData = preparedPayment.serializeData()
        let feeAmount = TSPaymentAmount(currency: .bitcoin, picoMob: preparedPayment.feeSats)
        let hash = preparedPayment.invoiceDetails.paymentHash.data(using: .utf8) ?? Data()
        
        let mobileCoin = MobileCoinPayment(
            recipientPublicAddressData: recipientAddressData,
            transactionData: transactionData,
            receiptData: nil,
            incomingTransactionPublicKeys: nil,
            spentKeyImages: [hash],
            outputPublicKeys: nil,
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

    // Only valid for the recipient
    public func unmaskReceiptAmount(data: Data?) -> MobileCoin.Amount? {
        guard let data = data else { return nil }
        let account = localMobileCoinAccount(paymentsState: self.paymentsState)
        guard let accountKey = account?.accountKey else { return nil }
        guard let receipt = Receipt(serializedData: data) else { return nil }
        guard let amount = receipt.validateAndUnmaskAmount(accountKey: accountKey) else {
            return nil
        }
        return amount
    }

    public func buildLocalPaymentAddress(paymentsState: PaymentsState) -> TSPaymentAddress? {
        owsAssertDebug(paymentsState.isEnabled)
        
        let address = walletAddressLNURL()
        guard let addressData = address?.data(using: .utf8) else {
            owsFailDebug("Missing wallet address.")
            return nil
        }
            
        return TSPaymentAddress(currency: .bitcoin, mobileCoinPublicAddressData: addressData)
    }
    
    public func walletAddressLNURL() -> String? {
        return walletAddress()?.lnurl.url
    }
    
    public func walletLightningAddress() -> String? {
        return walletAddress()?.lightningAddress
    }
    
    public func walletLightningAddressUsername() -> String? {
        return walletAddress()?.username
    }
    
    public func registerUsername(_ username: String) async throws {
        let paymentsState = self.paymentsState
        owsAssertDebug(paymentsState.isEnabled)
        
        _ = try await self.getBreezSdk().registerLightningAddress(request: RegisterLightningAddressRequest(username: username))
        try await updateLastKnownAddressAndReuploadProfile()
    }

    public func localPaymentAddressProtoData(paymentsState: PaymentsState, tx: DBReadTransaction)
        -> Data?
    {
        owsAssertDebug(paymentsState.isEnabled)

        guard let localPaymentAddress = buildLocalPaymentAddress(paymentsState: paymentsState)
        else {
            owsFailDebug("Missing localPaymentAddress.")
            return nil
        }
        guard localPaymentAddress.isValid, (localPaymentAddress.currency == .bitcoin) else {
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
        let data: Data?
        let paymentsState = self.paymentsState
        if paymentsState.isEnabled {
            data = localPaymentAddressProtoData(paymentsState: paymentsState, tx: transaction)
        } else {
            data = nil
        }

        SSKEnvironment.shared.paymentsHelperRef.setLastKnownLocalPaymentAddressProtoData(
            data, transaction: transaction)
    }
}

extension PaymentsImpl {
    private func updateLastKnownAddressAndReuploadProfile() async throws {
        try await DependenciesBridge.shared.db.write { tx in
            Logger.info("Re-uploading local bitcoin lightning profile")
            updateLastKnownLocalPaymentAddressProtoData(transaction: tx)
            return SSKEnvironment.shared.profileManagerRef.reuploadLocalProfileWithProfileKeyVersion(
                PaymentsConstants.bitcoinLightningProfileKeyVersion,
                unsavedRotatedProfileKey: nil,
                mustReuploadAvatar: false,
                authedAccount: .implicit(),
                tx: tx
            )
        }.awaitable()
    }
    
    private func walletAddress() -> LightningAddressInfo? {
        let paymentsState = self.paymentsState
        owsAssertDebug(paymentsState.isEnabled)
        let semaphore = DispatchSemaphore(value: 0)
        var address: LightningAddressInfo? = nil

        Task {
            do {
                guard let lightningAddress = try await self.getBreezSdk().getLightningAddress()
                else {
                    owsFailDebug("Missing lightning address")
                    semaphore.signal()
                    return
                }
                address = lightningAddress
                semaphore.signal()
            } catch {
                owsFailDebug("Failed to get lightning address: \(error)")
                semaphore.signal()
            }
        }

        semaphore.wait()
        return address
    }
}

// MARK: - Current Balance

extension PaymentsImpl {
    public func getCurrentBalance() async throws -> TSPaymentAmount {
        let sdk = try await self.getBreezSdk()
        let info = try await sdk.getInfo(request: GetInfoRequest(ensureSynced: true))
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
        let sdk = try await self.getBreezSdk()
        let recommendedFees = try await sdk.recommendedFees()

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
            let sdk = try await self.getBreezSdk()
            let recipentAddress = try await sdk.parse(input: recipientAddress);
            
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
        
        let sdk = try await self.getBreezSdk()

        switch recipientAddress {
        case .lnurlPay(let payRequest):
            let amountSats: UInt64 = paymentAmount.picoMob
            let optionalComment: String? = nil
            let optionalValidateSuccessActionUrl = true

            let request = PrepareLnurlPayRequest(
                amountSats: amountSats,
                payRequest: payRequest,
                comment: optionalComment,
                validateSuccessActionUrl: optionalValidateSuccessActionUrl
            )
            
            let preparedPayment = try await sdk.prepareLnurlPay(request: request)
            
            return PreparedPaymentImpl(
                recipientAci: recipientAci,
                recipientAddress: recipientAddress,
                paymentAmount: paymentAmount,
                memoMessage: memoMessage,
                isOutgoingTransfer: isOutgoingTransfer,
                preparedPayment: preparedPayment
            )
        case .lightningAddress(v1: let details):
            let amountSats: UInt64 = paymentAmount.picoMob
            let optionalComment: String? = nil
            let payRequest = details.payRequest
            let optionalValidateSuccessActionUrl = true

            let request = PrepareLnurlPayRequest(
                amountSats: amountSats,
                payRequest: payRequest,
                comment: optionalComment,
                validateSuccessActionUrl: optionalValidateSuccessActionUrl
            )
            
            let preparedPayment = try await sdk.prepareLnurlPay(request: request)
            
            return PreparedPaymentImpl(
                recipientAci: recipientAci,
                recipientAddress: recipientAddress,
                paymentAmount: paymentAmount,
                memoMessage: memoMessage,
                isOutgoingTransfer: isOutgoingTransfer,
                preparedPayment: preparedPayment
            )
        default:
            owsFail("Unsupported input type")
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
            preparedPayment: preparedPayment.preparedPayment,
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
            let _ = try? LnurlPayResponse.deserialize(from: mcReceiptData)
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
            let _ = try? LnurlPayResponse.deserialize(from: mcReceiptData)
        else {
            owsFailDebug("Missing mcReceiptData.")
            return
        }
        guard let transactionData = paymentModel.mcTransactionData,
            !transactionData.isEmpty,
            let _ = try? PrepareLnurlPayResponse.deserialize(from: transactionData)
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
    }

    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction) {
        let payments = SUIEnvironment.shared.paymentsRef as! PaymentsImpl
        payments.paymentsReconciliation.willUpdatePayment(paymentModel, transaction: transaction)
    }

    public func updateLastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction) {
        SUIEnvironment.shared.paymentsImplRef.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)
    }

    public func paymentsStateDidChange() {
        SUIEnvironment.shared.paymentsImplRef.updateCurrentPaymentBalance()
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

    public func replaceAsUnidentified(paymentModel oldPaymentModel: TSPaymentModel,
                               transaction: DBWriteTransaction) {
        paymentsReconciliation.replaceAsUnidentified(paymentModel: oldPaymentModel,
                                                     transaction: transaction)
    }

    // MARK: - URLs

    public static func format(inputType: InputType) -> String {
        switch inputType {
        case .lightningAddress(let details):
            return details.address
        default:
            owsFailDebug("Unsupported input type")
            return ""
        }
    }

    public static func parse(url: URL) -> InputType? {
        return parse(input: url.absoluteString)
    }

    public static func parse(input: String) -> InputType? {
        let semaphore = DispatchSemaphore(value: 0)
        var inputType: InputType? = nil

        Task {
            let sdk = try? await SUIEnvironment.shared.paymentsImplRef.getBreezSdk()
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
    
    public let preparedPayment: PrepareLnurlPayResponse
    
    public var feeAmount: TSPaymentAmount {
        return TSPaymentAmount(currency: .bitcoin, picoMob: preparedPayment.feeSats)
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


extension BreezSdk {
    func payment(by hash: String) async throws -> Payment? {
        let payments = try await listPayments(request: ListPaymentsRequest()).payments
        
        return payments.first {
            switch $0.details {
            case .lightning(_, _, _, let htlcDetails, _, _, _):
                return htlcDetails.paymentHash == hash
            case .spark(_, let htlcDetails, _):
                return htlcDetails?.paymentHash == hash
            default:
                return false
            }
        }
    }
}

extension Payment {
    var hash: String? {
        switch details {
        case .lightning(_, _, _, let htlcDetails, _, _, _):
            return htlcDetails.paymentHash
        case .spark(_, let htlcDetails, _):
            return htlcDetails?.paymentHash
        default:
            return nil
        }
    }
}
