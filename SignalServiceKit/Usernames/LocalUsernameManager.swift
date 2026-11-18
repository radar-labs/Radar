//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// Manages the local username and username link.
public protocol LocalUsernameManager {

    // MARK: Local state

    /// Returns the state of the local username.
    func usernameState(tx: DBReadTransaction) -> Usernames.LocalUsernameState

    /// Sets the local username and username link.
    func setLocalUsername(
        username: String,
        usernameLink: Usernames.UsernameLink,
        tx: DBWriteTransaction,
    )

    /// Sets the local username, and marks that the local username link is
    /// corrupted.
    ///
    /// Corruption indicates that the username link values we have locally may
    /// or do not decrypt the encrypted username stored by the service. This may
    /// occur due to an interrupted "update my username link" request, race
    /// between two devices simultaneously updating our username, and possibly
    /// other reasons.
    func setLocalUsernameWithCorruptedLink(
        username: String,
        tx: DBWriteTransaction,
    )

    /// Sets that the local username and username link are corrupted.
    ///
    /// Corruption indicates that the username value we have locally may or does
    /// not match the hash of our username stored by the service. This may occur
    /// due to an interrupted "update my username" request, race between two
    /// devices simultaneously updating our username, and possibly other
    /// reasons.
    func setLocalUsernameCorrupted(tx: DBWriteTransaction)

    /// Clears the local username and username link, whether they were corrupted
    /// or not.
    func clearLocalUsername(tx: DBWriteTransaction)

    /// Returns the color to be used for the local user's username link QR code.
    func usernameLinkQRCodeColor(tx: DBReadTransaction) -> QRCodeColor

    /// Sets the color to be used for the local user's username link QR code.
    func setUsernameLinkQRCodeColor(
        color: QRCodeColor,
        tx: DBWriteTransaction,
    )

    // MARK: Usernames and the service

    /// Reserve a username from the given set of candidates.
    func reserveUsername(
        usernameCandidates: [LibSignalClient.Username],
    ) async throws -> LibSignalClient.Username

    /// Set the local user's username to the given reserved username, on the
    /// service and locally. Note that setting a new username also sets a
    /// corresponding username link.
    func confirmUsername(
        reservedUsername: LibSignalClient.Username,
    ) async throws

    /// Delete the local user's username and username link.
    func deleteUsername() async throws

    // MARK: Username links and the service

    /// Rotate the local user's username link, without modifying their username.
    func rotateUsernameLink() async throws -> Usernames.UsernameLink

    /// Update the case of the local user's existing username, as it will be
    /// visibly presented.
    ///
    /// This updates the local store to reflect the new username casing. It also
    /// performs an in-place update of the encrypted username used in the user's
    /// username link without modifying the link handle or entropy. The existing
    /// username link is consequently unaffected, but the username that is
    /// available via the link will reflect the new casing.
    ///
    /// - Important
    /// The new username must case-insensitively match the existing username
    /// when calling this API.
    func updateVisibleCaseOfExistingUsername(
        newUsername: LibSignalClient.Username,
    ) async throws
}

// MARK: -

public extension Usernames {
    static let localUsernameStateChangedNotification = NSNotification.Name(
        "localUsernameStateChanged",
    )

    /// Represents the states that the local user's username and username link
    /// can be in.
    enum LocalUsernameState: Equatable {
        /// The user deliberately has no username nor username link.
        case unset
        /// The user has both a username and username link.
        case available(username: String, usernameLink: UsernameLink)
        /// The user has a username, but something is wrong with the
        /// corresponding username link and it cannot be used.
        case linkCorrupted(username: String)
        /// The user has a username, but something is wrong with it and neither
        /// it nor the corresponding username link can be used.
        case usernameAndLinkCorrupted

        /// Whether the user explicitly does not have a username set.
        public var isExplicitlyUnset: Bool {
            switch self {
            case .unset:
                return true
            case .available, .linkCorrupted, .usernameAndLinkCorrupted:
                return false
            }
        }

        /// The username, if there is one available.
        public var username: String? {
            switch self {
            case let .available(username, _):
                return username
            case let .linkCorrupted(username):
                return username
            case .unset, .usernameAndLinkCorrupted:
                return nil
            }
        }

        /// The username link, if there is one available.
        public var usernameLink: Usernames.UsernameLink? {
            switch self {
            case let .available(_, usernameLink):
                return usernameLink
            case .unset, .linkCorrupted, .usernameAndLinkCorrupted:
                return nil
            }
        }
    }
}

// MARK: -

