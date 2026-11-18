//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentManagerMock: AttachmentManager {

    open func createAttachmentPointer(
        from ownedProto: OwnedAttachmentPointerProto,
        tx: DBWriteTransaction,
    ) throws -> Attachment.IDType {
        // Do nothing
        return 0
    }

    open func createAttachmentPointer(
        from ownedBackupProto: OwnedAttachmentBackupPointerProto,
        uploadEra: String,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        tx: DBWriteTransaction,
    ) {
        // Do nothing
    }

    open func createAttachmentStream(
        from ownedDataSource: OwnedAttachmentDataSource,
        tx: DBWriteTransaction,
    ) -> Attachment.IDType {
        // Do nothing
        return 0
    }

    open func updateAttachmentWithOversizeTextFromBackup(
        attachmentId: Attachment.IDType,
        pendingAttachment: PendingAttachment,
        tx: DBWriteTransaction,
    ) {
        // Do nothing
    }

    open func createQuotedReplyMessageThumbnail(
        from quotedReplyAttachmentDataSource: QuotedReplyAttachmentDataSource,
        owningMessageAttachmentBuilder: AttachmentReference.OwnerBuilder.MessageAttachmentBuilder,
        tx: DBWriteTransaction,
    ) throws -> Attachment.IDType {
        // Do nothing
        return 0
    }
}

#endif
