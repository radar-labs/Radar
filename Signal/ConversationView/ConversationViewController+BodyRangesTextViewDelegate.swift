//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

extension ConversationViewController {
    var supportsMentions: Bool { thread.allowsMentionSend }

    func textViewDidBeginTypingMention(_ textView: BodyRangesTextView) {}

    func textViewDidEndTypingMention(_ textView: BodyRangesTextView) {}

    func textViewMentionPickerParentView(_ textView: BodyRangesTextView) -> UIView? {
        view
    }

    func textViewMentionPickerReferenceView(_ textView: BodyRangesTextView) -> UIView? {
        bottomBarContainer
    }

    func textViewMentionPickerPossibleAcis(_ textView: BodyRangesTextView, tx: DBReadTransaction) -> [Aci] {
        supportsMentions ? thread.recipientAddresses(with: tx).compactMap(\.aci) : []
    }

    func textViewMentionCacheInvalidationKey(_ textView: BodyRangesTextView) -> String {
        return thread.uniqueId
    }

    func textViewDisplayConfiguration(_ textView: BodyRangesTextView) -> HydratedMessageBody.DisplayConfiguration {
        return .composing(textViewColor: textView.textColor)
    }

    func mentionPickerStyle(_ textView: BodyRangesTextView) -> MentionPickerStyle {
        return .default
    }

    func textViewDidInsertMemoji(_ memojiGlyph: OWSAdaptiveImageGlyph) {
        do {
            let attachmentLimits = OutgoingAttachmentLimits.currentLimits()
            self.didPasteAttachments(
                [try PasteboardAttachment.loadPreviewableMemojiAttachment(fromMemojiGlyph: memojiGlyph)],
                attachmentLimits: attachmentLimits,
            )
        } catch {
            self.showErrorAlert(attachmentError: error as? SignalAttachmentError)
        }
    }
}
