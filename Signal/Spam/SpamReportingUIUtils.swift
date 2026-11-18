//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

enum ReportSpamUIUtils {
    static func showReportSpamActionSheet(
        from viewController: UIViewController,
        forThread thread: TSThread,
        isBlocked: Bool,
        onSuccess: @escaping @MainActor (OutgoingMessageRequestResponseSyncMessage.ResponseType) -> Void,
    ) {
        let actionSheet = createReportSpamActionSheet(
            forThread: thread,
            isBlocked: isBlocked,
            declineMessageRequest: { responseType in
                MessageRequestDecliner.declineMessageRequest(inThread: thread, responseType: responseType)
                onSuccess(responseType)
            },
        )
        viewController.presentActionSheet(actionSheet)
    }

    static func createReportSpamActionSheet(
        forThread thread: TSThread,
        isBlocked: Bool,
        declineMessageRequest: @escaping @MainActor (OutgoingMessageRequestResponseSyncMessage.ResponseType) -> Void,
    ) -> ActionSheetController {
        let actionSheetTitle = OWSLocalizedString(
            "MESSAGE_REQUEST_REPORT_CONVERSATION_TITLE",
            comment: "Action sheet title to confirm reporting a conversation as spam via a message request.",
        )
        let actionSheetMessage = OWSLocalizedString(
            "MESSAGE_REQUEST_REPORT_CONVERSATION_MESSAGE",
            comment: "Action sheet message to confirm reporting a conversation as spam via a message request.",
        )

        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)
        actionSheet.addAction(
            ActionSheetAction(
                title: OWSLocalizedString(
                    "MESSAGE_REQUEST_REPORT_SPAM_ACTION",
                    comment: "Action sheet action to confirm reporting a conversation as spam via a message request.",
                ),
                handler: { _ in
                    declineMessageRequest(.spam)
                },
            ),
        )
        if !isBlocked, !thread.isTerminatedGroup {
            actionSheet.addAction(
                ActionSheetAction(
                    title: OWSLocalizedString(
                        "MESSAGE_REQUEST_BLOCK_AND_REPORT_SPAM_ACTION",
                        comment: "Action sheet action to confirm blocking and reporting spam for a thread via a message request.",
                    ),
                    handler: { _ in
                        declineMessageRequest(.blockAndSpam)
                    },
                ),
            )
        }
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel))
        return actionSheet
    }

    static func successfulReportText(didBlock: Bool) -> String {
        if didBlock {
            OWSLocalizedString(
                "MESSAGE_REQUEST_SPAM_REPORTED_AND_BLOCKED",
                comment: "String indicating that spam has been reported and the chat has been blocked.",
            )
        } else {
            OWSLocalizedString(
                "MESSAGE_REQUEST_SPAM_REPORTED",
                comment: "String indicating that spam has been reported.",
            )
        }
    }

    static func insertSpamReportMessage(in thread: TSThread, tx: DBWriteTransaction) -> SpamReport? {
        var aci: Aci?
        var isGroup = false
        if let contactThread = thread as? TSContactThread {
            aci = contactThread.contactAddress.serviceId as? Aci
        } else if let groupThread = thread as? TSGroupThread {
            isGroup = true
            let accountManager = DependenciesBridge.shared.tsAccountManager
            guard let localIdentifiers = accountManager.localIdentifiers(tx: tx) else {
                owsFailDebug("Missing local identifiers")
                return nil
            }
            let groupMembership = groupThread.groupModel.groupMembership
            if let invitedAtServiceId = groupMembership.localUserInvitedAtServiceId(localIdentifiers: localIdentifiers) {
                aci = groupMembership.addedByAci(forInvitedMember: invitedAtServiceId)
            }
        } else {
            owsFailDebug("Unexpected thread type for reporting spam \(type(of: thread))")
            return nil
        }

        let infoMessage = TSInfoMessage(thread: thread, messageType: .reportedSpam)
        infoMessage.anyInsert(transaction: tx)

        guard let aci else {
            owsFailDebug("Missing ACI for reporting spam")
            return nil
        }

        // We only report a selection of the N most recent messages
        // in the conversation.
        let maxMessagesToReport = 3

        var guidsToReport = Set<String>()
        do {
            if isGroup {
                guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx) else {
                    owsFailDebug("Unable to find local identifiers")
                    return nil
                }
                try InteractionFinder(
                    threadUniqueId: thread.uniqueId,
                ).enumerateRecentGroupUpdateMessages(
                    transaction: tx,
                ) { infoMessage, stop in
                    guard let groupUpdateItems = infoMessage.computedGroupUpdateItems(localIdentifiers: localIdentifiers, tx: tx) else {
                        return
                    }

                    for item in groupUpdateItems {
                        if
                            let serverGuid = infoMessage.serverGuid,
                            let updaterAci = item.aciForSpamReporting,
                            updaterAci.wrappedValue == aci
                        {
                            guidsToReport.insert(serverGuid)
                        }
                    }
                    guard guidsToReport.count < maxMessagesToReport else {
                        stop = true
                        return
                    }
                }

            } else {
                try InteractionFinder(
                    threadUniqueId: thread.uniqueId,
                ).enumerateInteractionsForConversationView(
                    rowIdFilter: .newest,
                    tx: tx,
                ) { interaction -> Bool in
                    guard let incomingMessage = interaction as? TSIncomingMessage else { return true }
                    if let serverGuid = incomingMessage.serverGuid {
                        guidsToReport.insert(serverGuid)
                    }
                    if guidsToReport.count < maxMessagesToReport {
                        return true
                    }
                    return false
                }
            }
        } catch {
            owsFailDebug("Failed to lookup guids to report \(error)")
        }

        let reportingToken = SpamReportingTokenRecord.reportingToken(for: aci, database: tx.database)

        guard !guidsToReport.isEmpty else {
            Logger.warn("No messages with serverGuids to report.")
            return nil
        }

        return SpamReport(
            aci: aci,
            serverGuids: guidsToReport,
            reportingToken: reportingToken,
        )
    }
}
