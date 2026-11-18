//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct UnreadReminderManager {
    private static let defaultReminderInterval: TimeInterval = 72 * .hour

    private static let maxSenderNames = 3

    private static let maxInspectedUnreadMessages = 500

    private let contactManager: any ContactManager
    private let notificationPreferencesManager: NotificationPreferencesManager
    private let notificationPresenter: any NotificationPresenter
    private let tsAccountManager: any TSAccountManager

    public init(
        contactManager: any ContactManager,
        notificationPreferencesManager: NotificationPreferencesManager,
        notificationPresenter: any NotificationPresenter,
        tsAccountManager: any TSAccountManager,
    ) {
        self.contactManager = contactManager
        self.notificationPreferencesManager = notificationPreferencesManager
        self.notificationPresenter = notificationPresenter
        self.tsAccountManager = tsAccountManager
    }

    private var reminderInterval: TimeInterval {
        let testingOverride = DebugFlags.unreadReminderIntervalSecs.get()
        if testingOverride > 0 {
            return TimeInterval(testingOverride)
        }
        return Self.defaultReminderInterval
    }

    public func didChangeMuteState(thread: TSThread, tx: DBWriteTransaction) {
        if thread.isMuted {
            // The mute duration might have been shortened to end before the
            // notification is scheduled to fire. scheduleReminderIfNeeded will
            // cancel and reschedule as needed
            scheduleReminderIfNeeded(thread: thread, tx: tx)
        } else {
            // Only muted chats have unread reminders
            notificationPresenter.cancelUnreadReminder(threadUniqueId: thread.uniqueId, tx: tx)
        }
    }

    /// Cancels the unread reminder if the chat has been read or deleted
    public func reconcile(thread: TSThread, tx: DBReadTransaction) {
        let hasUnreadMessages = InteractionFinder(threadUniqueId: thread.uniqueId).unreadCount(transaction: tx) > 0
        if thread.isMuted, hasUnreadMessages {
            return
        }
        notificationPresenter.cancelUnreadReminder(threadUniqueId: thread.uniqueId, tx: tx)
    }

    public func didReceiveMessage(_ message: TSIncomingMessage, in thread: TSThread, tx: DBWriteTransaction) {
        scheduleReminderIfNeeded(thread: thread, tx: tx)
    }

    // MARK: - Settings

    public func setGlobalShowUnreadReminders(
        _ value: Bool,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        notificationPreferencesManager.setGlobalShowUnreadReminders(
            value,
            updateStorageService: updateStorageService,
            tx: tx,
        )

        // Threads with a per-thread preference are unaffected.
        var mutedThreads = [TSThread]()
        ThreadFinder().enumerateNonStoryThreads(tx: tx) { thread in
            if thread.isMuted, thread.shouldNotifyForUnreadRemindersWhenMuted == nil {
                mutedThreads.append(thread)
            }
            return true
        }
        for thread in mutedThreads {
            if value {
                scheduleReminderIfNeeded(thread: thread, tx: tx)
            } else {
                notificationPresenter.cancelUnreadReminder(threadUniqueId: thread.uniqueId, tx: tx)
            }
        }
    }

    /// - Parameter value: `nil` inherits the global preference
    public func setShowUnreadReminders(
        _ value: Bool?,
        thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        notificationPreferencesManager.setShowUnreadReminders(
            value,
            thread: thread,
            updateStorageService: updateStorageService,
            tx: tx,
        )

        guard thread.isMuted else { return }
        if notificationPreferencesManager.showUnreadReminders(thread: thread, tx: tx) {
            scheduleReminderIfNeeded(thread: thread, tx: tx)
        } else {
            notificationPresenter.cancelUnreadReminder(threadUniqueId: thread.uniqueId, tx: tx)
        }
    }

    // MARK: - Scheduling

    private func scheduleReminderIfNeeded(thread: TSThread, tx: DBWriteTransaction) {
        guard
            BuildFlags.improvedNotifications,
            notificationPreferencesManager.showUnreadReminders(thread: thread, tx: tx)
        else {
            return
        }

        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
        let unreadCount = Int(interactionFinder.unreadCount(transaction: tx))
        guard unreadCount > 0 else {
            return
        }

        let allowsNames = notificationPreferencesManager.previewType(tx: tx) != .noNameNoPreview
        let summary = fetchSummary(
            unreadCount: unreadCount,
            thread: thread,
            allowsNames: allowsNames,
            interactionFinder: interactionFinder,
            tx: tx,
        )

        notificationPresenter.scheduleUnreadReminder(
            threadUniqueId: thread.uniqueId,
            // Don't group by thread if names are hidden
            threadIdentifier: allowsNames ? thread.uniqueId : nil,
            title: allowsNames ? contactManager.displayName(for: thread, tx: tx)?.resolvedValue() : nil,
            body: Self.notificationBody(for: summary),
            initialDelay: reminderInterval,
            // A reminder about a chat that's no longer muted would be wrong.
            latestFireDate: Date(millisecondsSince1970: thread.mutedUntilTimestamp),
            tx: tx,
        )
    }

    // MARK: - Summary

    /// What an unread reminder is about. Names are left empty when the user
    /// hides them, and mentions and replies are only gathered when they'd be
    /// shown.
    struct Summary {
        struct Category {
            var count = 0
            /// Distinct names of up to `maxSenderNames` senders, oldest first.
            var senderNames = [String]()
        }

        var messages: Category
        var mentions = Category()
        var replies = Category()
    }

    func fetchSummary(
        unreadCount: Int,
        thread: TSThread,
        allowsNames: Bool,
        interactionFinder: InteractionFinder,
        tx: DBReadTransaction,
    ) -> Summary {
        var summary = Summary(messages: Summary.Category(count: unreadCount))
        guard allowsNames else {
            return summary
        }

        let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
        let localAci = localIdentifiers?.aci
        let localAddress = localIdentifiers?.aciAddress

        let includesMentions = thread.isGroupThread && localAci != nil
            && notificationPreferencesManager.notifyForMentionsWhenMuted(thread: thread, tx: tx)
        let includesReplies = thread.isGroupThread && localAddress != nil
            && notificationPreferencesManager.notifyForRepliesWhenMuted(thread: thread, tx: tx)

        var messageSenders = [SignalServiceAddress]()
        var mentionSenders = [SignalServiceAddress]()
        var replySenders = [SignalServiceAddress]()

        // More generic summary when we can't get full results
        func incompleteSummary() -> Summary {
            let names = messageSenders.count >= Self.maxSenderNames ? messageSenders : []
            return Summary(messages: Summary.Category(count: unreadCount, senderNames: displayNames(for: names, tx: tx)))
        }

        var inspectedCount = 0
        var cursor = interactionFinder.fetchAllUnreadMessages(transaction: tx)
        do {
            while let unreadItem = try cursor.next() {
                guard inspectedCount < Self.maxInspectedUnreadMessages else {
                    return incompleteSummary()
                }

                inspectedCount += 1
                guard let incomingMessage = unreadItem as? TSIncomingMessage else {
                    continue
                }
                let author = incomingMessage.authorAddress
                Self.save(sender: author, in: &messageSenders)

                if
                    includesMentions,
                    let mentions = incomingMessage.bodyRanges?.orderedMentions,
                    mentions.contains(where: { $0.value == localAci })
                {
                    summary.mentions.count += 1
                    Self.save(sender: author, in: &mentionSenders)
                }

                if
                    includesReplies,
                    let quotedAuthor = incomingMessage.quotedMessage?.authorAddress,
                    let localAddress,
                    quotedAuthor.isEqualToAddress(localAddress)
                {
                    summary.replies.count += 1
                    Self.save(sender: author, in: &replySenders)
                }

                // Once enough names are known, only continue if we need to
                // compile mention and reply counts.
                if messageSenders.count >= Self.maxSenderNames, !includesMentions, !includesReplies {
                    break
                }
            }
        } catch {
            owsFailDebug("Couldn't fetch unread messages: \(error)")
            return incompleteSummary()
        }

        summary.messages.senderNames = displayNames(for: messageSenders, tx: tx)
        summary.mentions.senderNames = displayNames(for: mentionSenders, tx: tx)
        summary.replies.senderNames = displayNames(for: replySenders, tx: tx)
        return summary
    }

    private static func save(sender: SignalServiceAddress, in senders: inout [SignalServiceAddress]) {
        guard senders.count < maxSenderNames else { return }
        if !senders.contains(where: { $0.isEqualToAddress(sender) }) {
            senders.append(sender)
        }
    }

    private func displayNames(for addresses: [SignalServiceAddress], tx: DBReadTransaction) -> [String] {
        guard !addresses.isEmpty else { return [] }
        return contactManager.displayNames(for: addresses, tx: tx).map { $0.resolvedValue() }
    }

    // MARK: - Copy

    static func notificationBody(for summary: Summary) -> String {
        let messagesPhrase = String.localizedStringWithFormat(
            OWSLocalizedString(
                "UnreadReminderJob__messages",
                tableName: "PluralAware",
                comment: "Notification placeholder for unread messages",
            ),
            summary.messages.count,
        )
        let mentionsPhrase = mentionsPhrase(for: summary.mentions)
        let repliesPhrase = repliesPhrase(for: summary.replies)

        switch (mentionsPhrase, repliesPhrase) {
        case (let mentionsPhrase?, let repliesPhrase?):
            return String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__unread_both_summary",
                    comment: "Notification body for unread reminders. First placeholder is unread messages, second is a summary of unread mentions, third replies",
                ),
                messagesPhrase,
                mentionsPhrase,
                repliesPhrase,
            )
        case (let highlightsPhrase?, nil), (nil, let highlightsPhrase?):
            return String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__unread_one_summary",
                    comment: "Notification body for unread reminders. First placeholder is unread messages, second is a summary of either unread mentions or replies",
                ),
                messagesPhrase,
                highlightsPhrase,
            )
        case (nil, nil):
            break
        }

        if let sendersPhrase = sendersPhrase(for: summary.messages.senderNames) {
            return String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__calls_or_unread_author",
                    comment: "Notification body for unread reminders. First placeholder is unread messages, second is a list of people who sent them",
                ),
                messagesPhrase,
                sendersPhrase,
            )
        }
        return String.nonPluralLocalizedStringWithFormat(
            OWSLocalizedString(
                "UnreadReminderJob__calls_or_unread",
                comment: "Notification body for unread reminders. First placeholder is unread messages or unread calls",
            ),
            messagesPhrase,
        )
    }

    private static func sendersPhrase(for names: [String]) -> String? {
        switch names.count {
        case 0:
            return nil
        case 1:
            return String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__authors_one",
                    comment: "Notification placeholder for a single recipient who sent unread messages",
                ),
                names[0],
            )
        case 2:
            return String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__authors_two",
                    comment: "Notification placeholder for two recipients who sent unread messages",
                ),
                names[0],
                names[1],
            )
        default:
            return String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__authors_many",
                    comment: "Notification placeholder for three or more recipients who sent unread messages",
                ),
                names[0],
            )
        }
    }

    /// e.g. "a mention of you by Alice" or "5 mentions of you by Alice and others"
    private static func mentionsPhrase(for mentions: Summary.Category) -> String? {
        switch mentions.senderNames.count {
        case 0:
            return nil
        case 1:
            return String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__mentions_one",
                    comment: "Notification placeholder that sums up a single unread mention. Placeholder is the name of the person who sent the message",
                ),
                mentions.senderNames[0],
            )
        case 2:
            return String.localizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__mentions_two",
                    tableName: "PluralAware",
                    comment: "Notification placeholder that sums up unread mentions from two people. First placeholder is the number of mentions, second and third are the names of the people who sent them",
                ),
                mentions.count,
                mentions.senderNames[0],
                mentions.senderNames[1],
            )
        default:
            return String.localizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__mentions_many",
                    tableName: "PluralAware",
                    comment: "Notification placeholder that sums up unread mentions from three or more people. First placeholder is the number of mentions, second is the name of one person who sent them",
                ),
                mentions.count,
                mentions.senderNames[0],
            )
        }
    }

    /// e.g. "a reply from Alice" or "5 replies from Alice and others"
    private static func repliesPhrase(for replies: Summary.Category) -> String? {
        switch replies.senderNames.count {
        case 0:
            return nil
        case 1:
            return String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__replies_one",
                    comment: "Notification placeholder that sums up a single unread reply. Placeholder is the name of the person who sent the message",
                ),
                replies.senderNames[0],
            )
        case 2:
            return String.localizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__replies_two",
                    tableName: "PluralAware",
                    comment: "Notification placeholder that sums up unread replies from two people. First placeholder is the number of replies, second and third are the names of the people who sent them",
                ),
                replies.count,
                replies.senderNames[0],
                replies.senderNames[1],
            )
        default:
            return String.localizedStringWithFormat(
                OWSLocalizedString(
                    "UnreadReminderJob__replies_many",
                    tableName: "PluralAware",
                    comment: "Notification placeholder that sums up unread replies from three or more people. First placeholder is the number of replies, second is the name of one person who sent them",
                ),
                replies.count,
                replies.senderNames[0],
            )
        }
    }
}