class LocalUsernameManagerImpl: LocalUsernameManager {
    private struct CorruptionStore {
        private enum Constants {
            static let collection = "LocalUsernameCorruption"
            static let usernameKey = "username"
            static let usernameLinkKey = "link"
        }

        private let kvStore: KeyValueStore

        init() {
            kvStore = KeyValueStore(collection: Constants.collection)
        }

        func isUsernameCorrupted(tx: DBReadTransaction) -> Bool {
            return kvStore.getBool(Constants.usernameKey, defaultValue: false, transaction: tx)
        }

        func isUsernameLinkCorrupted(tx: DBReadTransaction) -> Bool {
            return kvStore.getBool(Constants.usernameLinkKey, defaultValue: false, transaction: tx)
        }

        func setUsernameCorrupted(_ value: Bool, tx: DBWriteTransaction) {
            kvStore.setBool(value, key: Constants.usernameKey, transaction: tx)
        }

        func setUsernameLinkCorrupted(_ value: Bool, tx: DBWriteTransaction) {
            kvStore.setBool(value, key: Constants.usernameLinkKey, transaction: tx)
        }
    }

    private struct UsernameStore {
        private enum Constants {
            static let collection = "LocalUsername"
            static let usernameKey = "username"
            static let usernameLinkHandleKey = "linkHandle"
            static let usernameLinkEntropyKey = "linkEntropy"
            static let usernameLinkQRCodeColorKey = "linkColor"
        }

        private let kvStore: KeyValueStore

        init() {
            kvStore = KeyValueStore(collection: Constants.collection)
        }

        func username(tx: DBReadTransaction) -> String? {
            return kvStore.getString(Constants.usernameKey, transaction: tx)
        }

        func usernameLink(tx: DBReadTransaction) -> Usernames.UsernameLink? {
            if
                let linkHandleData = kvStore.getData(Constants.usernameLinkHandleKey, transaction: tx),
                let linkHandle = UUID(data: linkHandleData),
                let linkEntropyData = kvStore.getData(Constants.usernameLinkEntropyKey, transaction: tx),
                let linkEntropy = try? UsernameLink.Entropy(rawValue: linkEntropyData)
            {
                return UsernameLink(handle: linkHandle, entropy: linkEntropy)
            }

            return nil
        }

        func usernameLinkColor(tx: DBReadTransaction) -> QRCodeColor {
            return (try? kvStore.getCodableValue(
                forKey: Constants.usernameLinkQRCodeColorKey,
                transaction: tx,
            )) ?? .unknown
        }

        func setUsername(username: String?, tx: DBWriteTransaction) {
            kvStore.setString(username, key: Constants.usernameKey, transaction: tx)
        }

        func setUsernameLink(usernameLink: Usernames.UsernameLink?, tx: DBWriteTransaction) {
            kvStore.setData(usernameLink?.handle.data, key: Constants.usernameLinkHandleKey, transaction: tx)
            kvStore.setData(usernameLink?.entropy.rawValue, key: Constants.usernameLinkEntropyKey, transaction: tx)
        }

        func setUsernameLinkColor(color: QRCodeColor, tx: DBWriteTransaction) {
            try? kvStore.setCodable(color, key: Constants.usernameLinkQRCodeColorKey, transaction: tx)
        }
    }

    private let db: any DB
    private let keyTransparencyStore: KeyTransparencyStore
    private let reachabilityManager: SSKReachabilityManager
    private let serviceProvider: any ServiceProvider
    private let storageServiceManager: StorageServiceManager
    private let syncMessageSender: UsernameChangeSyncMessageSender
    private let tsAccountManager: TSAccountManager

    private let corruptionStore: CorruptionStore
    private let usernameStore: UsernameStore

    private let maxNetworkRequestRetries: Int

    private var logger: PrefixedLogger { UsernameLogger.shared }

    init(
        db: any DB,
        keyTransparencyStore: KeyTransparencyStore,
        reachabilityManager: SSKReachabilityManager,
        serviceProvider: any ServiceProvider,
        storageServiceManager: StorageServiceManager,
        syncMessageSender: UsernameChangeSyncMessageSender,
        tsAccountManager: TSAccountManager,
        maxNetworkRequestRetries: Int = 2,
    ) {
        self.db = db
        self.keyTransparencyStore = keyTransparencyStore
        self.reachabilityManager = reachabilityManager
        self.serviceProvider = serviceProvider
        self.storageServiceManager = storageServiceManager
        self.syncMessageSender = syncMessageSender
        self.tsAccountManager = tsAccountManager

        corruptionStore = CorruptionStore()
        usernameStore = UsernameStore()

        self.maxNetworkRequestRetries = maxNetworkRequestRetries
    }

