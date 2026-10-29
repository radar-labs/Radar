//
// Copyright 2026 Radar contributors
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CryptoKit
import Security
import UIKit
import CMonero
import SignalServiceKit

public enum MoneroNetwork: Int, Codable, Sendable {
    case mainnet = 0
    case testnet = 1
    case stagenet = 2

    fileprivate var nativeValue: Int32 { Int32(rawValue) }
}

public struct MoneroNode: Codable, Equatable, Sendable {
    public let endpoint: String
    public let username: String?
    public let password: String?

    public init(endpoint: String, username: String? = nil, password: String? = nil) {
        self.endpoint = endpoint
        self.username = username
        self.password = password
    }

    fileprivate func daemonConfiguration() throws -> (address: String, useSSL: Bool) {
        guard let components = URLComponents(string: endpoint),
              let host = components.host,
              !host.isEmpty else {
            throw MoneroWalletError.invalidNode
        }

        let scheme = (components.scheme ?? "http").lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw MoneroWalletError.invalidNode
        }

        let address = components.port.map { "\(host):\($0)" } ?? host
        return (address, scheme == "https")
    }

    fileprivate func daemonConfiguration(for network: MoneroNetwork) throws -> (address: String, useSSL: Bool) {
        let configuration = try daemonConfiguration()
        guard network != .mainnet || configuration.useSSL else {
            throw MoneroWalletError.insecureNode
        }
        return configuration
    }
}

public struct MoneroManagedNode: Decodable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let endpoint: String
}

public enum MoneroNodeDirectory {
    private static let remoteConfigKey = "ios.moneroNodes"
    private static let customNodesKey = "radar.monero.customNodes.v1"

    public static var managedNodes: [MoneroManagedNode] {
        let configured = RemoteConfig.current.debugDescriptions()[remoteConfigKey]
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([MoneroManagedNode].self, from: $0) } ?? []
        var seen = Set<String>()
        return configured.filter { node in
            guard isSecureEndpoint(node.endpoint), !node.name.isEmpty else { return false }
            return seen.insert(node.endpoint.lowercased()).inserted
        }
    }

    public static var availableNodes: [MoneroManagedNode] {
        let custom = (UserDefaults.standard.stringArray(forKey: customNodesKey) ?? []).enumerated().map { index, endpoint in
            MoneroManagedNode(id: "custom-\(index)", name: endpoint, endpoint: endpoint)
        }
        var seen = Set<String>()
        return (managedNodes + custom).filter { node in
            guard isSecureEndpoint(node.endpoint), !node.name.isEmpty else { return false }
            return seen.insert(node.endpoint.lowercased()).inserted
        }
    }

    fileprivate static func managedFailoverNodes(for network: MoneroNetwork, excluding endpoint: String) -> [MoneroNode] {
        guard network == .mainnet else { return [] }
        guard !isCustomNode(endpoint) else { return [] }
        return managedNodes
            .filter { $0.endpoint.caseInsensitiveCompare(endpoint) != .orderedSame }
            .map { MoneroNode(endpoint: $0.endpoint) }
    }

    fileprivate static func isCustomNode(_ endpoint: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: customNodesKey) ?? [])
            .contains(where: { $0.caseInsensitiveCompare(endpoint) == .orderedSame })
    }

    @discardableResult
    public static func addCustomNode(_ endpoint: String) -> Bool {
        let normalized = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSecureEndpoint(normalized) else { return false }
        var nodes = UserDefaults.standard.stringArray(forKey: customNodesKey) ?? []
        if !nodes.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            nodes.append(normalized)
            UserDefaults.standard.set(nodes, forKey: customNodesKey)
        }
        return true
    }

    private static func isSecureEndpoint(_ endpoint: String) -> Bool {
        guard let components = URLComponents(string: endpoint),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return false }
        return true
    }
}

public enum MoneroWalletError: Error, LocalizedError {
    case walletAlreadyExists
    case walletNotFound
    case invalidNode
    case insecureNode
    case invalidAddress
    case invalidAmount
    case insufficientFunds
    case mainnetDisabled
    case walletUnavailable
    case native(String)
    case keychain(Error)
    case fileSystem(Error)

