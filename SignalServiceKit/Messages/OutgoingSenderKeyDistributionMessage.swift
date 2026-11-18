//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

final class OutgoingSenderKeyDistributionMessage: TransientOutgoingMessage {

    /// True if this message is being sent as a precondition to sending an
    /// online-only message. Typing indicators are only delivered to online
    /// devices. Since they're ephemeral we just don't bother sending a typing
    /// indicator to a recipient if we need the user to verify a safety number
    /// change. Outgoing SKDMs being sent on behalf of an outgoing typing
    /// indicator should inherit this behavior.
    let isSentOnBehalfOfOnlineMessage: Bool

    /// True if this message is being sent as a precondition to sending a story
    /// message.
    let isSentOnBehalfOfStoryMessage: Bool

    let senderKeyDistributionMessage: SenderKeyDistributionMessage

    init(
        recipientThread: TSContactThread,
        senderKeyDistributionMessage: SenderKeyDistributionMessage,
        onBehalfOfMessage originalMessage: any SendableMessage,
        inThread originalThread: TSThread,
        tx: DBReadTransaction,
    ) {
        self.senderKeyDistributionMessage = senderKeyDistributionMessage
        self.isSentOnBehalfOfOnlineMessage = originalMessage.isOnline
        self.isSentOnBehalfOfStoryMessage = originalMessage.isStorySend && !originalThread.isGroupThread
        super.init(
            outgoingMessageWith: TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: recipientThread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        owsFail("Doesn't support serialization.")
    }

    required init?(coder: NSCoder) {
        // Doesn't support serialization.
        return nil
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.isSentOnBehalfOfOnlineMessage)
        hasher.combine(self.isSentOnBehalfOfStoryMessage)
        hasher.combine(self.senderKeyDistributionMessage.serialize())
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.isSentOnBehalfOfOnlineMessage == object.isSentOnBehalfOfOnlineMessage else { return false }
        guard self.isSentOnBehalfOfStoryMessage == object.isSentOnBehalfOfStoryMessage else { return false }
        guard self.senderKeyDistributionMessage.serialize() == object.senderKeyDistributionMessage.serialize() else { return false }
        return true
    }

    override var shouldRecordSendLog: Bool { false }

    override var isUrgent: Bool { false }

    override var isStorySend: Bool { self.isSentOnBehalfOfStoryMessage }

    override var contentHint: SealedSenderContentHint { .implicit }

    override func contentBuilder(thread: TSThread, transaction: DBReadTransaction) -> SSKProtoContentBuilder? {
        let builder = SSKProtoContent.builder()
        builder.setSenderKeyDistributionMessage(self.senderKeyDistributionMessage.serialize())
        return builder
    }
}
