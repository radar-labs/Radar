//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public struct LocalFileBackupAttachmentMetadataStore {
    private enum StoreKeys {
        static let lastEnumeratedAttachmentId = "lastEnumeratedAttachmentId"
    }

    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "BackupLocalFileAttachmentMetadata")
    }

    // MARK: -

    func metadataRecord(
        attachmentId: Attachment.IDType,
        tx: DBReadTransaction,
    ) -> BackupLocalFileAttachmentMetadataRecord? {
        failIfThrows {
            try BackupLocalFileAttachmentMetadataRecord
                .filter(key: attachmentId)
                .fetchOne(tx.database)
        }
    }

    func insertNewMetadataIfNeeded(
        attachmentId: Attachment.IDType,
        unencryptedByteCount: UInt32,
        localKey: Data?,
        tx: DBWriteTransaction,
    ) {
        guard metadataRecord(attachmentId: attachmentId, tx: tx) == nil else {
            return
        }

        let localKeyToInsert: Data
        if let localKey {
            localKeyToInsert = localKey
        } else {
            localKeyToInsert = Randomness.generateRandomBytes(64)
        }

        let metadataToInsert = BackupLocalFileAttachmentMetadataRecord(
            attachmentRowId: attachmentId,
            localKey: localKeyToInsert,
            unencryptedByteCount: unencryptedByteCount,
        )

        failIfThrows {
            try metadataToInsert.insert(tx.database)
        }
    }

    // MARK: - Attachment enumeration

    func fetchLastEnumeratedAttachmentRowId(tx: DBReadTransaction) -> Attachment.IDType? {
        kvStore.fetchValue(
            Attachment.IDType.self,
            forKey: StoreKeys.lastEnumeratedAttachmentId,
            tx: tx,
        )
    }

    public func clearLastEnumeratedAttachmentRowId(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.lastEnumeratedAttachmentId, tx: tx)
    }

    func updateLastEnumeratedAttachmentRowId(
        _ attachmentId: Attachment.IDType,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(attachmentId, forKey: StoreKeys.lastEnumeratedAttachmentId, tx: tx)
    }
}