    private func requireReachability() throws(OWSHTTPError) {
        guard reachabilityManager.isReachable else {
            logger.warn("Not attempting to reserve username – Reachability indicates we will fail.")
            throw OWSHTTPError.networkFailure(.genericFailure)
        }
    }

    // MARK: - Local state

    func usernameState(
        tx: DBReadTransaction,
    ) -> Usernames.LocalUsernameState {
        if corruptionStore.isUsernameCorrupted(tx: tx) {
            return .usernameAndLinkCorrupted
        } else if let username = usernameStore.username(tx: tx) {
            if
                !corruptionStore.isUsernameLinkCorrupted(tx: tx),
                let usernameLink = usernameStore.usernameLink(tx: tx)
            {
                return .available(username: username, usernameLink: usernameLink)
            }

            return .linkCorrupted(username: username)
        }

        return .unset
    }

    func setLocalUsername(
        username: String,
        usernameLink: Usernames.UsernameLink,
        tx: DBWriteTransaction,
    ) {
        corruptionStore.setUsernameCorrupted(false, tx: tx)
        usernameStore.setUsername(username: username, tx: tx)

        corruptionStore.setUsernameLinkCorrupted(false, tx: tx)
        usernameStore.setUsernameLink(usernameLink: usernameLink, tx: tx)

        tx.addSyncCompletion {
            self.postLocalUsernameStateChangedNotification()
        }
    }

    func setLocalUsernameWithCorruptedLink(
        username: String,
        tx: DBWriteTransaction,
    ) {
        corruptionStore.setUsernameCorrupted(false, tx: tx)
        usernameStore.setUsername(username: username, tx: tx)

        corruptionStore.setUsernameLinkCorrupted(true, tx: tx)

        tx.addSyncCompletion {
            self.postLocalUsernameStateChangedNotification()
        }
    }

    func setLocalUsernameCorrupted(tx: DBWriteTransaction) {
        markUsernameCorrupted(true, tx: tx)
    }

    func clearLocalUsername(tx: DBWriteTransaction) {
        corruptionStore.setUsernameCorrupted(false, tx: tx)
        corruptionStore.setUsernameLinkCorrupted(false, tx: tx)

        usernameStore.setUsername(username: nil, tx: tx)
        usernameStore.setUsernameLink(usernameLink: nil, tx: tx)

        tx.addSyncCompletion {
            self.postLocalUsernameStateChangedNotification()
        }
    }

    func usernameLinkQRCodeColor(
        tx: DBReadTransaction,
    ) -> QRCodeColor {
        return usernameStore.usernameLinkColor(tx: tx)
    }

    func setUsernameLinkQRCodeColor(
        color: QRCodeColor,
        tx: DBWriteTransaction,
    ) {
        usernameStore.setUsernameLinkColor(color: color, tx: tx)
    }

    private func markUsernameCorrupted(_ value: Bool, tx: DBWriteTransaction) {
        corruptionStore.setUsernameCorrupted(value, tx: tx)
        corruptionStore.setUsernameLinkCorrupted(value, tx: tx)

        tx.addSyncCompletion {
            self.postLocalUsernameStateChangedNotification()
        }
    }

    private func markUsernameLinkCorrupted(_ value: Bool, tx: DBWriteTransaction) {
        corruptionStore.setUsernameLinkCorrupted(value, tx: tx)

        tx.addSyncCompletion {
            self.postLocalUsernameStateChangedNotification()
        }
    }

    private func postLocalUsernameStateChangedNotification() {
        NotificationCenter.default.postOnMainThread(
            name: Usernames.localUsernameStateChangedNotification,
            object: nil,
        )
    }

    // MARK: Usernames and the service

    func reserveUsername(
        usernameCandidates: [LibSignalClient.Username],
    ) async throws -> LibSignalClient.Username {
        try requireReachability()

        let reservedHash = try await makeRequestWithNetworkRetries {
            return try await $0.reserveUsernameHashes(usernameCandidates.map(\.hash))
        }
        guard let reservedCandidate = usernameCandidates.first(where: { $0.hash == reservedHash }) else {
            throw OWSGenericError("server returned a candidate we didn't ask for")
        }
        return reservedCandidate
    }

