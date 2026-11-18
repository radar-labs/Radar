//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

enum MessageRequestDecliner {
    @MainActor
    static func declineMessageRequest(
        inThread thread: TSThread,
        responseType: OutgoingMessageRequestResponseSyncMessage.ResponseType,
    ) {
        let blockingManager = SSKEnvironment.shared.blockingManagerRef
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let deleteManager = DependenciesBridge.shared.threadDeletionManager
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let syncManager = SSKEnvironment.shared.syncManagerRef
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        // Leave the group if we're going to block it or delete it. (If we're only
        // reporting spam without blocking it, we remain a member of the group.)
        let shouldLeaveGroup = responseType.shouldBlockThread || responseType.shouldDeleteThread

        databaseStorage.write { tx in
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx).owsFailUnwrap("never registered")
            let timestamp = MessageTimestampGenerator.sharedInstance.generateTimestamp()

            syncManager.sendMessageRequestResponseSyncMessage(
                forThread: thread,
                timestamp: timestamp,
                responseType: responseType,
                tx: tx,
            )
            if responseType.shouldBlockThread {
                switch thread {
                case let thread as TSContactThread:
                    if localIdentifiers.contains(address: thread.contactAddress) {
                        owsFailDebug("can't block note to self")
                    } else if var recipient = recipientFetcher.fetchOrCreate(address: thread.contactAddress, tx: tx) {
                        blockingManager.addBlockedRecipient(
                            &recipient,
                            blockedAt: BlockedTimestamp(clamping: timestamp),
                            blockMode: .localUser,
                            tx: tx,
                        )
                    } else {
                        owsFailDebug("can't block contact thread with invalid address")
                    }
                case let thread as TSGroupThread:
                    if var groupRecord = GroupStore().fetchGroup(forGroupIdData: thread.groupId, tx: tx) {
                        blockingManager.addBlockedGroup(
                            &groupRecord,
                            blockedAt: BlockedTimestamp(clamping: timestamp),
                            blockMode: .localUser,
                            tx: tx,
                        )
                    } else {
                        owsFailDebug("can't block group thread that's somehow missing its GroupRecord")
                    }
                case let thread as TSReleaseNotesThread:
                    blockingManager.addBlockedReleaseNotesThread(thread: thread, blockMode: .localUser, transaction: tx)
                default:
                    owsFailDebug("can't block thread: \(type(of: thread))")
                }
            }
            if responseType.shouldReportSpam {
                let spamReport = ReportSpamUIUtils.insertSpamReportMessage(in: thread, tx: tx)
                // We don't wait for this because it's best effort.
                Task {
                    _ = try? await spamReport?.submit(using: SSKEnvironment.shared.networkManagerRef)
                }
            }
            if shouldLeaveGroup, let thread = thread as? TSGroupThread, thread.groupModel.groupMembership.isLocalUserFullOrInvitedMember {
                // We don't wait for this because it's durably enqeueued and may take up to
                // 24 hours to complete.
                _ = GroupManager.localLeaveGroupOrDeclineInvite(
                    groupThread: thread,
                    waitForMessageProcessing: true,
                    tx: tx,
                )
            }
            if responseType.shouldDeleteThread {
                deleteManager.deleteThreads(
                    [thread],
                    // We're already sending a sync message about this above!
                    sendDeleteForMeSyncMessage: false,
                    updateStorageService: true,
                    localIdentifiers: localIdentifiers,
                    tx: tx,
                )
            }
        }
    }
}
