import Foundation
public import SignalServiceKit

// Carried by ordinary, authenticated Signal messages. This never authorizes a payment.
struct MoneroAddressExchange: Codable, Equatable {
    enum Kind: String, Codable { case request, address, unavailable, paymentSent }
    static let prefix = "radar-monero-exchange-v1:"
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60
    static let responseTimeout: TimeInterval = 120

    let version: Int
    let kind: Kind
    let id: UUID
    let network: MoneroNetwork
    let expiresAt: TimeInterval
    let address: String?
    let amount: UInt64?

    static func request(network: MoneroNetwork, now: Date = Date()) -> Self {
        Self(version: 1, kind: .request, id: UUID(), network: network,
             expiresAt: now.timeIntervalSince1970 + lifetime, address: nil, amount: nil)
    }

    static func paymentSent(amount: UInt64, network: MoneroNetwork, now: Date = Date()) -> Self {
        Self(version: 1, kind: .paymentSent, id: UUID(), network: network,
             expiresAt: now.timeIntervalSince1970 + lifetime, address: nil, amount: amount)
    }

    static func announcement(address: String, network: MoneroNetwork, now: Date = Date()) -> Self {
        Self(version: 1, kind: .address, id: UUID(), network: network,
             expiresAt: now.timeIntervalSince1970 + lifetime, address: address, amount: nil)
    }

    func reply(address: String?) -> Self {
        Self(version: version, kind: address == nil ? .unavailable : .address,
             id: id, network: network, expiresAt: expiresAt, address: address, amount: nil)
    }

    func body() throws -> String {
        let introduction: String
        switch kind {
        case .request: introduction = MoneroLocalized("Monero payment request")
        case .address: introduction = MoneroLocalized("Monero receiving address shared")
        case .unavailable: introduction = MoneroLocalized("Monero address unavailable")
        case .paymentSent:
            let amountText = amount.map(MoneroPaymentRequest.decimalString) ?? MoneroLocalized("an amount of")
            introduction = String(format: MoneroLocalized("Hey, I sent you %@ XMR."), amountText)
        }
        let payload = Self.prefix + (try JSONEncoder().encode(self)).base64EncodedString()
        return introduction + "\n\n" + payload
    }

    static func parse(_ body: String, now: Date = Date(), allowExpired: Bool = false) -> Self? {
        guard body.utf8.count <= 2_048,
              let marker = body.range(of: prefix),
              body[marker.upperBound...].range(of: prefix) == nil,
              let payload = Data(base64Encoded: body[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)),
              let value = try? JSONDecoder().decode(Self.self, from: payload),
              value.version == 1, value.expiresAt.isFinite,
              allowExpired || (value.expiresAt > now.timeIntervalSince1970
                && value.expiresAt <= now.timeIntervalSince1970 + lifetime + 30) else { return nil }
        switch value.kind {
        case .request, .unavailable:
            guard value.address == nil, value.amount == nil else { return nil }
        case .address:
            guard let address = value.address,
                  value.amount == nil,
                  MoneroWalletService.isValidAddress(address, network: value.network) else { return nil }
        case .paymentSent:
            guard value.address == nil, let amount = value.amount, amount > 0 else { return nil }
        }
        return value
    }

    func matches(_ request: Self, threadID: String, expectedThreadID: String, now: Date = Date()) -> Bool {
        kind != .request && request.kind == .request && threadID == expectedThreadID
            && id == request.id && network == request.network && expiresAt == request.expiresAt
            && expiresAt > now.timeIntervalSince1970
    }
}

@MainActor
public final class MoneroChatPayments: NSObject, DatabaseChangeDelegate {
    public static let shared = MoneroChatPayments()
    private let store = KeyValueStore(collection: "MoneroChatAddressExchange.v1")
    private var started = false
    private var responding = Set<String>()
    private var responseBackgroundTasks: [String: OWSBackgroundTask] = [:]
    private var pending: [UUID: Pending] = [:]
    private var announcing = false

    private struct Pending {
        let threadID: String
        let request: MoneroAddressExchange
        let completion: (Result<MoneroPaymentRequest, Error>) -> Void
    }

    private struct CachedAddress: Codable {
        let address: String
        let network: MoneroNetwork
    }

