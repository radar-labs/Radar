//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Manages the metadata, such as the local key, required to include an
/// attachment in a local-file export.
public class LocalFileBackupAttachmentMetadataManager {
    public enum ProgressLabel {
        public static let ensureAttachmentMetadataExists = "ensureAttachmentMetadataExists"
    }

    private let attachmentStore: AttachmentStore
    private let db: DB
    private let metadataStore: LocalFileBackupAttachmentMetadataStore

    init(
        attachmentStore: AttachmentStore,
        db: DB,
        metadataStore: LocalFileBackupAttachmentMetadataStore,
    ) {
        self.attachmentStore = attachmentStore
        self.db = db
        self.metadataStore = metadataStore
    }

    /// Ensure metadata exists for all attachments with a plaintext hash.
    func ensureAttachmentMetadataExists(
        progressSink: OWSProgressSink?,
    ) async throws(CancellationError) {
        struct TxContextAttachmentMetadata {
            var cursor: FailIfThrowsRecordCursor<Attachment.Record>
            var lastEnumeratedAttachmentId: Attachment.IDType?
            var didFinish: Bool
        }

        let totalRemainingAttachmentCount = db.read { tx in
            let lastEnumeratedAttachmentId = metadataStore
                .fetchLastEnumeratedAttachmentRowId(tx: tx)

            return attachmentStore.countAttachmentsWithPlaintextHash(
                afterRowId: lastEnumeratedAttachmentId,
                tx: tx,
            )
        }
        let source = progressSink?.addSource(
            withLabel: ProgressLabel.ensureAttachmentMetadataExists,
            unitCount: UInt64(totalRemainingAttachmentCount),
        )

        try await TimeGatedBatch.processAll(
            db: db,
            buildTxContext: { tx -> TxContextAttachmentMetadata in
                let lastEnumeratedAttachmentId = metadataStore
                    .fetchLastEnumeratedAttachmentRowId(tx: tx)

                return TxContextAttachmentMetadata(
                    cursor: attachmentStore.attachmentsWithPlaintextHash(
                        afterRowId: lastEnumeratedAttachmentId,
                        tx: tx,
                    ),
                    lastEnumeratedAttachmentId: lastEnumeratedAttachmentId,
                    didFinish: false,
                )
            },
            processBatch: { tx, txContext throws(CancellationError) -> TimeGatedBatch.ProcessBatchResult<Void> in
                if Task.isCancelled {
                    throw CancellationError()
                }

                guard
                    let attachment = txContext.cursor.next().map({
                        Attachment(record: $0)
                    })
                else {
                    txContext.didFinish = true
                    return .done(())
                }

                source?.incrementCompletedUnitCount(by: 1)

                if let streamInfo = attachment.streamInfo {
                    metadataStore.insertNewMetadataIfNeeded(
                        attachmentId: attachment.id,
                        unencryptedByteCount: streamInfo.unencryptedByteCount,
                        // Create a new local key if it doesn't exist.
                        localKey: nil,
                        tx: tx,
                    )
                }

                txContext.lastEnumeratedAttachmentId = attachment.id
                return .more
            },
            concludeTx: { tx, txContext in
                if txContext.didFinish {
                    metadataStore.clearLastEnumeratedAttachmentRowId(tx: tx)
                    source?.complete()
                } else if let lastEnumeratedAttachmentId = txContext.lastEnumeratedAttachmentId {
                    metadataStore.updateLastEnumeratedAttachmentRowId(
                        lastEnumeratedAttachmentId,
                        tx: tx,
                    )
                }
            },
        )
    }
}
