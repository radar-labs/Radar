//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/**
 * Abstract base class used for the family of sync messages which take care
 * of keeping your multiple registered devices consistent. E.g. sharing contacts, sharing groups,
 * notifying your devices of sent messages, and "read" receipts.
 */
@objc(OWSOutgoingSyncMessage)
public class OutgoingSyncMessage: TransientOutgoingMessage {

    override public class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    init(localThread: TSContactThread, tx: DBReadTransaction) {
        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: localThread)
        super.init(
            outgoingMessageWith: messageBuilder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    init(timestamp: UInt64, localThread: TSContactThread, tx: DBReadTransaction) {
        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: localThread)
        messageBuilder.timestamp = timestamp
        super.init(
            outgoingMessageWith: messageBuilder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override public func shouldSyncTranscript() -> Bool { false }

    // This method should not be overridden because we want to add random padding to *every* sync message
    private func buildSyncMessage(tx: DBReadTransaction) -> SSKProtoSyncMessage? {
        guard let builder = self.syncMessageBuilder(tx: tx) else {
            return nil
        }
        do {
            return try Self.buildSyncMessageProto(forMessageBuilder: builder)
        } catch {
            owsFailDebug("could not build protobuf: \(error)")
            return nil
        }
    }

    func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        owsFail("Method must be implemented by subclasses.")
    }

    override public func contentBuilder(thread: TSThread, transaction: DBReadTransaction) -> SSKProtoContentBuilder? {
        guard let syncMessage = self.buildSyncMessage(tx: transaction) else {
            return nil
        }

        let contentBuilder = SSKProtoContent.builder()
        contentBuilder.setSyncMessage(syncMessage)
        return contentBuilder
    }

    static func buildSyncMessageProto(forMessageBuilder messageBuilder: SSKProtoSyncMessageBuilder) throws -> SSKProtoSyncMessage {
        // Add a random 1-512 bytes to obscure sync message type
        let paddingBytesLength = UInt.random(in: 1...512)
        messageBuilder.setPadding(Randomness.generateRandomBytes(paddingBytesLength))
        return try messageBuilder.build()
    }
}
