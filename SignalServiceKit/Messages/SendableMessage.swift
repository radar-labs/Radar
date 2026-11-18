//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

protocol SendableMessage {
    var threadUniqueId: String { get }

    var sqliteRowId: Int64? { get }

    var uniqueId: String { get }

    var timestamp: UInt64 { get }

    /// If true, this message corresponds to a story and should use story=true
    /// authentication and story account existence semantics.
    var isStorySend: Bool { get }

    /// If true, this message should set the "online" flag to indicate that it
    /// should only be delivered if the recipient is currently online (e.g.,
    /// typing indicator messages).
    var isOnline: Bool { get }

    /// If true, this message should set the "urgent" flag (e.g., text messages
    /// are urgent and receipts are not).
    var isUrgent: Bool { get }

    /// Indicates desired behavior if decryption fails.
    var contentHint: SealedSenderContentHint { get }

    /// Indicates how the message should be encrypted.
    var encryptionStyle: EncryptionStyle { get }

    // TODO: Remove the thread parameter?
    /// Builds the serialized Content protobuf for this message.
    func buildPlaintextData(inThread thread: TSThread, tx: DBWriteTransaction) throws -> Data

    // TODO: Merge this into the return value when sending a message.
    var wasSentToAnyRecipient: Bool { get }

    func sendingRecipientAddresses() -> [SignalServiceAddress]

    func sentRecipientAddresses() -> [SignalServiceAddress]

    func insertedMessageHasRenderableContent(rowId: Int64, tx: DBReadTransaction) -> Bool

    func anyUpdateOutgoingMessage(transaction: DBWriteTransaction, block: (TSOutgoingMessage) -> Void)

    func updateWithSkippedRecipients(_ skippedRecipients: some Sequence<SignalServiceAddress>, tx: DBWriteTransaction)

    func updateWithFailedRecipients(_ recipientErrors: some Sequence<(serviceId: ServiceId, error: Error)>, tx: DBWriteTransaction)

    func updateWithSentRecipients(_ serviceIds: some Sequence<ServiceId>, wasSentByUD: Bool, tx: DBWriteTransaction)

    // TODO: Add SyncTranscriptableMessage protocol for these properties.

    /// Indicates that this message needs a sync transcript.
    ///
    /// If true, `buildSyncTranscriptMessage` will be invoked.
    func shouldSyncTranscript() -> Bool

    /// Builds a sync transcript for this message.
    ///
    /// Only invoked if `shouldSyncTranscript` returns true.
    func buildSyncTranscriptMessage(localThread: TSContactThread, tx: DBWriteTransaction) throws -> OutgoingSyncMessage

    func thread(tx: DBReadTransaction) -> TSThread?

    var shouldBeSaved: Bool { get }

    /// True if this message should be stored in the Message Send Log.
    var shouldRecordSendLog: Bool { get }

    var relatedUniqueIds: Set<String> { get }

    func envelopeGroupIdWithTransaction(_ transaction: DBReadTransaction) -> Data?

    func update(withHasSyncedTranscript: Bool, transaction: DBWriteTransaction)
}

extension TSOutgoingMessage: SendableMessage {
    var threadUniqueId: String { self.uniqueThreadId }
}