    public var errorDescription: String? {
        switch self {
        case .walletAlreadyExists: return MoneroLocalized("A Monero wallet already exists for this network.")
        case .walletNotFound: return MoneroLocalized("The Monero wallet was not found.")
        case .invalidNode: return MoneroLocalized("The Monero node is invalid.")
        case .insecureNode: return MoneroLocalized("Use an HTTPS node URL for Monero Mainnet.")
        case .invalidAddress: return MoneroLocalized("The Monero address is invalid for this network.")
        case .invalidAmount: return MoneroLocalized("The Monero amount is invalid.")
        case .insufficientFunds: return MoneroLocalized("The Monero wallet has insufficient unlocked funds.")
        case .mainnetDisabled: return MoneroLocalized("Monero mainnet payments are disabled in this build.")
        case .walletUnavailable: return MoneroLocalized("The Monero wallet is not open.")
        case .native(let message): return message.isEmpty ? MoneroLocalized("The Monero wallet operation failed.") : message
        case .keychain(let error): return error.localizedDescription
        case .fileSystem(let error): return error.localizedDescription
        }
    }
}

public struct MoneroWalletSnapshot: Sendable {
    public let network: MoneroNetwork
    public let nodeHost: String
    public let address: String
    public let balance: UInt64
    public let unlockedBalance: UInt64
    public let blockchainHeight: UInt64
    public let daemonHeight: UInt64
    public let isSynchronized: Bool
    public let isConnected: Bool
}

public struct MoneroTransaction: Identifiable, Sendable {
    public let id: String
    public let amount: Int64
    public let fee: UInt64
    public let direction: Direction
    public let isPending: Bool
    public let isFailed: Bool
    public let confirmations: UInt64
    public let blockHeight: UInt64
    public let timestamp: Date

    public enum Direction: Sendable {
        case incoming
        case outgoing
    }
}

private final class MoneroKeychainStorage: KeychainStorage {
    private let isUsingProductionService: Bool

    init(isUsingProductionService: Bool) {
        self.isUsingProductionService = isUsingProductionService
    }

    func dataValue(service: String, key: String) throws -> Data {
        var query = baseQuery(service: service, key: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw MoneroWalletError.native(String(format: MoneroLocalized("Could not read Monero wallet credentials from the iOS Keychain (%@)."), String(status)))
        }
        return data
    }

    func setDataValue(_ dataValue: Data, service: String, key: String) throws {
        let query = baseQuery(service: service, key: key)
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: dataValue
        ]
        let addStatus = SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
        guard addStatus == errSecDuplicateItem else {
            guard addStatus == errSecSuccess else {
                throw MoneroWalletError.native(String(format: MoneroLocalized("Could not save Monero wallet credentials to the iOS Keychain (%@)."), String(addStatus)))
            }
            return
        }

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw MoneroWalletError.native(String(format: MoneroLocalized("Could not update Monero wallet credentials in the iOS Keychain (%@)."), String(updateStatus)))
        }
    }

    func removeValue(service: String, key: String) throws {
        let status = SecItemDelete(baseQuery(service: service, key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MoneroWalletError.native(String(format: MoneroLocalized("Could not remove Monero wallet credentials from the iOS Keychain (%@)."), String(status)))
        }
    }

    private func baseQuery(service: String, key: String) -> [String: Any] {
        let scopedService = isUsingProductionService ? service : "\(service).staging"
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: scopedService,
            kSecAttrAccount as String: key
        ]
    }
}

public final class MoneroPreparedTransaction {
    public let amount: UInt64
    public let fee: UInt64

    private let queue: DispatchQueue
    private let nativeWallet: UnsafeMutableRawPointer
    private let walletPath: URL
    private var nativeTransaction: UnsafeMutableRawPointer?
    private var committed = false

    fileprivate init(amount: UInt64, fee: UInt64, nativeWallet: UnsafeMutableRawPointer, nativeTransaction: UnsafeMutableRawPointer?, walletPath: URL, queue: DispatchQueue) {
        self.amount = amount
        self.fee = fee
        self.nativeWallet = nativeWallet
        self.nativeTransaction = nativeTransaction
        self.walletPath = walletPath
        self.queue = queue
    }

    deinit {
        if let transaction = nativeTransaction {
            queue.async {
                MONERO_Wallet_disposeTransaction(self.nativeWallet, transaction)
            }
        }
    }

