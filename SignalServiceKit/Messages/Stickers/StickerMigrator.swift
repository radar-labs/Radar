//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct StickerMigrator {
    private typealias Columns = InstalledStickerRecord.CodingKeys

    private let stickerManager: () -> StickerManager
    private let db: DB
    private let logger = PrefixedLogger(prefix: "StickerMigrator")
    private let kvStore = NewKeyValueStore(collection: "StickerMigrator")

    private enum StoreKeys {
        static let lastSeenRowId: String = "lastSeenRowId"
    }

    public init(db: DB, stickerManager: @escaping () -> StickerManager) {
        self.db = db
        self.stickerManager = stickerManager
    }

    public func needsToRun() -> Bool {
        return db.read { tx in
            // Row IDs start at 1, so 0 means we've visited every row.
            return lastMigratedStickerRowId(tx: tx) > 0
        }
    }

    public func run() async throws(CancellationError) {
        logger.info("Starting...")

        struct TxContext {
            var lastMigratedStickerRowId: Int64
        }

        try await TimeGatedBatch.processAll(
            db: db,
            buildTxContext: { tx -> TxContext in
                let lastMigratedStickerRowId = lastMigratedStickerRowId(tx: tx)
                return TxContext(
                    lastMigratedStickerRowId: lastMigratedStickerRowId,
                )
            },
            processBatch: { tx, txContext throws(CancellationError) in
                guard !Task.isCancelled else {
                    throw CancellationError()
                }

                guard
                    let installedStickerRow = fetchNextUnmigratedRow(beforeId: txContext.lastMigratedStickerRowId, tx: tx)
                else {
                    txContext.lastMigratedStickerRowId = 0
                    return .done(())
                }

                if installedStickerRow.localKey == nil {
                    migrate(installedStickerRow, tx: tx)
                }

                txContext.lastMigratedStickerRowId = installedStickerRow.id.owsFailUnwrap("Fetched record must have rowID")
                return .more
            },
            concludeTx: { tx, txContext in
                setLastMigratedStickerRowId(txContext.lastMigratedStickerRowId, tx: tx)
            },
        )

        logger.info("Done!")
    }

    // MARK: -

    private func fetchNextUnmigratedRow(
        beforeId: Int64,
        tx: DBReadTransaction,
    ) -> InstalledStickerRecord? {
        return try? InstalledStickerRecord
            .filter(Columns.id < beforeId)
            .order(Columns.id.desc)
            .fetchOne(tx.database)
    }

    private func migrate(_ row: InstalledStickerRecord, tx: DBWriteTransaction) {
        let stickerType = StickerType.stickerType(forContentType: row.contentType)
        let url = stickerManager().cacheDirUrl()
            .appendingPathComponent("\(row.uniqueId).\(stickerType.fileExtension)")

        let plaintext: Data
        do {
            plaintext = try Data(contentsOf: url)
        } catch {
            logger.warn("Missing or unreadable sticker file \(row.uniqueId); skipping. \(error)")
            return
        }

        let key = AttachmentKey.generate()
        let encryptedData: Data
        let encryptionMetadata: EncryptionMetadata
        do {
            (encryptedData, encryptionMetadata) = try Cryptography.encrypt(
                plaintext,
                attachmentKey: key,
                applyExtraPadding: false,
            )
        } catch {
            logger.warn("Encryption failed for sticker \(row.uniqueId); skipping. \(error)")
            return
        }

        guard let plaintextLength = UInt32(exactly: encryptionMetadata.plaintextLength) else {
            logger.warn("Sticker \(row.uniqueId) plaintext too large to migrate; skipping.")
            return
        }

        do {
            try encryptedData.write(to: url, options: .atomic)
        } catch {
            logger.warn("Failed to write encrypted sticker \(row.uniqueId); skipping. \(error)")
            return
        }

        // If the file isn't a valid image. A prior migration
        // run may have crashed after encrypting the file but before updating the DB,
        // or the image is otherwise broken. Delete the installed record row.
        guard DataImageSource(plaintext).ows_isValidImage else {
            logger.warn("Sticker \(row.uniqueId) file is not a valid image; Deleting row.")
            do {
                try InstalledStickerRecord.filter(Columns.id == row.id).deleteAll(tx.database)
                try? FileManager.default.removeItem(at: url)
            } catch {
                logger.warn("Failed to delete corrupt sticker row \(row.uniqueId): \(error)")
            }
            return
        }

        do {
            try InstalledStickerRecord
                .filter(Columns.id == row.id)
                .updateAll(tx.database, [
                    Columns.localKey.set(to: key.combinedKey),
                    Columns.plaintextLength.set(to: plaintextLength),
                ])
        } catch {
            logger.warn("Failed to update sticker row \(error)")
        }
    }

    // MARK: - KVStore

    func lastMigratedStickerRowId(tx: DBReadTransaction) -> Int64 {
        return kvStore.fetchValue(
            Int64.self,
            forKey: StoreKeys.lastSeenRowId,
            tx: tx,
        ) ?? .max
    }

    func setLastMigratedStickerRowId(
        _ attachmentId: Int64,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(
            attachmentId,
            forKey: StoreKeys.lastSeenRowId,
            tx: tx,
        )
    }
}