    public func start() {
        guard !started else { return }
        started = true
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
        NotificationCenter.default.addObserver(self, selector: #selector(scanRecentMessages),
                                               name: .OWSApplicationDidBecomeActive, object: nil)
        scanRecentMessages()
        announceAddresses()
    }

    @discardableResult
    public func resolveAddress(
        for recipient: SignalServiceAddress,
        network: MoneroNetwork,
        completion: @escaping (Result<MoneroPaymentRequest, Error>) -> Void
    ) -> UUID {
        let request = MoneroAddressExchange.request(network: network)
        let threadAndAddress = SSKEnvironment.shared.databaseStorageRef.read { tx -> (TSContactThread, CachedAddress?)? in
            guard let thread = TSContactThread.getWithContactAddress(recipient, transaction: tx),
                  self.isTrusted(thread, tx: tx) else { return nil }
            let cachedAddress: CachedAddress? = try? self.store.getCodableValue(
                forKey: self.cachedAddressKey(threadID: thread.uniqueId, network: network),
                transaction: tx
            )
            return (thread, cachedAddress)
        }
        guard let (thread, cachedAddress) = threadAndAddress else {
            completion(.failure(MoneroWalletError.native(MoneroLocalized("Accept this conversation before sending Monero."))))
            return request.id
        }
        if let cachedAddress,
           cachedAddress.network == network,
           MoneroWalletService.isValidAddress(cachedAddress.address, network: network),
           let paymentRequest = try? MoneroPaymentRequest(address: cachedAddress.address, network: network) {
            completion(.success(paymentRequest))
            return request.id
        }
        pending[request.id] = Pending(threadID: thread.uniqueId, request: request, completion: completion)
        Task {
            do {
                try await enqueue(request, threadID: thread.uniqueId)
            } catch {
                finish(request.id, result: .failure(error))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MoneroAddressExchange.responseTimeout) { [weak self] in
            self?.finish(request.id, result: .failure(MoneroWalletError.native(
                MoneroLocalized("No saved receiving address is available yet. Your contact must share one or send you a Monero request once. After that, they do not need to be online for each payment.")
            )))
        }
        return request.id
    }

    public func cancel(_ id: UUID) {
        pending.removeValue(forKey: id)
    }

    public func sendPaymentNotification(to recipient: SignalServiceAddress, amount: UInt64, network: MoneroNetwork) async throws {
        guard amount > 0 else { throw MoneroWalletError.invalidAmount }
        let thread = SSKEnvironment.shared.databaseStorageRef.read { tx -> TSContactThread? in
            guard let thread = TSContactThread.getWithContactAddress(recipient, transaction: tx),
                  self.isTrusted(thread, tx: tx) else { return nil }
            return thread
        }
        guard let thread else {
            throw MoneroWalletError.native(MoneroLocalized("The payment was sent, but Radar could not send its chat notification."))
        }
        try await enqueue(.paymentSent(amount: amount, network: network), threadID: thread.uniqueId)
        await requestFreshAddressAfterPayment(threadID: thread.uniqueId, network: network)
    }

    private func requestFreshAddressAfterPayment(threadID: String, network: MoneroNetwork) async {
        let key = "address-rotation.\(threadID).\(network.rawValue)"
        let shouldRequest = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let lastRequest = store.getDate(key, transaction: tx) ?? .distantPast
            return Date().timeIntervalSince(lastRequest) >= 24 * 60 * 60
        }
        guard shouldRequest else { return }

        do {
            try await enqueue(.request(network: network), threadID: threadID)
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                store.setDate(Date(), key: key, transaction: tx)
            }
        } catch {
            // The previously cached subaddress remains valid if the contact is offline.
        }
    }

    private func finish(_ id: UUID, result: Result<MoneroPaymentRequest, Error>) {
        pending.removeValue(forKey: id)?.completion(result)
    }

    private func isTrusted(_ thread: TSContactThread, tx: DBReadTransaction) -> Bool {
        !thread.hasPendingMessageRequest(transaction: tx)
            && !SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(thread, transaction: tx)
    }

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard databaseChanges.didUpdateInteractions else { return }
        process(ids: databaseChanges.interactionUniqueIds)
    }

    public func databaseChangesDidUpdateExternally() { scanRecentMessages() }
    public func databaseChangesDidReset() { scanRecentMessages() }

    @objc private func scanRecentMessages() {
        guard canProcess else { return }
        announceAddresses()
        let ids: Set<String> = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let cursor = TSInteraction.grdbFetchCursor(
                // The protocol marker follows the human-readable introduction, so it is
                // not at the beginning of the stored message body.
                sql: "SELECT * FROM model_TSInteraction WHERE timestamp >= ? AND body LIKE ? ORDER BY id DESC LIMIT 200",
                arguments: [UInt64((Date().timeIntervalSince1970 - MoneroAddressExchange.lifetime) * 1_000),
                            "%" + MoneroAddressExchange.prefix + "%"], transaction: tx)
            return Set(((try? cursor.all()) ?? []).map(\.uniqueId))
        }
        process(ids: ids)
    }

    private var canProcess: Bool {
        CurrentAppContext().isMainApp
            && DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice
    }

    private func process(ids: Set<String>) {
        guard canProcess else { return }
        let messages: [(MoneroAddressExchange, String)] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            ids.compactMap { id in
                guard let message = TSInteraction.anyFetch(uniqueId: id, transaction: tx) as? TSIncomingMessage,
                      !message.wasRemotelyDeleted,
                      let body = message.body, let exchange = MoneroAddressExchange.parse(body, allowExpired: true),
                      let thread = TSThread.anyFetch(uniqueId: message.uniqueThreadId, transaction: tx) as? TSContactThread,
                      message.authorAddress == thread.contactAddress, self.isTrusted(thread, tx: tx) else { return nil }
                return (exchange, thread.uniqueId)
            }
        }
        for (exchange, threadID) in messages {
            if exchange.kind == .request,
               exchange.expiresAt > Date().timeIntervalSince1970 {
                respond(to: exchange, threadID: threadID)
            } else if exchange.kind == .address, let address = exchange.address {
                let cached = CachedAddress(address: address, network: exchange.network)
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    try? self.store.setCodable(
                        cached,
                        key: self.cachedAddressKey(threadID: threadID, network: exchange.network),
                        transaction: tx
                    )
                }
                if let pending = pending[exchange.id],
                   exchange.matches(pending.request, threadID: threadID, expectedThreadID: pending.threadID) {
                    finish(exchange.id, result: Result {
                        try MoneroPaymentRequest(address: address, network: exchange.network, requestID: exchange.id.uuidString)
                    })
                }
            } else if let pending = pending[exchange.id],
                      exchange.matches(pending.request, threadID: threadID, expectedThreadID: pending.threadID) {
                finish(exchange.id, result: .failure(MoneroWalletError.native(
                    MoneroLocalized("Your contact needs to open or set up a Monero wallet on the same network.")
                )))
            }
        }
    }

    private func cachedAddressKey(threadID: String, network: MoneroNetwork) -> String {
        "address.\(threadID).\(network.rawValue)"
    }

    public func announceAddresses() {
        guard canProcess, !announcing else { return }
        announcing = true
        MoneroWalletService.shared.configuredWallet { [weak self] configured in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let configured else { self.announcing = false; return }
                let network = configured.network
                let identity = configured.identity
                let threadIDs: [String] = SSKEnvironment.shared.databaseStorageRef.read { tx in
                    let cursor = TSInteraction.grdbFetchCursor(
                        sql: "SELECT * FROM model_TSInteraction WHERE timestamp >= ? AND body LIKE ? ORDER BY id DESC LIMIT 500",
                        arguments: [UInt64((Date().timeIntervalSince1970 - 30 * 24 * 60 * 60) * 1_000),
                                    "%" + MoneroAddressExchange.prefix + "%"], transaction: tx)
                    let moneroThreads = Set(((try? cursor.all()) ?? []).map(\.uniqueThreadId))
                    var ids: [String] = []
                    try? ThreadFinder().enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
                        guard let contact = thread as? TSContactThread,
                              moneroThreads.contains(contact.uniqueId),
                              self.isTrusted(contact, tx: tx),
                              !self.store.hasValue("announced.\(contact.uniqueId).\(network.rawValue).\(identity)", transaction: tx),
                              ids.count < 50 else { return }
                        ids.append(contact.uniqueId)
                    }
                    return ids
                }
                self.announceNext(threadIDs, network: network, identity: identity)
            }
        }
    }

    private func announceNext(_ threadIDs: [String], network: MoneroNetwork, identity: String) {
        guard let threadID = threadIDs.first else { announcing = false; return }
        let remaining = Array(threadIDs.dropFirst())
        MoneroWalletService.shared.createChatReceiveRequest(network: network, requestID: UUID().uuidString) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let address = try? result.get().address else {
                    self.announcing = false
                    return
                }
                Task { @MainActor in
                    do {
                        try await self.enqueue(.announcement(address: address, network: network), threadID: threadID)
                        SSKEnvironment.shared.databaseStorageRef.write { tx in
                            self.store.setBool(true, key: "announced.\(threadID).\(network.rawValue).\(identity)", transaction: tx)
                        }
                    } catch {
                        // Retry sharing when Radar becomes active again.
                    }
                    self.announceNext(remaining, network: network, identity: identity)
                }
            }
        }
    }

    private func respond(to request: MoneroAddressExchange, threadID: String) {
        guard request.expiresAt > Date().timeIntervalSince1970 else { return }
        guard !responding.contains(threadID) else { return }
        let responseKey = "response.\(threadID).\(request.id.uuidString)"
        let shouldRespond = SSKEnvironment.shared.databaseStorageRef.read { tx in
            guard !store.hasValue(responseKey, transaction: tx) else { return false }
            let lastResponse = store.getDate("last.\(threadID)", transaction: tx) ?? .distantPast
            return Date().timeIntervalSince(lastResponse) >= 5
        }
        guard shouldRespond else { return }
        responding.insert(threadID)
        responseBackgroundTasks[threadID] = OWSBackgroundTask(
            label: "MoneroAddressExchange",
            completionBlock: { [weak self] state in
                guard case .expired = state else { return }
                self?.finishResponding(threadID: threadID)
            }
        )
        MoneroWalletService.shared.createChatReceiveRequest(network: request.network, requestID: request.id.uuidString) { result in
            DispatchQueue.main.async {
                let address = try? result.get().address
                Task { @MainActor in
                    defer { self.finishResponding(threadID: threadID) }
                    guard self.responding.contains(threadID), self.canProcess,
                          request.expiresAt > Date().timeIntervalSince1970 else { return }
                    do {
                        try await self.enqueue(request.reply(address: address), threadID: threadID, responseKey: responseKey)
                    } catch {
                        // A later database update or foreground event can retry this handshake.
                    }
                }
            }
        }
    }

    private func finishResponding(threadID: String) {
        responding.remove(threadID)
        responseBackgroundTasks.removeValue(forKey: threadID)
    }

    private func enqueue(_ exchange: MoneroAddressExchange, threadID: String, responseKey: String? = nil) async throws {
        let body = try await DependenciesBridge.shared.attachmentContentValidator.prepareOversizeTextIfNeeded(
            MessageBody(text: try exchange.body(), ranges: .empty)
        )
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            guard let thread = TSThread.anyFetch(uniqueId: threadID, transaction: tx) as? TSContactThread,
                  self.isTrusted(thread, tx: tx) else {
                throw MoneroWalletError.native(MoneroLocalized("This conversation is no longer available for payments."))
            }
            if let responseKey, self.store.hasValue(responseKey, transaction: tx) { return }
            let message = UnpreparedOutgoingMessage.build(thread: thread, messageBody: body,
                quotedReplyDraft: nil, linkPreviewDataSource: nil, transaction: tx)
            let prepared = try message.prepare(tx: tx)
            SSKEnvironment.shared.messageSenderJobQueueRef.add(message: prepared, transaction: tx)
            if let responseKey {
                self.store.setBool(true, key: responseKey, transaction: tx)
                self.store.setDate(Date(), key: "last.\(threadID)", transaction: tx)
            }
        }
    }
}

public enum MoneroChatPaymentMessage {
    public static func displayText(for body: String, isOutgoing: Bool = false) -> String? {
        guard let exchange = MoneroAddressExchange.parse(body, allowExpired: true) else { return nil }
        switch exchange.kind {
        case .request, .address, .unavailable: return ""
        case .paymentSent:
            guard let amount = exchange.amount else { return MoneroLocalized("A contact sent a Monero payment notice. Check your wallet to verify it.") }
            let formattedAmount = MoneroPaymentRequest.decimalString(amount)
            return String(format: MoneroLocalized("Hey, I sent you %@ XMR."), formattedAmount)
        }
    }
}
