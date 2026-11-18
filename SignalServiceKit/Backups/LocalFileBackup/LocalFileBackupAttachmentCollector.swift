//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class LocalFileBackupAttachmentCollector {
    private(set) var attachments: [Attachment.IDType] = []

    func append(id: Attachment.IDType) {
        attachments.append(id)
    }
}
