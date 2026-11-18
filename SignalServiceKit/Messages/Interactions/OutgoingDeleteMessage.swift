//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

@objc(TSOutgoingDeleteMessage)
public final class OutgoingDeleteMessage: TransientOutgoingMessage {
    let messageTimestamp: UInt64
    let messageUniqueId: String?
    let isDeletingStoryMessage: Bool

    public init(
        thread: TSThread,
        message: TSOutgoingMessage,
        tx: DBReadTransaction,
    ) {
        owsAssertDebug(thread.uniqueId == message.uniqueThreadId)

        self.messageTimestamp = message.timestamp
        self.messageUniqueId = message.uniqueId
        self.isDeletingStoryMessage = false

        super.init(
            outgoingMessageWith: TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override public class var supportsSecureCoding: Bool { true }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.isDeletingStoryMessage), forKey: "isDeletingStoryMessage")
        coder.encode(NSNumber(value: self.messageTimestamp), forKey: "messageTimestamp")
        if let messageUniqueId {
            coder.encode(messageUniqueId, forKey: "messageUniqueId")
        }
    }

    public required init?(coder: NSCoder) {
        self.isDeletingStoryMessage = coder.decodeObject(of: NSNumber.self, forKey: "isDeletingStoryMessage")?.boolValue ?? false
        guard let messageTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "messageTimestamp") else {
            return nil
        }
        self.messageTimestamp = messageTimestamp.uint64Value
        self.messageUniqueId = coder.decodeObject(of: NSString.self, forKey: "messageUniqueId") as String?
        super.init(coder: coder)
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.isDeletingStoryMessage)
        hasher.combine(self.messageTimestamp)
        hasher.combine(self.messageUniqueId)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.isDeletingStoryMessage == object.isDeletingStoryMessage else { return false }
        guard self.messageTimestamp == object.messageTimestamp else { return false }
        guard self.messageUniqueId == object.messageUniqueId else { return false }
        return true
    }

    public init(
        thread: TSThread,
        storyMessage: StoryMessage,
        skippedRecipients: some Sequence<ServiceId>,
        tx: DBReadTransaction,
    ) {
        self.messageTimestamp = storyMessage.timestamp
        self.messageUniqueId = storyMessage.uniqueId
        self.isDeletingStoryMessage = true

        super.init(
            outgoingMessageWith: TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: skippedRecipients.map(ServiceIdObjC.wrapValue(_:)),
            transaction: tx,
        )
    }

    override public var isStorySend: Bool {
        return self.isDeletingStoryMessage
    }

    override public func dataMessageBuilder(with thread: TSThread, transaction: DBReadTransaction) -> SSKProtoDataMessageBuilder? {
        let deleteBuilder = SSKProtoDataMessageDelete.builder(targetSentTimestamp: self.messageTimestamp)
        let deleteProto: SSKProtoDataMessageDelete
        do {
            deleteProto = try deleteBuilder.build()
        } catch {
            owsFailDebug("could not build protobuf: \(error)")
            return nil
        }

        let builder = super.dataMessageBuilder(with: thread, transaction: transaction)
        builder?.setTimestamp(self.timestamp)
        builder?.setDelete(deleteProto)
        return builder
    }

    override public func anyUpdateOutgoingMessage(transaction: DBWriteTransaction, block: (TSOutgoingMessage) -> Void) {
        super.anyUpdateOutgoingMessage(transaction: transaction, block: block)

        // Some older outgoing delete messages didn't store the deleted message's
        // unique id. We want to mirror our sending state onto the original
        // message, so it shows up within the conversation.
        if let messageUniqueId {
            let deletedMessage = TSOutgoingMessage.fetchOutgoingMessageViaCache(uniqueId: messageUniqueId, transaction: transaction)
            deletedMessage?.updateWithRecipientAddressStates(self.recipientAddressStates, tx: transaction)
        }
    }

    override public var relatedUniqueIds: Set<String> {
        return super.relatedUniqueIds.union([self.messageUniqueId].compacted())
    }
}