    /// Confirm the given reserved username, setting it as our username.
    func confirmUsername(
        reservedUsername: LibSignalClient.Username,
    ) async throws {
        try requireReachability()

        let (linkEntropy, usernameCiphertext) = UsernameLink.encryptUsername(reservedUsername)

        // Mark as corrupted in case we encounter an unexpected error while
        // confirming. If that happens we can't be sure if our new username was
        // set or not, so we conservatively leave it in the corrupted state.
        // If, however, we get a response we understand (affirmative or
        // negative), we remove the corrupted flag.
        await db.awaitableWrite { tx in
            markUsernameCorrupted(true, tx: tx)
        }

        do {
            let linkHandle = try await makeRequestWithNetworkRetries {
                return try await $0.confirmUsername(
                    reservedUsername,
                    usernameCiphertext: usernameCiphertext,
                )
            }
            await self.db.awaitableWrite { tx in
                let usernameLink = UsernameLink(handle: linkHandle, entropy: linkEntropy)

                self.setLocalUsername(
                    username: reservedUsername.value,
                    usernameLink: usernameLink,
                    tx: tx,
                )

                // This device changed our username hash, which we need to
                // communicate out.
                self.usernameHashDidChangeLocally(tx: tx)

                // We back up the username and link in StorageService, so
                // trigger a backup now.
                self.storageServiceManager.recordPendingLocalAccountUpdates()
            }
        } catch {
            switch error {
            case SignalError.usernameReservationNotFound, SignalError.usernameNotAvailable, SignalError.rateLimitedError(retryAfter: _, message: _):
                await self.db.awaitableWrite { tx in
                    self.markUsernameCorrupted(false, tx: tx)
                }
            default:
                break
            }
            throw error
        }
    }

    func deleteUsername() async throws {
        try requireReachability()

        // Mark as corrupted in case we encounter an unexpected error while
        // deleting. If that happens we can't be sure if our new username was
        // deleted or not, so we conservatively leave it in the corrupted state.
        // If, however, we get a response, we remove the corrupted flag.
        await db.awaitableWrite { tx in
            markUsernameCorrupted(true, tx: tx)
        }

        try await makeRequestWithNetworkRetries {
            try await $0.deleteUsernameHash()
        }
        await self.db.awaitableWrite { tx in
            self.clearLocalUsername(tx: tx)

            // This device changed our username hash, which we need to
            // communicate out.
            self.usernameHashDidChangeLocally(tx: tx)
        }

        // We back up the username and link in StorageService, so
        // trigger a backup now.
        self.storageServiceManager.recordPendingLocalAccountUpdates()
    }

    /// Performs necessary side-effects when we locally change our username such
    /// that the username hash has changed.
    private func usernameHashDidChangeLocally(tx: DBWriteTransaction) {
        guard let localAci = tsAccountManager.localIdentifiers(tx: tx)?.aci else {
            return
        }

        // Enqueue a username-change sync message, so our other devices learn
        // about each of our username changes. (If we just relied on Storage
        // Service, multiple quick updates might appear to a linked device as
        // one update.)
        syncMessageSender.addUsernameChangeSyncMessage(tx: tx)

        // Our local username hash has changed, and we should inform
        // LibSignal for KT self-check monitoring.
        KeyTransparencyManager.handleSelfCheckIdentifierChanged(
            accountDataField: .usernameHash,
            localAci: localAci,
            tx: tx,
            db: db,
            keyTransparencyStore: keyTransparencyStore,
        )
    }

    // MARK: Username links and the service

    func rotateUsernameLink() async throws -> Usernames.UsernameLink {
        try requireReachability()

        let (currentUsername, newEntropy, newUsernameCiphertext) = try await db.awaitableWrite(block: { tx -> (LibSignalClient.Username, UsernameLink.Entropy, Data) in
            guard let currentUsername = usernameState(tx: tx).username else {
                throw OWSAssertionError("Tried to rotate link, but missing current username!")
            }

            let currentUsernameObj: LibSignalClient.Username
            do {
                currentUsernameObj = try LibSignalClient.Username(currentUsername)
            } catch let error {
                throw OWSGenericError("Failed to parse existing username! \(error)")
            }

            let (newEntropy, newUsernameCiphertext) = UsernameLink.encryptUsername(currentUsernameObj)

            // Mark as corrupted in case we encounter an unexpected error while
            // rotating. If that happens we can't be sure if our username link was
            // rotated or not, so we conservatively leave it in the corrupted state.
            // If, however, we get a response, we remove the corrupted flag.
            markUsernameLinkCorrupted(true, tx: tx)

            return (currentUsernameObj, newEntropy, newUsernameCiphertext)
        })

        let newHandle = try await makeRequestWithNetworkRetries {
            try await $0.setUsernameLink(usernameCiphertext: newUsernameCiphertext, keepLinkHandle: false)
        }

        let newUsernameLink = UsernameLink(handle: newHandle, entropy: newEntropy)

        await self.db.awaitableWrite { tx in
            self.setLocalUsername(
                username: currentUsername.value,
                usernameLink: newUsernameLink,
                tx: tx,
            )
        }

        // We back up the username and link in StorageService, so
        // trigger a backup now.
        self.storageServiceManager.recordPendingLocalAccountUpdates()

        return newUsernameLink
    }

