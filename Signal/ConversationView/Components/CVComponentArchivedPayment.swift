//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
public import SignalUI

@objc
public class CVComponentArchivedPayment: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .archivedPaymentAttachment }

    private let archivedPaymentAttachment: CVComponentState.ArchivedPaymentAttachment
    private let messageStatus: MessageReceiptStatus

    init(
        itemModel: CVItemModel,
        archivedPaymentAttachment: CVComponentState.ArchivedPaymentAttachment,
        messageStatus: MessageReceiptStatus?
    ) {
        self.archivedPaymentAttachment = archivedPaymentAttachment

        switch (messageStatus, itemModel.interaction.interactionType) {
        case (nil, .incomingMessage):
            self.messageStatus = .sent
        case (.some(let messageStatus), _):
            self.messageStatus = messageStatus
        default:
            self.messageStatus = .failed
        }

        super.init(itemModel: itemModel)
    }

    // MARK: - Content helpers

    private var noteText: String? {
        archivedPaymentAttachment.note?.nilIfEmpty
    }

    private var amountNumberText: String {
        guard !PaymentsDisplayPreferences.shared.isBalanceHidden else {
            return PaymentsFormat.hiddenBalanceString
        }
        return archivedPaymentAttachment.amount ?? OWSLocalizedString(
            "PAYMENTS_INFO_UNAVAILABLE_MESSAGE",
            comment: "Status indicator for invalid payments which could not be processed."
        )
    }

    private var amountUnitText: String {
        " " + (PaymentsDisplayPreferences.shared.isSatoshiEnabled ? "sats" : "BTC")
    }

    private var badgeText: String {
        switch (itemModel.interaction.interactionType, messageStatus) {
        case (.incomingMessage, _):
            return OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_RECEIVED",
                comment: "Badge label shown on received payment bubbles in chat"
            )
        case (_, .failed):
            return OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_FAILED",
                comment: "Badge label shown on failed payment bubbles in chat"
            )
        case (_, .sending):
            return OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_IN_CHAT_PROCESSING",
                comment: "Payment status context while sending"
            )
        default:
            return OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_SENT",
                comment: "Badge label shown on sent payment bubbles in chat"
            )
        }
    }

    // MARK: - Build component view

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewArchivedPayment()
    }

    public func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate
    ) {
        guard let componentView = componentViewParam as? CVComponentViewArchivedPayment else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let textColor = conversationStyle.bubbleTextColor(isIncoming: isIncoming)
        let dimTextColor = textColor.withAlphaComponent(isIncoming ? 0.5 : 0.75)
        let accentBgColor: UIColor = isIncoming
            ? UIColor.black.withAlphaComponent(0.05)
            : UIColor.white.withAlphaComponent(0.15)

        // Badge pill
        componentView.badgePillView.backgroundColor = accentBgColor
        componentView.badgeLabel.text = badgeText
        componentView.badgeLabel.textColor = textColor
        let arrowSymbol = isIncoming ? "arrow.down.left" : "arrow.up.right"
        componentView.badgeIconView.image = UIImage(systemName: arrowSymbol)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        componentView.badgeIconView.tintColor = textColor

        // Badge order: received = [icon, label], sent = [label, icon]
        componentView.badgePillStack.arrangedSubviews.forEach {
            componentView.badgePillStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if isIncoming {
            componentView.badgePillStack.addArrangedSubview(componentView.badgeIconView)
            componentView.badgePillStack.addArrangedSubview(componentView.badgeLabel)
        } else {
            componentView.badgePillStack.addArrangedSubview(componentView.badgeLabel)
            componentView.badgePillStack.addArrangedSubview(componentView.badgeIconView)
        }

        // Amount
        let amountAlpha: CGFloat = messageStatus == .sending ? 0.5 : 1
        componentView.amountNumberLabel.text = amountNumberText
        componentView.amountNumberLabel.textColor = textColor
        componentView.amountNumberLabel.alpha = amountAlpha
        componentView.amountUnitLabel.text = amountUnitText
        componentView.amountUnitLabel.textColor = dimTextColor
        componentView.amountUnitLabel.alpha = amountAlpha

        // Fiat label (hidden — no fiat data available for archived payments yet)
        componentView.fiatLabel.isHidden = true

        // Note section
        if let note = noteText {
            componentView.noteLabel.text = note
            componentView.noteLabel.textColor = textColor
            componentView.noteSectionView.backgroundColor = accentBgColor
            componentView.noteSectionView.isHidden = false
        } else {
            componentView.noteSectionView.isHidden = true
        }
    }

    // MARK: - Measurement

    public func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder
    ) -> CGSize {
        owsAssertDebug(maxWidth > 0)
        return Self.measurePaymentBubble(noteText: noteText, maxWidth: maxWidth)
    }

    static func measurePaymentBubble(noteText: String?, maxWidth: CGFloat) -> CGSize {
        let outerPadding: CGFloat = 12
        let itemSpacing: CGFloat = 4

        let badgeFont = UIFont.systemFont(ofSize: 12)
        let badgeHeight = max(22, ceil(badgeFont.lineHeight) + 6)

        let amountFont = UIFont.systemFont(ofSize: 28, weight: .medium)
        let amountHeight = ceil(amountFont.lineHeight)

        let topSectionHeight = outerPadding + badgeHeight + itemSpacing + amountHeight + outerPadding

        var noteSectionHeight: CGFloat = 0
        if let note = noteText, !note.isEmpty {
            let noteFont = UIFont.systemFont(ofSize: 16)
            let noteMaxWidth = maxWidth - outerPadding * 2
            let noteRect = (note as NSString).boundingRect(
                with: CGSize(width: max(1, noteMaxWidth), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: noteFont],
                context: nil
            )
            noteSectionHeight = ceil(noteRect.height) + outerPadding * 2
        }

        return CGSize(width: maxWidth, height: topSectionHeight + noteSectionHeight)
    }

    // MARK: - CVComponentView

    public class CVComponentViewArchivedPayment: NSObject, CVComponentView {

        private let containerView = UIView()

        // Badge pill
        let badgePillView = UIView()
        let badgePillStack = UIStackView()
        let badgeIconView = UIImageView()
        let badgeLabel = UILabel()

        // Amount row
        let amountNumberLabel = UILabel()
        let amountUnitLabel = UILabel()

        // Fiat amount
        let fiatLabel = UILabel()

        // Note section
        let noteSectionView = UIView()
        let noteLabel = UILabel()

        public var isDedicatedCellView = true

        public var rootView: UIView { containerView }

        override init() {
            super.init()
            setupViews()
        }

        private func setupViews() {
            // Badge pill
            badgePillView.layer.cornerRadius = 11
            badgePillView.clipsToBounds = true

            badgeLabel.font = UIFont.systemFont(ofSize: 12)
            badgeLabel.numberOfLines = 1
            badgeLabel.setContentHuggingPriority(.required, for: .horizontal)

            badgeIconView.contentMode = .scaleAspectFit
            badgeIconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                badgeIconView.widthAnchor.constraint(equalToConstant: 16),
                badgeIconView.heightAnchor.constraint(equalToConstant: 16)
            ])

            badgePillStack.axis = .horizontal
            badgePillStack.spacing = 2
            badgePillStack.alignment = .center
            badgePillStack.addArrangedSubview(badgeIconView)
            badgePillStack.addArrangedSubview(badgeLabel)

            badgePillView.addSubview(badgePillStack)
            badgePillStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                badgePillStack.topAnchor.constraint(equalTo: badgePillView.topAnchor, constant: 3),
                badgePillStack.bottomAnchor.constraint(equalTo: badgePillView.bottomAnchor, constant: -3),
                badgePillStack.leadingAnchor.constraint(equalTo: badgePillView.leadingAnchor, constant: 8),
                badgePillStack.trailingAnchor.constraint(equalTo: badgePillView.trailingAnchor, constant: -8)
            ])

            let badgePillHeightConstraint = badgePillView.heightAnchor.constraint(greaterThanOrEqualToConstant: 22)
            badgePillHeightConstraint.isActive = true

            // Amount row
            amountNumberLabel.font = UIFont.systemFont(ofSize: 28, weight: .medium)
            amountNumberLabel.numberOfLines = 1
            amountNumberLabel.setContentHuggingPriority(.required, for: .horizontal)

            amountUnitLabel.font = UIFont.systemFont(ofSize: 28, weight: .medium)
            amountUnitLabel.numberOfLines = 1
            amountUnitLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let amountRow = UIStackView(arrangedSubviews: [amountNumberLabel, amountUnitLabel])
            amountRow.axis = .horizontal
            amountRow.spacing = 2
            amountRow.alignment = .lastBaseline

            // Fiat label
            fiatLabel.font = UIFont.systemFont(ofSize: 16)
            fiatLabel.numberOfLines = 1
            fiatLabel.isHidden = true

            // Top content stack
            let topContentStack = UIStackView(arrangedSubviews: [badgePillView, amountRow, fiatLabel])
            topContentStack.axis = .vertical
            topContentStack.spacing = 4
            topContentStack.alignment = .leading
            topContentStack.isLayoutMarginsRelativeArrangement = true
            topContentStack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

            // Note section
            noteLabel.font = UIFont.systemFont(ofSize: 16)
            noteLabel.numberOfLines = 0

            noteSectionView.addSubview(noteLabel)
            noteLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                noteLabel.topAnchor.constraint(equalTo: noteSectionView.topAnchor, constant: 12),
                noteLabel.leadingAnchor.constraint(equalTo: noteSectionView.leadingAnchor, constant: 12),
                noteLabel.trailingAnchor.constraint(equalTo: noteSectionView.trailingAnchor, constant: -12),
                noteLabel.bottomAnchor.constraint(equalTo: noteSectionView.bottomAnchor, constant: -12)
            ])

            // Main layout
            let mainStack = UIStackView(arrangedSubviews: [topContentStack, noteSectionView])
            mainStack.axis = .vertical
            mainStack.spacing = 0
            mainStack.alignment = .fill

            containerView.addSubview(mainStack)
            mainStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                mainStack.topAnchor.constraint(equalTo: containerView.topAnchor),
                mainStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                mainStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                mainStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            badgeLabel.text = nil
            badgeIconView.image = nil
            amountNumberLabel.text = nil
            amountUnitLabel.text = nil
            amountNumberLabel.alpha = 1
            amountUnitLabel.alpha = 1
            fiatLabel.text = nil
            fiatLabel.isHidden = true
            noteLabel.text = nil
            noteSectionView.isHidden = true
        }
    }

    // MARK: - Tap handler

    public override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem
    ) -> Bool {
        guard let contactAddress = (thread as? TSContactThread)?.contactAddress else {
            owsFailDebug("Should be contact thread")
            return false
        }
        guard let archivedPayment = archivedPaymentAttachment.archivedPayment else { return false }
        guard let item = ArchivedPaymentHistoryItem(
            archivedPayment: archivedPayment,
            address: contactAddress,
            displayName: archivedPaymentAttachment.otherUserShortName,
            interaction: interaction
        ) else {
            return false
        }
        componentDelegate.didTapPayment(item)
        return true
    }
}

// MARK: - Accessibility

extension CVComponentArchivedPayment: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        let amount = amountNumberText + amountUnitText
        if let note = noteText {
            return amount + ". " + note
        }
        return amount
    }
}