    public func commit(completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            guard !self.committed, let transaction = self.nativeTransaction else {
                completion(.failure(MoneroWalletError.native(MoneroLocalized("This transaction has already been submitted."))))
                return
            }

            self.committed = true
            let txid = Self.nativeString(MONERO_PendingTransaction_txid(transaction, ","))
            guard !txid.isEmpty else {
                MONERO_Wallet_disposeTransaction(self.nativeWallet, transaction)
                self.nativeTransaction = nil
                completion(.failure(MoneroWalletError.native(MoneroLocalized("MoneroCore did not provide a transaction ID. The payment was not submitted."))))
                return
            }

            let committed = MONERO_PendingTransaction_commit(transaction, "", false)
            guard committed else {
                let error = Self.nativeString(MONERO_PendingTransaction_errorString(transaction))
                MONERO_Wallet_disposeTransaction(self.nativeWallet, transaction)
                self.nativeTransaction = nil
                completion(.failure(MoneroWalletError.native(error)))
                return
            }

            // Commit is irreversible; a local persistence failure must not report the
            // payment as failed and invite the user to submit it a second time.
            _ = MONERO_Wallet_store(self.nativeWallet, self.walletPath.path)
            MONERO_Wallet_disposeTransaction(self.nativeWallet, transaction)
            self.nativeTransaction = nil
            completion(.success(txid))
        }
    }

    private static func nativeString(_ pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        let value = String(cString: pointer)
        // MoneroCore's vectorToString returns a static string literal for empty vectors.
        // It is not allocated with new[], so it must not be passed to MONERO_free.
        guard pointer.pointee != 0 else { return value }
        MONERO_free(UnsafeMutableRawPointer(mutating: pointer))
        return value
    }
}

public final class MoneroWalletService {
    public static let shared = MoneroWalletService()
    public static let isMainnetPaymentsEnabled = true

    private let queue = DispatchQueue(label: "org.radar.monero.wallet", qos: .userInitiated)
    private let keychain: KeychainStorage
    private let keychainService = "org.radar.monero.wallet"
    private let walletDirectory: URL
    private var manager: UnsafeMutableRawPointer?
    private var wallet: UnsafeMutableRawPointer?
    private var network: MoneroNetwork?
    private var node: MoneroNode?
    private var lastManagedFailoverAttemptAt = Date.distantPast
    private var backgroundObserver: NSObjectProtocol?