    func updateVisibleCaseOfExistingUsername(
        newUsername: LibSignalClient.Username,
    ) async throws {
        try requireReachability()

        let (newUsernameCiphertext, currentUsernameLink) = try await db.awaitableWrite(block: { tx -> (Data, Usernames.UsernameLink) in
            let currentUsernameState = usernameState(tx: tx)

            guard
                let currentUsernameLink = currentUsernameState.usernameLink,
                let currentUsername = currentUsernameState.username,
                newUsername.value.lowercased() == currentUsername.lowercased()
            else {
                throw OWSAssertionError("Attempting to change username case, but new nickname does not match existing username!")
            }

            let newUsernameCiphertext = UsernameLink.encryptUsername(
                newUsername,
                existingEntropy: currentUsernameLink.entropy,
            )

            // Mark as corrupted in case we encounter an unexpected error while
            // setting the new encrypted username. If that happens we can't be sure
            // if our encrypted username was updated or not, so we conservatively
            // leave it in the corrupted state. If, however, we get a response, we
            // remove the corrupted flag.
            markUsernameLinkCorrupted(true, tx: tx)

            return (newUsernameCiphertext, currentUsernameLink)
        })

        defer {
            // We back up the username and link in StorageService, and in all
            // codepaths we've updated the username, so trigger a backup now.
            storageServiceManager.recordPendingLocalAccountUpdates()
        }

        do {
            let newHandle = try await makeRequestWithNetworkRetries {
                /// Pass `keepLinkHandle = true` here, to ask the service not to
                /// rotate the username link handle. That's key to keeping the
                /// existing link unaffected while updating the case of the
                /// visible username the link points to.
                return try await $0.setUsernameLink(usernameCiphertext: newUsernameCiphertext, keepLinkHandle: true)
            }
            guard currentUsernameLink.handle == newHandle else {
                UsernameLogger.shared.error("Handle received while changing username case did not match existing! Is this a server bug?")
                throw OWSGenericError("")
            }

            await self.db.awaitableWrite { tx in
                self.setLocalUsername(
                    username: newUsername.value,
                    usernameLink: currentUsernameLink,
                    tx: tx,
                )
            }
        } catch {
            // Even though we failed to update the link, we can save the new
            // nickname locally. If the user rotates their link to fix the
            // issue, the new link will reflect the updated nickname.
            await self.db.awaitableWrite { tx in
                self.setLocalUsernameWithCorruptedLink(
                    username: newUsername.value,
                    tx: tx,
                )
            }
            throw error
        }
    }

    // MARK: - Network retries

    /// Make the request in the given block, with retries.
    ///
    /// Because a failed username mutation request leaves us in a corrupted
    /// state, add retries for network errors to avoid unnecessary corruption
    /// where possible.
    private func makeRequestWithNetworkRetries<Output>(requestBlock: (any AuthUsernamesService) async throws -> Output) async throws -> Output {
        return try await Retry.performWithBackoff(
            maxAttempts: self.maxNetworkRequestRetries + 1,
            isRetryable: { $0.isNetworkFailureOrTimeout },
            block: { try await serviceProvider.withAuthService(.usernames, do: requestBlock) },
        )
    }

    // MARK: -

    /// Wrapper around `MessageSenderJobQueue`, for tests.
    protocol UsernameChangeSyncMessageSender {
        func addUsernameChangeSyncMessage(tx: DBWriteTransaction)
    }

    struct UsernameChangeSyncMessageSenderImpl: UsernameChangeSyncMessageSender {
        let messageSenderJobQueue: MessageSenderJobQueue
        let threadStore: ThreadStore

        func addUsernameChangeSyncMessage(tx: DBWriteTransaction) {
            guard let localThread = threadStore.getOrCreateLocalThread(tx: tx) else {
                owsFailDebug("Failed to getOrCreateLocalThread!")
                return
            }

            let usernameChangeSyncMessage = UsernameChangeSyncMessage(
                localThread: localThread,
                tx: tx,
            )

            messageSenderJobQueue.add(
                message: .preprepared(transientMessageWithoutAttachments: usernameChangeSyncMessage),
                transaction: tx,
            )
        }
    }
}
