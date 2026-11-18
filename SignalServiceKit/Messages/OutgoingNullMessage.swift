//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSOutgoingNullMessage)
final class OutgoingNullMessage: TransientOutgoingMessage {

    init(contactThread: TSContactThread, tx: DBReadTransaction) {
        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: contactThread)
        super.init(
            outgoingMessageWith: messageBuilder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func contentBuilder(thread: TSThread, transaction: DBReadTransaction) -> SSKProtoContentBuilder? {
        let contentBuilder = SSKProtoContent.builder()
        contentBuilder.setNullMessage(SSKProtoNullMessage.builder().buildInfallibly())
        return contentBuilder
    }

    override func shouldSyncTranscript() -> Bool { false }

    override var contentHint: SealedSenderContentHint { .implicit }
}