    init(keychain: KeychainStorage = MoneroKeychainStorage(isUsingProductionService: TSConstants.isUsingProductionService)) {
        self.keychain = keychain
        self.walletDirectory = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
            .appendingPathComponent("Monero", isDirectory: true)
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.storeOpenWallet()
        }
        queue.sync {
            MONERO_WalletManagerFactory_setLogLevel(LogLevel_Silent)
            MONERO_WalletManagerFactory_setLogCategories("")
            self.manager = MONERO_WalletManagerFactory_getWalletManager()
        }
    }

    public func createWallet(network: MoneroNetwork, node: MoneroNode, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            do {
                try self.requireSupportedPaymentNetwork(network)
                try self.ensureClosed()
                try self.prepareDirectory()
                let record = try self.newRecord(network: network, node: node)
                let walletPath = self.walletPath(network: network)
                guard !MONERO_WalletManager_walletExists(self.manager, walletPath.path) else {
                    throw MoneroWalletError.walletAlreadyExists
                }

                let wallet = MONERO_WalletManager_createWallet(
                    self.manager,
                    walletPath.path,
                    record.password,
                    "English",
                    network.nativeValue
                )
                guard let wallet else { throw self.managerError() }
                self.wallet = wallet
                let actualNetwork = try self.actualNetwork(for: wallet)
                guard actualNetwork == network else {
                    throw MoneroWalletError.native(MoneroLocalized("The created Monero wallet network did not match the selected network."))
                }
                self.network = actualNetwork
                self.node = node
                try self.initialize(wallet: wallet, record: record)
                let seed = Self.nativeString(MONERO_Wallet_seed(wallet, ""))
                guard !seed.isEmpty else { throw self.nativeError(wallet) }
                try self.persist(record: record)
                try self.store(wallet: wallet, path: walletPath)
                completion(.success(seed))
            } catch {
                self.closeAfterFailure()
                completion(.failure(error))
            }
        }
    }

    public func restoreWallet(
        mnemonic: String,
        network: MoneroNetwork,
        node: MoneroNode,
        restoreHeight: UInt64 = 0,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async {
            do {
                try self.requireSupportedPaymentNetwork(network)
                try self.ensureClosed()
                try self.prepareDirectory()
                let normalizedMnemonic = mnemonic.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                guard normalizedMnemonic.split(separator: " ").count >= 12 else {
                    throw MoneroWalletError.native(MoneroLocalized("The Monero recovery phrase is incomplete."))
                }

                let record = try self.newRecord(network: network, node: node)
                let walletPath = self.walletPath(network: network)
                let wallet = MONERO_WalletManager_recoveryWallet(
                    self.manager,
                    walletPath.path,
                    record.password,
                    normalizedMnemonic,
                    network.nativeValue,
                    restoreHeight,
                    1,
                    ""
                )
                guard let wallet else { throw self.managerError() }
                self.wallet = wallet
                let actualNetwork = try self.actualNetwork(for: wallet)
                guard actualNetwork == network else {
                    throw MoneroWalletError.native(MoneroLocalized("The restored Monero wallet network did not match the selected network."))
                }
                self.network = actualNetwork
                self.node = node
                try self.initialize(wallet: wallet, record: record)
                try self.persist(record: record)
                try self.store(wallet: wallet, path: walletPath)
                completion(.success(()))
            } catch {
                self.closeAfterFailure()
                completion(.failure(error))
            }
        }
    }

    public func openWallet(completion: @escaping (Result<Void, Error>) -> Void) {
        openWallet(requestedNetwork: nil, completion: completion)
    }

    public func openWallet(network: MoneroNetwork, completion: @escaping (Result<Void, Error>) -> Void) {
        openWallet(requestedNetwork: network, completion: completion)
    }

    private func openWallet(requestedNetwork: MoneroNetwork?, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            do {
                if let wallet = self.wallet {
                    MONERO_Wallet_stop(wallet)
                    // Closing with store=true can crash MoneroCore while it serializes
                    // the hash-chain cache during an in-flight refresh. Wallet keys and
                    // committed transactions are already persisted independently.
                    _ = MONERO_WalletManager_closeWallet(self.manager, wallet, false)
                    self.wallet = nil
                    self.network = nil
                    self.node = nil
                }

                let storedRecord = try self.loadRecord(network: requestedNetwork)
                let record = self.migratedMainnetNodeRecord(storedRecord)
                let walletPath = self.walletPath(network: record.network)
                guard FileManager.default.fileExists(atPath: walletPath.path),
                      MONERO_WalletManager_walletExists(self.manager, walletPath.path) else {
                    throw MoneroWalletError.walletNotFound
                }

                let wallet = MONERO_WalletManager_openWallet(
                    self.manager,
                    walletPath.path,
                    record.password,
                    record.network.nativeValue
                )
                guard let wallet else { throw self.managerError() }
                self.wallet = wallet
                let actualNetwork = try self.actualNetwork(for: wallet)
                guard actualNetwork == record.network else {
                    throw MoneroWalletError.native(MoneroLocalized("The saved wallet network does not match its MoneroCore network."))
                }
                self.network = actualNetwork
                self.node = record.node
                try self.initialize(wallet: wallet, record: record)
                if record.node != storedRecord.node {
                    try self.persist(record: record)
                }
                if requestedNetwork != nil {
                    try self.keychain.setDataValue(
                        Data(String(record.network.rawValue).utf8),
                        service: self.keychainService,
                        key: "active"
                    )
                }
                completion(.success(()))
            } catch {
                self.closeAfterFailure()
                completion(.failure(error))
            }
        }
    }

    public func close(completion: ((Result<Void, Error>) -> Void)? = nil) {
        queue.async {
            if let wallet = self.wallet {
                MONERO_Wallet_stop(wallet)
                _ = MONERO_WalletManager_closeWallet(self.manager, wallet, true)
            }
            self.wallet = nil
            self.network = nil
            self.node = nil
            completion?(.success(()))
        }
    }

    private func storeOpenWallet() {
        queue.async {
            guard let wallet = self.wallet,
                  let network = self.network else { return }
            do {
                try self.store(wallet: wallet, path: self.walletPath(network: network))
            } catch {
                Logger.warn("Could not persist the Monero wallet before the app entered background.")
            }
        }
    }

    public func refresh(completion: @escaping (Result<MoneroWalletSnapshot, Error>) -> Void) {
        queue.async {
            guard let wallet = self.wallet else {
                completion(.failure(MoneroWalletError.walletUnavailable))
                return
            }

            do {
                if MONERO_Wallet_refresh(wallet) {
                    completion(.success(try self.snapshot(wallet: wallet)))
                    return
                }

                let refreshError = self.nativeError(wallet)
                guard try self.reconnectUsingManagedFallback(wallet: wallet) else {
                    throw refreshError
                }
                guard MONERO_Wallet_refresh(wallet) else { throw self.nativeError(wallet) }
                completion(.success(try self.snapshot(wallet: wallet)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func snapshot(completion: @escaping (Result<MoneroWalletSnapshot, Error>) -> Void) {
        queue.async {
            do {
                guard let wallet = self.wallet else { throw MoneroWalletError.walletUnavailable }
                completion(.success(try self.snapshot(wallet: wallet)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func reconnectIfDisconnected(completion: @escaping (Result<MoneroWalletSnapshot, Error>) -> Void) {
        queue.async {
            do {
                guard let wallet = self.wallet else { throw MoneroWalletError.walletUnavailable }
                if MONERO_Wallet_connected(wallet) == 0 {
                    _ = try self.reconnectUsingManagedFallback(wallet: wallet)
                }
                completion(.success(try self.snapshot(wallet: wallet)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func transactions(completion: @escaping (Result<[MoneroTransaction], Error>) -> Void) {
        queue.async {
            do {
                guard let wallet = self.wallet else { throw MoneroWalletError.walletUnavailable }
                let history = MONERO_Wallet_history(wallet)
                guard let history else {
                    completion(.success([]))
                    return
                }

                // TransactionHistory is a cached view in MoneroCore; its count and
                // transaction pointers do not advance until refresh() is called.
                MONERO_TransactionHistory_refresh(history)

                var result: [MoneroTransaction] = []
                for index in 0..<MONERO_TransactionHistory_count(history) {
                    guard let transaction = MONERO_TransactionHistory_transaction(history, Int32(index)) else { continue }
                    let item = MoneroTransaction(
                        id: Self.nativeString(MONERO_TransactionInfo_hash(transaction)),
                        amount: MONERO_TransactionInfo_amount(transaction),
                        fee: MONERO_TransactionInfo_fee(transaction),
                        direction: MONERO_TransactionInfo_direction(transaction) == TransactionInfoDirection_In ? .incoming : .outgoing,
                        isPending: MONERO_TransactionInfo_isPending(transaction),
                        isFailed: MONERO_TransactionInfo_isFailed(transaction),
                        confirmations: MONERO_TransactionInfo_confirmations(transaction),
                        blockHeight: MONERO_TransactionInfo_blockHeight(transaction),
                        timestamp: Date(timeIntervalSince1970: TimeInterval(MONERO_TransactionInfo_timestamp(transaction)))
                    )
                    result.append(item)
                }
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func createSubaddress(label: String = "", completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            do {
                guard let wallet = self.wallet else { throw MoneroWalletError.walletUnavailable }
                let address = try self.createSubaddress(wallet: wallet, label: label)
                try self.store(wallet: wallet, path: self.walletPath(network: self.actualNetwork(for: wallet)))
                completion(.success(address))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Answers a chat address exchange using the wallet for the requested network.
    /// It never changes an already-open wallet's network or exposes its primary address.
    public func createChatReceiveRequest(
        network: MoneroNetwork,
        requestID: String,
        completion: @escaping (Result<MoneroPaymentRequest, Error>) -> Void
    ) {
        queue.async {
            do {
                try self.requireSupportedPaymentNetwork(network)
                if let wallet = self.wallet {
                    guard try self.actualNetwork(for: wallet) == network else {
                        throw MoneroWalletError.native(MoneroLocalized("Open the Monero wallet on the requested network to receive this payment."))
                    }
                } else {
                    try self.openWalletForChat(network: network)
                }
                guard let wallet = self.wallet else { throw MoneroWalletError.walletUnavailable }
                let address = try self.createSubaddress(wallet: wallet, label: "Radar chat")
                try self.store(wallet: wallet, path: self.walletPath(network: network))
                let request = try MoneroPaymentRequest(
                    address: address,
                    network: network,
                    requestID: requestID
                )
                self.openedForChatExchange = false
                completion(.success(request))
            } catch {
                self.closeAfterFailureIfWalletWasOpenedForChat()
                completion(.failure(error))
            }
        }
    }

    private func createSubaddress(wallet: UnsafeMutableRawPointer, label: String) throws -> String {
        let walletNetwork = try actualNetwork(for: wallet)
        let account: UInt32 = 0
        let before = MONERO_Wallet_numSubaddresses(wallet, account)
        MONERO_Wallet_addSubaddress(wallet, account, label)
        let after = MONERO_Wallet_numSubaddresses(wallet, account)
        guard after > before else { throw nativeError(wallet) }
        let address = Self.nativeString(MONERO_Wallet_address(wallet, UInt64(account), UInt64(after - 1)))
        guard MONERO_Wallet_addressValid(address, walletNetwork.nativeValue) else {
            throw MoneroWalletError.native(String(format: MoneroLocalized("MoneroCore generated a receive subaddress that its own validator rejected for %@. No request was sent."), walletNetwork.displayName))
        }
        return address
    }

    private var openedForChatExchange = false

    private func openWalletForChat(network: MoneroNetwork) throws {
        let record = try loadRecord(network: network)
        let path = walletPath(network: network)
        guard FileManager.default.fileExists(atPath: path.path),
              MONERO_WalletManager_walletExists(manager, path.path),
              let opened = MONERO_WalletManager_openWallet(manager, path.path, record.password, network.nativeValue) else {
            throw MoneroWalletError.walletNotFound
        }
        wallet = opened
        openedForChatExchange = true
        let actualNetwork = try actualNetwork(for: opened)
        guard actualNetwork == network else {
            throw MoneroWalletError.native(MoneroLocalized("The saved wallet network does not match its MoneroCore network."))
        }
        self.network = actualNetwork
        node = record.node
        try initialize(wallet: opened, record: record)
    }

    private func closeAfterFailureIfWalletWasOpenedForChat() {
        guard openedForChatExchange else { return }
        closeAfterFailure()
        openedForChatExchange = false
    }

    public func estimateFee(to address: String, amount: UInt64, completion: @escaping (Result<UInt64, Error>) -> Void) {
        queue.async {
            do {
                let wallet = try self.requireWallet()
                let network = try self.requireNetwork()
                try self.requireSupportedPaymentNetwork(network)
                try self.validate(address: address, network: network)
                guard amount > 0 else { throw MoneroWalletError.invalidAmount }
                let fee = MONERO_Wallet_estimateTransactionFee(
                    wallet,
                    address,
                    "",
                    String(amount),
                    "",
                    Priority_Default
                )
                guard fee > 0 || MONERO_Wallet_unlockedBalance(wallet, 0) >= amount else {
                    throw MoneroWalletError.insufficientFunds
                }
                completion(.success(fee))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func prepareSend(to address: String, amount: UInt64, completion: @escaping (Result<MoneroPreparedTransaction, Error>) -> Void) {
        queue.async {
            do {
                let wallet = try self.requireWallet()
                let network = try self.requireNetwork()
                try self.requireSupportedPaymentNetwork(network)
                try self.validate(address: address, network: network)
                guard amount > 0 else { throw MoneroWalletError.invalidAmount }
                guard MONERO_Wallet_unlockedBalance(wallet, 0) >= amount else {
                    throw MoneroWalletError.insufficientFunds
                }

                let transaction = MONERO_Wallet_createTransaction(
                    wallet,
                    address,
                    "",
                    amount,
                    0,
                    Priority_Default,
                    0,
                    "",
                    ","
                )
                guard let transaction else { throw self.nativeError(wallet) }
                let status = MONERO_PendingTransaction_status(transaction)
                guard status == PendingTransactionStatus_Ok else {
                    let error = Self.nativeString(MONERO_PendingTransaction_errorString(transaction))
                    MONERO_Wallet_disposeTransaction(wallet, transaction)
                    throw MoneroWalletError.native(error)
                }

                let prepared = MoneroPreparedTransaction(
                    amount: amount,
                    fee: MONERO_PendingTransaction_fee(transaction),
                    nativeWallet: wallet,
                    nativeTransaction: transaction,
                    walletPath: self.walletPath(network: network),
                    queue: self.queue
                )
                completion(.success(prepared))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func validate(address: String, network: MoneroNetwork? = nil) throws {
        guard let walletNetwork = self.network else { throw MoneroWalletError.walletUnavailable }
        let targetNetwork = network ?? walletNetwork
        guard targetNetwork == walletNetwork else {
            throw MoneroWalletError.native(String(format: MoneroLocalized("This payment request is for %@, but the open Monero wallet is on %@."), targetNetwork.displayName, walletNetwork.displayName))
        }
        guard MONERO_Wallet_addressValid(address, targetNetwork.nativeValue) else {
            throw MoneroWalletError.invalidAddress
        }
    }

    public static func isValidAddress(_ address: String, network: MoneroNetwork) -> Bool {
        MONERO_Wallet_addressValid(address, Int32(network.rawValue))
    }

    public func address(completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            do {
                let wallet = try self.requireWallet()
                completion(.success(Self.nativeString(MONERO_Wallet_address(wallet, 0, 0))))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func currentNetwork(completion: @escaping (Result<MoneroNetwork, Error>) -> Void) {
        queue.async {
            do {
                let wallet = try self.requireWallet()
                completion(.success(try self.actualNetwork(for: wallet)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func configuredWallet(completion: @escaping ((network: MoneroNetwork, identity: String)?) -> Void) {
        queue.async {
            guard let record = try? self.loadRecord() else { completion(nil); return }
            let identity = SHA256.hash(data: Data(record.password.utf8))
                .map { String(format: "%02x", $0) }.joined()
            completion((record.network, identity))
        }
    }

    public func formatAmount(_ amount: UInt64) -> String {
        Self.nativeString(MONERO_Wallet_displayAmount(amount))
    }

    private func initialize(wallet: UnsafeMutableRawPointer, record: KeychainRecord) throws {
        MONERO_Wallet_init3(wallet, "Radar", "radar-monero", "", false)
        let daemon = try record.node.daemonConfiguration(for: record.network)
        guard MONERO_Wallet_init(
            wallet,
            daemon.address,
            0,
            record.node.username ?? "",
            record.node.password ?? "",
            daemon.useSSL,
            false,
            ""
        ) else {
            throw nativeError(wallet)
        }

        MONERO_Wallet_setSubaddressLookahead(wallet, 5, 20)
        MONERO_Wallet_setAutoRefreshInterval(wallet, 10_000)
        MONERO_Wallet_startRefresh(wallet)
        try protectWalletFiles()
    }

    private func snapshot(wallet: UnsafeMutableRawPointer) throws -> MoneroWalletSnapshot {
        guard let node else { throw MoneroWalletError.walletUnavailable }
        let network = try actualNetwork(for: wallet)
        let nodeHost = URLComponents(string: node.endpoint)?.host ?? node.endpoint
        return MoneroWalletSnapshot(
            network: network,
            nodeHost: nodeHost,
            address: Self.nativeString(MONERO_Wallet_address(wallet, 0, 0)),
            balance: MONERO_Wallet_balance(wallet, 0),
            unlockedBalance: MONERO_Wallet_unlockedBalance(wallet, 0),
            blockchainHeight: MONERO_Wallet_blockChainHeight(wallet),
            daemonHeight: MONERO_Wallet_daemonBlockChainHeight(wallet),
            isSynchronized: MONERO_Wallet_synchronized(wallet),
            isConnected: MONERO_Wallet_connected(wallet) != 0
        )
    }

    private func reconnectUsingManagedFallback(wallet: UnsafeMutableRawPointer) throws -> Bool {
        guard let network, let currentNode = node,
              !MoneroNodeDirectory.isCustomNode(currentNode.endpoint),
              Date().timeIntervalSince(lastManagedFailoverAttemptAt) >= 30 else { return false }

        var candidates = MoneroNodeDirectory.managedFailoverNodes(for: network, excluding: currentNode.endpoint)
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.endpoint.lowercased()).inserted }
        guard !candidates.isEmpty else { return false }
        lastManagedFailoverAttemptAt = Date()

        let originalConfiguration = try currentNode.daemonConfiguration(for: network)
        let record = try loadRecord(network: network)
        MONERO_Wallet_stop(wallet)

        for candidate in candidates {
            guard let configuration = try? candidate.daemonConfiguration(for: network) else { continue }
            guard MONERO_Wallet_init(wallet, configuration.address, 0, "", "", configuration.useSSL, false, ""),
                  MONERO_Wallet_connectToDaemon(wallet),
                  MONERO_Wallet_connected(wallet) != 0,
                  (try? actualNetwork(for: wallet)) == network else { continue }

            let updatedRecord = KeychainRecord(network: network, node: candidate, password: record.password)
            do {
                try persist(record: updatedRecord)
            } catch {
                _ = MONERO_Wallet_init(wallet, originalConfiguration.address, 0, "", "", originalConfiguration.useSSL, false, "")
                _ = MONERO_Wallet_connectToDaemon(wallet)
                MONERO_Wallet_startRefresh(wallet)
                throw error
            }

            node = candidate
            MONERO_Wallet_startRefresh(wallet)
            return true
        }

        _ = MONERO_Wallet_init(wallet, originalConfiguration.address, 0, "", "", originalConfiguration.useSSL, false, "")
        _ = MONERO_Wallet_connectToDaemon(wallet)
        MONERO_Wallet_startRefresh(wallet)
        return false
    }

    private func requireWallet() throws -> UnsafeMutableRawPointer {
        guard let wallet else { throw MoneroWalletError.walletUnavailable }
        return wallet
    }

    private func requireNetwork() throws -> MoneroNetwork {
        try actualNetwork(for: requireWallet())
    }

    private func actualNetwork(for wallet: UnsafeMutableRawPointer) throws -> MoneroNetwork {
        let rawValue = MONERO_Wallet_nettype(wallet)
        guard let network = MoneroNetwork(rawValue: Int(rawValue)) else {
            throw MoneroWalletError.native(String(format: MoneroLocalized("MoneroCore returned an unknown wallet network (%@)."), String(rawValue)))
        }
        return network
    }

    private func requireSupportedPaymentNetwork(_ network: MoneroNetwork) throws {
        if network == .mainnet && !Self.isMainnetPaymentsEnabled {
            throw MoneroWalletError.mainnetDisabled
        }
    }

    private func ensureClosed() throws {
        guard wallet == nil else { throw MoneroWalletError.native(MoneroLocalized("The Monero wallet is already open.")) }
    }

    private func prepareDirectory() throws {
        do {
            try FileManager.default.createDirectory(at: walletDirectory, withIntermediateDirectories: true)
        } catch {
            throw MoneroWalletError.fileSystem(error)
        }
    }

    private func walletPath(network: MoneroNetwork) -> URL {
        walletDirectory.appendingPathComponent("wallet-\(network.rawValue)")
    }

    private struct KeychainRecord: Codable {
        let network: MoneroNetwork
        let node: MoneroNode
        let password: String
    }

    private func newRecord(network: MoneroNetwork, node: MoneroNode) throws -> KeychainRecord {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw MoneroWalletError.native(MoneroLocalized("Unable to generate wallet storage key."))
        }
        return KeychainRecord(
            network: network,
            node: node,
            password: Data(bytes).base64EncodedString()
        )
    }

    private func persist(record: KeychainRecord) throws {
        do {
            let data = try JSONEncoder().encode(record)
            try keychain.setDataValue(
                data,
                service: keychainService,
                key: recordKey(record.network)
            )
            try keychain.setDataValue(
                Data(String(record.network.rawValue).utf8),
                service: keychainService,
                key: "active"
            )
        } catch {
            throw MoneroWalletError.keychain(error)
        }
    }

    private func loadRecord(network requestedNetwork: MoneroNetwork? = nil) throws -> KeychainRecord {
        let networks: [MoneroNetwork] = {
            if let requestedNetwork {
                return [requestedNetwork]
            }
            if let data = try? keychain.dataValue(service: keychainService, key: "active"),
               let value = String(data: data, encoding: .utf8),
               let rawValue = Int(value),
               let network = MoneroNetwork(rawValue: rawValue) {
                return [network]
            }
            return [.stagenet, .testnet, .mainnet]
        }()

        for network in networks {
            guard let data = try? keychain.dataValue(service: keychainService, key: recordKey(network)),
                  let record = try? JSONDecoder().decode(KeychainRecord.self, from: data) else {
                continue
            }
            return record
        }
        throw MoneroWalletError.walletNotFound
    }

    private func migratedMainnetNodeRecord(_ record: KeychainRecord) -> KeychainRecord {
        guard record.network == .mainnet,
              let components = URLComponents(string: record.node.endpoint),
              components.host?.lowercased() == "node.sethforprivacy.com",
              let replacement = MoneroNodeDirectory.managedNodes.first else {
            return record
        }
        return KeychainRecord(
            network: record.network,
            node: MoneroNode(endpoint: replacement.endpoint),
            password: record.password
        )
    }

    private func recordKey(_ network: MoneroNetwork) -> String {
        "wallet-\(network.rawValue)"
    }

    private func store(wallet: UnsafeMutableRawPointer, path: URL) throws {
        guard MONERO_Wallet_store(wallet, path.path) else { throw nativeError(wallet) }
        try protectWalletFiles()
    }

    private func protectWalletFiles() throws {
        guard OWSFileSystem.protectFileOrFolder(atPath: walletDirectory.path, fileProtectionType: .complete) else {
            throw MoneroWalletError.fileSystem(NSError(domain: "MoneroWallet", code: 1))
        }
    }

    private func managerError() -> MoneroWalletError {
        MoneroWalletError.native(Self.nativeString(MONERO_WalletManager_errorString(manager)))
    }

    private func nativeError(_ wallet: UnsafeMutableRawPointer) -> MoneroWalletError {
        MoneroWalletError.native(Self.nativeString(MONERO_Wallet_errorString(wallet)))
    }

    private func closeAfterFailure() {
        if let wallet {
            MONERO_Wallet_stop(wallet)
            _ = MONERO_WalletManager_closeWallet(manager, wallet, false)
        }
        wallet = nil
        network = nil
        node = nil
    }

    private static func nativeString(_ pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        let value = String(cString: pointer)
        MONERO_free(UnsafeMutableRawPointer(mutating: pointer))
        return value
    }
}

private extension MoneroNetwork {
    var displayName: String {
        switch self {
        case .mainnet: return MoneroLocalized("Mainnet")
        case .testnet: return MoneroLocalized("Testnet")
        case .stagenet: return MoneroLocalized("Stagenet")
        }
    }
}
