//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

extension TSMessage {

    /// Dangerous to use for uninserted messages; exposed only in the Signal target because most rendering
    /// uses already-inserted messages, obviating the concern.
    /// There are some exceptions to this, such as mock messages we insert for purely UI previewing purposes.
    public func hasRenderableContent(tx: DBReadTransaction) -> Bool {
        guard let rowId = self.sqliteRowId else {
            owsAssertDebug(
                self is MockIncomingMessage || self is MockOutgoingMessage,
                "Checking renderable content for uninserted message",
            )
            return TSMessageBuilder.hasRenderableContent(
                hasNonemptyBody: body?.nilIfEmpty != nil,
                hasBodyAttachmentsOrOversizeText: false,
                hasLinkPreview: linkPreview != nil,
                hasQuotedReply: quotedMessage != nil,
                hasContactShare: contactShare != nil,
                hasSticker: messageSticker != nil,
                hasGiftBadge: giftBadge != nil,
                isStoryReply: isStoryReply,
                isPaymentMessage: self is OWSPaymentMessage || self is OWSArchivedPaymentMessage,
                storyReactionEmoji: storyReactionEmoji,
                isPoll: isPoll,
            )
        }
        return insertedMessageHasRenderableContent(rowId: rowId, tx: tx)
    }
}
