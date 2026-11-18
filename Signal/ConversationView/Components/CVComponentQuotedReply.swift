//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CVComponentQuotedReply: CVComponentBase, CVComponent, CVAccessibilityComponent {

    var componentKey: CVComponentKey { .quotedReply }

    private let quotedReply: CVComponentState.QuotedReply
    private var quotedReplyModel: QuotedReplyModel {
        quotedReply.quotedReplyModel
    }

    private let sharpCornersForQuotedMessage: OWSDirectionalRectCorner

    init(
        itemModel: CVItemModel,
        quotedReply: CVComponentState.QuotedReply,
        sharpCornersForQuotedMessage: OWSDirectionalRectCorner,
    ) {
        self.quotedReply = quotedReply
        self.sharpCornersForQuotedMessage = sharpCornersForQuotedMessage

        super.init(itemModel: itemModel)
    }

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewQuotedReply()
    }

    func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentViewParam as? CVComponentViewQuotedReply else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let quotedMessageView = componentView.quotedMessageView
        let adapter = CVQuotedMessageViewAdapter(interactionUniqueId: interaction.uniqueId)
        quotedMessageView.configureForRendering(
            state: quotedReply.viewState,
            delegate: adapter,
            componentDelegate: componentDelegate,
            sharpCorners: sharpCornersForQuotedMessage,
            cellMeasurement: cellMeasurement,
        )
    }

    private var stackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .fill,
            spacing: 0,
            layoutMargins: .zero,
        )
    }

    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        return CVQuotedMessageView.measure(
            state: quotedReply.viewState,
            maxWidth: maxWidth,
            measurementBuilder: measurementBuilder,
        )
    }

    // MARK: - Events

    override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {

        componentDelegate.didTapQuotedReply(quotedReplyModel)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    class CVComponentViewQuotedReply: CVComponentView {

        fileprivate let quotedMessageView = CVQuotedMessageView(name: "quotedMessageView")

        var isDedicatedCellView = false

        var rootView: UIView {
            quotedMessageView
        }

        func setIsCellVisible(_ isCellVisible: Bool) {
            quotedMessageView.setIsCellVisible(isCellVisible)
        }

        func reset() {
            quotedMessageView.reset()
        }

    }

    // MARK: - CVAccessibilityComponent

    var accessibilityDescription: String {
        let format = OWSLocalizedString(
            "QUOTED_REPLY_ACCESSIBILITY_LABEL_FORMAT",
            comment: "Accessibility label stating the author of the message to which you are replying. Embeds: {{ the author of the message to which you are replying }} {{ original message }}.",
        )

        let originalMessage = self.quotedReply.viewState.quotedReplyModel.originalMessageAccessibilityLabel ?? ""

        if quotedReply.quotedReplyModel.isOriginalMessageAuthorLocalUser {
            return String.nonPluralLocalizedStringWithFormat(format, CommonStrings.you, originalMessage)
        } else {
            return String.nonPluralLocalizedStringWithFormat(
                format,
                self.quotedReply.viewState.quotedAuthorName,
                originalMessage,
            )
        }
    }
}

private class CVQuotedMessageViewAdapter: CVQuotedMessageViewDelegate {

    private let interactionUniqueId: String

    init(interactionUniqueId: String) {
        self.interactionUniqueId = interactionUniqueId
    }

    func didTapDownloadQuotedReplyAttachment(_ quotedReply: QuotedReplyModel) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            guard let message = TSMessage.fetchMessageViaCache(uniqueId: interactionUniqueId, transaction: tx) else {
                return
            }
            DependenciesBridge.shared.attachmentDownloadManager.enqueueDownloadOfAttachmentsForMessage(
                message,
                priority: .userInitiated,
                useThumbnails: false,
                tx: tx,
            )
        }
    }
}
