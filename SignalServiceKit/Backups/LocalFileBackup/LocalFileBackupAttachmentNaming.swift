//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit

/// Naming for attachment files in local-file exports.
enum LocalFileBackupAttachmentNaming {

    /// The file name for an attachment, before any path extension.
    static func mediaName(localKey: Data, plaintextHash: Data) -> String {
        var sha = SHA256()
        sha.update(data: plaintextHash + localKey)
        return Data(sha.finalize()).hexadecimalString
    }

    /// The name of the subdirectory, within the attachments directory, that
    /// holds the attachment with the given media name.
    static func subdirectoryName(mediaName: String) -> String {
        return String(mediaName.prefix(2))
    }
}
