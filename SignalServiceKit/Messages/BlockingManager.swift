//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum BlockMode {
    case localUser
    case storageService
    case syncMessage
    case backupRestore

    var isLocallyInitiated: Bool {
        switch self {
        case .syncMessage, .storageService, .backupRestore:
            return false
        case .localUser:
            return true
        }
    }

    var asUserProfileWriter: UserProfileWriter {
        switch self {
        case .localUser: return .localUser
        case .storageService: return .storageService
        case .syncMessage: return .syncMessage
        case .backupRestore: return .backupRestore
        }
    }
}

// MARK: -

public class BlockingManager {
    private let blockedReleaseNotesStore: BlockedReleaseNotesStore

    private let syncQueue = SerialTaskQueue()

#if TESTABLE_BUILD
    func flushSyncQueueTask() -> Task<Void, any Error> {
        return self.syncQueue.enqueue {}
    }
#endif

    init(
        blockedReleaseNotesStore: BlockedReleaseNotesStore,
    ) {
        self.blockedReleaseNotesStore = blockedReleaseNotesStore
    }

    private func didUpdate(wasLocallyInitiated: Bool, tx: DBWriteTransaction) {
        if wasLocallyInitiated {
            setNeedsSync(tx: tx)
        } else {
            clearNeedsSync(tx: tx)
        }
        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: Self.blockListDidChange, object: nil)
        }
    }

    private func setNeedsSync(tx: DBWriteTransaction) {
        setChangeToken(fetchChangeToken(tx: tx) + 1, tx: tx)
        tx.addSyncCompletion {
            self.syncQueue.enqueue { [self] in
                do {
                    try await syncBlockListIfNecessary(force: false)
                } catch {
                    Logger.warn("Failed to sync block list! \(error)")
                }
            }
        }
    }

    private func clearNeedsSync(tx: DBWriteTransaction) {
        setLastSyncedChangeToken(fetchChangeToken(tx: tx), transaction: tx)
    }

    public func isAddressBlocked(_ address: SignalServiceAddress, transaction: DBReadTransaction) -> Bool {
        guard !address.isLocalAddress else {
            return false
        }
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        guard let recipient = recipientDatabaseTable.fetchRecipient(address: address, tx: transaction) else {
            return false
        }
        return recipient.isBlocked
    }

    public func isGroupIdBlocked(_ groupId: GroupIdentifier, transaction tx: DBReadTransaction) -> Bool {
        return _isGroupIdBlocked(groupId.serialize(), tx: tx)
    }

    public func isGroupIdBlocked_deprecated(_ groupId: Data, tx: DBReadTransaction) -> Bool {
        return _isGroupIdBlocked(groupId, tx: tx)
    }

    private func _isGroupIdBlocked(_ groupId: Data, tx: DBReadTransaction) -> Bool {
        return GroupStore().fetchGroup(forGroupIdData: groupId, tx: tx)?.isBlocked == true
    }

    public func isReleaseNotesThreadBlocked(tx: DBReadTransaction) -> Bool {
        return blockedReleaseNotesStore.isBlocked(tx: tx)
    }

    public func addBlockedRecipient(
        _ recipient: inout SignalRecipient,
        blockedAt: BlockedTimestamp,
        blockMode: BlockMode,
        tx: DBWriteTransaction,
    ) {
        let interactionStore = DependenciesBridge.shared.interactionStore
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientStore = DependenciesBridge.shared.recipientDatabaseTable
        let storageServiceManager = SSKEnvironment.shared.storageServiceManagerRef
        let storyRecipientManager = DependenciesBridge.shared.storyRecipientManager
        let threadStore = DependenciesBridge.shared.threadStore

        let isBlocked = recipient.isBlocked
        if isBlocked {
            if !blockMode.isLocallyInitiated, blockedAt != .unspecified, recipient.blockedAt != blockedAt {
                recipient.blockedAt = blockedAt
                recipientStore.updateRecipient(recipient, transaction: tx)
            }
            return
        }
        let wasRemoved = profileManager.removeRecipientFromProfileWhitelist(
            &recipient,
            userProfileWriter: blockMode.asUserProfileWriter,
            tx: tx,
        )
        owsAssertDebug(recipient.status == .unspecified)
        recipient.status = .blocked
        recipient.blockedAt = blockedAt
        recipientStore.updateRecipient(recipient, transaction: tx)
        if wasRemoved {
            profileManager.setNeedsProfileKeyRotation(tx: tx)
        }

        Logger.info("blocked address: \(recipient.address)")

        if blockMode.isLocallyInitiated {
            storageServiceManager.recordPendingUpdates(updatedRecipientUniqueIds: [recipient.uniqueId])
        }

        // We will start dropping new stories from the blocked address;
        // delete any existing ones we already have.
        if let aci = recipient.aci {
            StoryManager.deleteAllStories(forSender: aci, tx: tx)
        }
        storyRecipientManager.removeRecipientIdFromAllPrivateStoryThreads(
            recipient.id,
            shouldUpdateStorageService: true,
            tx: tx,
        )

        switch blockMode {
        case .backupRestore:
            // If we're restoring from a Backup, avoid the side effect of
            // inserting a message. One either existed in the backup or not.
            break
        case .storageService, .syncMessage, .localUser:
            // Insert an info message that we blocked this user.
            if let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx) {
                interactionStore.insertInteraction(
                    TSInfoMessage(thread: contactThread, messageType: .blockedOtherUser),
                    tx: tx,
                )
            }
        }

        didUpdate(wasLocallyInitiated: blockMode.isLocallyInitiated, tx: tx)
    }

    public func removeBlockedRecipient(
        _ recipient: inout SignalRecipient,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction,
    ) {
        let interactionStore = DependenciesBridge.shared.interactionStore
        let recipientStore = DependenciesBridge.shared.recipientDatabaseTable
        let storageServiceManager = SSKEnvironment.shared.storageServiceManagerRef
        let threadStore = DependenciesBridge.shared.threadStore

        let isBlocked = recipient.isBlocked
        guard isBlocked else {
            return
        }
        recipient.status = .unspecified
        recipient.blockedAt = .unspecified
        recipientStore.updateRecipient(recipient, transaction: tx)

        Logger.info("unblocked address: \(recipient.address)")

        if wasLocallyInitiated {
            storageServiceManager.recordPendingUpdates(updatedRecipientUniqueIds: [recipient.uniqueId])
        }

        // Insert an info message that we unblocked this user.
        if let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx) {
            interactionStore.insertInteraction(
                TSInfoMessage(thread: contactThread, messageType: .unblockedOtherUser),
                tx: tx,
            )
        }

        didUpdate(wasLocallyInitiated: wasLocallyInitiated, tx: tx)
    }

    public func addBlockedGroup(
        _ record: inout GroupRecord,
        blockedAt: BlockedTimestamp,
        blockMode: BlockMode,
        tx: DBWriteTransaction,
    ) {
        let interactionStore = DependenciesBridge.shared.interactionStore
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let storageServiceManager = SSKEnvironment.shared.storageServiceManagerRef

        let isBlocked = record.isBlocked
        if isBlocked {
            if !blockMode.isLocallyInitiated, blockedAt != .unspecified, record.blockedAt != blockedAt {
                record.setBlockedAt(blockedAt, tx: tx)
            }
            return
        }
        let didRemove = profileManager.removeGroupFromProfileWhitelist(
            &record,
            userProfileWriter: blockMode.asUserProfileWriter,
            tx: tx,
        )
        record.setBlocked(true, tx: tx)
        record.setBlockedAt(blockedAt, tx: tx)
        if didRemove {
            profileManager.setNeedsProfileKeyRotation(tx: tx)
        }

        Logger.info("blocked groupId: \(record.groupId.toHex())")

        if blockMode.isLocallyInitiated, (try? GroupIdentifier(contents: record.groupId)) != nil {
            let masterKey = record.masterKey
            owsAssertDebug(masterKey != nil, "must have GroupRecord.masterKey in order to block v2 group")
            if let masterKey {
                storageServiceManager.recordPendingUpdates(updatedGroupV2MasterKeys: [masterKey])
            }
        }

        switch blockMode {
        case .backupRestore:
            // If we're restoring from a Backup, avoid the side effect of
            // inserting a message. One either existed in the backup or not.
            break
        case .storageService, .syncMessage, .localUser:
            let groupThread = record.threadId.flatMap {
                return TSGroupThread.threadUniqueId(forThreadId: $0, tx: tx)
            }.flatMap {
                return TSGroupThread.fetchViaCache(uniqueId: $0, transaction: tx)
            }
            owsAssertDebug(groupThread != nil, "Must have TSGroupThread in order to insert an event.")
            if let groupThread {
                // Insert an info message that we blocked this group.
                interactionStore.insertInteraction(
                    TSInfoMessage(thread: groupThread, messageType: .blockedGroup),
                    tx: tx,
                )
            }
        }

        didUpdate(wasLocallyInitiated: blockMode.isLocallyInitiated, tx: tx)
    }

    public func removeBlockedGroup(_ record: inout GroupRecord, wasLocallyInitiated: Bool, tx: DBWriteTransaction) {
        let isBlocked = record.isBlocked
        guard isBlocked else {
            return
        }
        record.setBlocked(false, tx: tx)

        Logger.info("unblocked groupId: \(record.groupId.toHex())")

        if wasLocallyInitiated, (try? GroupIdentifier(contents: record.groupId)) != nil {
            let masterKey = record.masterKey
            owsAssertDebug(masterKey != nil, "must have GroupRecord.masterKey in order to unblock v2 group")
            if let masterKey {
                SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedGroupV2MasterKeys: [masterKey])
            }
        }

        let groupThread = record.threadId.flatMap {
            return TSGroupThread.threadUniqueId(forThreadId: $0, tx: tx)
        }.flatMap {
            return TSGroupThread.fetchViaCache(uniqueId: $0, transaction: tx)
        }
        if let groupThread {
            // Insert an info message that we unblocked.
            DependenciesBridge.shared.interactionStore.insertInteraction(
                TSInfoMessage(thread: groupThread, messageType: .unblockedGroup),
                tx: tx,
            )

            // Refresh unblocked group.
            tx.addSyncCompletion {
                SSKEnvironment.shared.groupV2UpdatesRef.refreshGroupUpThroughCurrentRevision(groupThread: groupThread, throttle: false)
            }
        }

        didUpdate(wasLocallyInitiated: wasLocallyInitiated, tx: tx)
    }

    public func addBlockedReleaseNotesThread(
        thread: TSReleaseNotesThread,
        blockMode: BlockMode,
        transaction: DBWriteTransaction,
    ) {
        let interactionStore = DependenciesBridge.shared.interactionStore
        let storageServiceManager = SSKEnvironment.shared.storageServiceManagerRef

        let isBlocked = blockedReleaseNotesStore.isBlocked(tx: transaction)
        guard !isBlocked else {
            return
        }
        blockedReleaseNotesStore.setBlocked(true, tx: transaction)

        Logger.info("blocked release notes thread")

        interactionStore.insertInteraction(
            TSInfoMessage(thread: thread, messageType: .blockedGroup),
            tx: transaction,
        )

        let wasLocallyInitiated = blockMode.isLocallyInitiated
        if wasLocallyInitiated {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    public func removeBlockedReleaseNotesThread(
        thread: TSReleaseNotesThread,
        wasLocallyInitiated: Bool,
        transaction: DBWriteTransaction,
    ) {
        let interactionStore = DependenciesBridge.shared.interactionStore
        let storageServiceManager = SSKEnvironment.shared.storageServiceManagerRef

        let isBlocked = blockedReleaseNotesStore.isBlocked(tx: transaction)
        guard isBlocked else {
            return
        }
        blockedReleaseNotesStore.setBlocked(false, tx: transaction)

        Logger.info("unblocked release notes thread")

        // Insert an info message that we unblocked.
        interactionStore.insertInteraction(
            TSInfoMessage(thread: thread, messageType: .unblockedGroup),
            tx: transaction,
        )

        if wasLocallyInitiated {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    // MARK: Other convenience access

    public func isThreadBlocked(_ thread: TSThread, transaction: DBReadTransaction) -> Bool {
        if let contactThread = thread as? TSContactThread {
            return isAddressBlocked(contactThread.contactAddress, transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            return _isGroupIdBlocked(groupThread.groupModel.groupId, tx: transaction)
        } else if thread is TSPrivateStoryThread {
            return false
        } else if thread.isReleaseNotesThread {
            return blockedReleaseNotesStore.isBlocked(tx: transaction)
        } else {
            owsFailDebug("Invalid thread: \(type(of: thread))")
            return false
        }
    }

    // MARK: - Syncing

    public func processIncomingSync(
        blockedPhoneNumbers: [E164: BlockedTimestamp],
        blockedAcis: [Aci: BlockedTimestamp],
        blockedGroups: [AnyGroupIdentifier: BlockedTimestamp],
        localIdentifiers: LocalIdentifiers,
        tx transaction: DBWriteTransaction,
    ) {
        let blockMode = BlockMode.syncMessage
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipientStore = DependenciesBridge.shared.recipientDatabaseTable

        Logger.info("")
        transaction.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: Self.blockedSyncDidComplete, object: nil)
        }

        var didChange = false
        var shouldRotateProfileKey = false

        let oldBlockedGroups = GroupStore().fetchBlockedGroups(tx: transaction)
        var newBlockedGroups = blockedGroups
        for var blockedGroup in oldBlockedGroups {
            if
                let groupId = try? blockedGroup.groupIdObj,
                let newBlockedAt = newBlockedGroups.removeValue(forKey: groupId)
            {
                // It was already blocked and should remain blocked.
                if newBlockedAt != .unspecified, blockedGroup.blockedAt != newBlockedAt {
                    blockedGroup.setBlockedAt(newBlockedAt, tx: transaction)
                }
                continue
            }
            blockedGroup.setBlocked(false, tx: transaction)
            didChange = true
        }
        for (groupId, blockedAt) in newBlockedGroups {
            var record = GroupStore().fetchGroupOrInsert(groupId: groupId, tx: transaction)
            let didRemove = profileManager.removeGroupFromProfileWhitelist(
                &record,
                userProfileWriter: blockMode.asUserProfileWriter,
                tx: transaction,
            )
            record.setBlocked(true, tx: transaction)
            record.setBlockedAt(blockedAt, tx: transaction)
            didChange = true
            if didRemove {
                shouldRotateProfileKey = true
            }
        }

        var newBlockedRecipients = [SignalRecipient.RowId: (SignalRecipient, blockedAt: BlockedTimestamp)]()
        for (blockedPhoneNumber, blockedAt) in blockedPhoneNumbers {
            let blockedRecipient = recipientFetcher.fetchOrCreate(phoneNumber: blockedPhoneNumber, tx: transaction)
            newBlockedRecipients[blockedRecipient.id] = (blockedRecipient, blockedAt)
        }
        for (blockedAci, blockedAt) in blockedAcis {
            let blockedRecipient = recipientFetcher.fetchOrCreate(serviceId: blockedAci, tx: transaction)
            newBlockedRecipients[blockedRecipient.id] = (blockedRecipient, blockedAt)
        }

        let oldBlockedRecipients = recipientStore.fetchBlockedRecipients(tx: transaction)
        for var blockedRecipient in oldBlockedRecipients {
            if let (_, blockedAt) = newBlockedRecipients.removeValue(forKey: blockedRecipient.id) {
                // It was already blocked and should remain blocked.
                if blockedAt != .unspecified, blockedRecipient.blockedAt != blockedAt {
                    blockedRecipient.blockedAt = blockedAt
                    recipientStore.updateRecipient(blockedRecipient, transaction: transaction)
                }
                continue
            }
            blockedRecipient.status = .unspecified
            blockedRecipient.blockedAt = .unspecified
            recipientStore.updateRecipient(blockedRecipient, transaction: transaction)
            didChange = true
        }
        for (blockedRecipient, blockedAt) in newBlockedRecipients.values {
            var blockedRecipient = blockedRecipient
            let isLocalRecipient = localIdentifiers.containsAnyOf(
                aci: blockedRecipient.aci,
                phoneNumber: blockedRecipient.phoneNumber?.stringValue,
                pni: blockedRecipient.pni,
            )
            if isLocalRecipient {
                owsFailDebug("ignoring sync message trying to block the local user")
                continue
            }
            let didRemove = profileManager.removeRecipientFromProfileWhitelist(
                &blockedRecipient,
                userProfileWriter: blockMode.asUserProfileWriter,
                tx: transaction,
            )
            blockedRecipient.status = .blocked
            blockedRecipient.blockedAt = blockedAt
            recipientStore.updateRecipient(blockedRecipient, transaction: transaction)
            didChange = true
            if didRemove {
                shouldRotateProfileKey = true
            }
        }

        if shouldRotateProfileKey {
            profileManager.setNeedsProfileKeyRotation(tx: transaction)
        }

        if didChange {
            didUpdate(wasLocallyInitiated: false, tx: transaction)
        }
    }

    public func syncBlockListIfNecessary(force: Bool) async throws {
        let sendResult = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx -> (sendPromise: Promise<Void>, changeToken: UInt64)? in
            let recipientStore = DependenciesBridge.shared.recipientDatabaseTable
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager

            // If we're not forcing a sync, then we only sync if our last synced token is stale
            // and we're not in the NSE. We'll leaving syncing to the main app.
            let changeToken = fetchChangeToken(tx: tx)
            if !force {
                guard shouldSync(changeToken: changeToken, tx: tx) else {
                    return nil
                }
                guard !CurrentAppContext().isNSE else {
                    throw OWSGenericError("Can't send in the NSE.")
                }
            }

            let registeredState = try tsAccountManager.registeredState(tx: tx)

            let localThread = TSContactThread.getOrCreateThread(
                withContactAddress: registeredState.localIdentifiers.aciAddress,
                transaction: tx,
            )

            let blockedRecipients = recipientStore.fetchBlockedRecipients(tx: tx)
            let blockedGroups = GroupStore().fetchBlockedGroups(tx: tx)

            let message = OutgoingBlockedSyncMessage(
                localThread: localThread,
                phoneNumbers: blockedRecipients.compactMap { recipient in
                    return recipient.phoneNumber.map {
                        return OutgoingBlockedSyncMessage.BlockedItem(
                            rawValue: $0.stringValue,
                            blockedAt: recipient.blockedAt,
                        )
                    }
                },
                acis: blockedRecipients.compactMap { recipient in
                    return recipient.aci.map {
                        return OutgoingBlockedSyncMessage.BlockedItem(
                            rawValue: $0,
                            blockedAt: recipient.blockedAt,
                        )
                    }
                },
                groupIds: blockedGroups.map {
                    return OutgoingBlockedSyncMessage.BlockedItem(
                        rawValue: $0.groupId,
                        blockedAt: $0.blockedAt,
                    )
                },
                tx: tx,
            )

            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: message,
            )

            let sendPromise = SSKEnvironment.shared.messageSenderJobQueueRef.add(
                .promise,
                message: preparedMessage,
                transaction: tx,
            )

            return (sendPromise, changeToken)
        }

        guard let sendResult else {
            return
        }

        try await sendResult.sendPromise.awaitable()

        // Record the last block list which we successfully synced..
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            setLastSyncedChangeToken(sendResult.changeToken, transaction: transaction)
        }
    }

    private func shouldSync(changeToken: UInt64, tx: DBReadTransaction) -> Bool {
        // If we've ever sync'd with this mechanism, we need only sync again if the
        // token has changed.
        if let lastSyncedChangeToken = fetchLastSyncedChangeToken(tx: tx) {
            return changeToken != lastSyncedChangeToken
        }
        // Otherwise, if we've made any change, we must sync.
        if changeToken > Constants.initialChangeToken {
            return true
        }
        // If we don't have a last synced change token, we can use the existence of
        // one of our old KVS keys as a hint that we may need to sync. If they
        // don't exist this is probably a fresh install and we don't need to sync.
        return PersistenceKey.Legacy.allCases.contains { key in
            return keyValueStore.hasValue(key.rawValue, transaction: tx)
        }
    }

    // MARK: - Notifications

    public static let blockListDidChange = Notification.Name("blockListDidChange")
    public static let blockedSyncDidComplete = Notification.Name("blockedSyncDidComplete")

    // MARK: - Persistence

    private enum Constants {
        static let initialChangeToken: UInt64 = 1
    }

    private let keyValueStore = KeyValueStore(collection: "kOWSBlockingManager_BlockedPhoneNumbersCollection")

    enum PersistenceKey: String {
        case changeTokenKey = "kOWSBlockingManager_ChangeTokenKey"
        case lastSyncedChangeTokenKey = "kOWSBlockingManager_LastSyncedChangeTokenKey"

        // No longer in use
        enum Legacy: String, CaseIterable {
            case syncedBlockedPhoneNumbersKey = "kOWSBlockingManager_SyncedBlockedPhoneNumbersKey"
            case syncedBlockedUUIDsKey = "kOWSBlockingManager_SyncedBlockedUUIDsKey"
            case syncedBlockedGroupIdsKey = "kOWSBlockingManager_SyncedBlockedGroupIdsKey"
        }
    }

    func fetchChangeToken(tx: DBReadTransaction) -> UInt64 {
        keyValueStore.getUInt64(PersistenceKey.changeTokenKey.rawValue, defaultValue: Constants.initialChangeToken, transaction: tx)
    }

    func setChangeToken(_ newValue: UInt64, tx: DBWriteTransaction) {
        keyValueStore.setUInt64(newValue, key: PersistenceKey.changeTokenKey.rawValue, transaction: tx)
    }

    func fetchLastSyncedChangeToken(tx: DBReadTransaction) -> UInt64? {
        keyValueStore.getUInt64(PersistenceKey.lastSyncedChangeTokenKey.rawValue, transaction: tx)
    }

    func setLastSyncedChangeToken(_ newValue: UInt64, transaction writeTx: DBWriteTransaction) {
        keyValueStore.setUInt64(newValue, key: PersistenceKey.lastSyncedChangeTokenKey.rawValue, transaction: writeTx)
    }
}
