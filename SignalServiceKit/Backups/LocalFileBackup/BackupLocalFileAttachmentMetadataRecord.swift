//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// Data associated with an attachment that is useful for importing or exporting a local file backup.
struct BackupLocalFileAttachmentMetadataRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "BackupLocalFileAttachmentMetadata"

    let attachmentRowId: Attachment.IDType
    let localKey: Data
    let unencryptedByteCount: UInt32

    enum CodingKeys: String, CodingKey {
        case attachmentRowId
        case localKey
        case unencryptedByteCount
    }
}
