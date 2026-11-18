//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// Represents an attachment we are waiting to copy to the user's local file backup destination.
/// If a file is present in the table, we haven't copied it yet.
struct BackupLocalFileAttachmentExportRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "BackupLocalFileAttachmentExport"

    let attachmentRowId: Attachment.IDType

    static let persistenceConflictPolicy: PersistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .ignore,
        update: .ignore,
    )

    enum CodingKeys: String, CodingKey {
        case attachmentRowId
    }
}
