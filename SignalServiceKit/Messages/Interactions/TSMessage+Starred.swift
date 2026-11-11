//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Radar: starred messages.
///
/// The flag lives in the `isStarred` column of `model_TSInteraction`, which the
/// Radar migration `addStarredMessageColumn` adds with a default of `false`.
///
/// It is intentionally *not* part of `InteractionRecord`. SDS writes every
/// encoded column whenever a message is saved, so keeping the flag outside the
/// record means routine message updates (receipts, edits, expiration, ...)
/// can never reset it, and upstream changes to the message model don't need to
/// carry it along.
extension TSMessage {

    public func isStarred(tx: DBReadTransaction) -> Bool {
        guard let rowId = self.sqliteRowId else {
            return false
        }
        return failIfThrows {
            try Bool.fetchOne(
                tx.database,
                sql: "SELECT isStarred FROM \(InteractionRecord.databaseTableName) WHERE id = ?",
                arguments: [rowId],
            ) ?? false
        }
    }

    public func setIsStarred(_ isStarred: Bool, tx: DBWriteTransaction) {
        guard let rowId = self.sqliteRowId else {
            owsFailDebug("Can't star a message that hasn't been saved.")
            return
        }
        failIfThrows {
            try tx.database.execute(
                sql: "UPDATE \(InteractionRecord.databaseTableName) SET isStarred = ? WHERE id = ?",
                arguments: [isStarred, rowId],
            )
        }
        // Let observers (e.g. the starred-messages list) reload this message.
        SSKEnvironment.shared.databaseStorageRef.touch(interaction: self, shouldReindex: false, tx: tx)
    }
}
