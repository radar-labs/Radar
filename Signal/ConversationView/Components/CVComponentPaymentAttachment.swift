//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
public import SignalUI

@objc
public class CVComponentPaymentAttachment: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .paymentAttachment }

    private let paymentAttachment: CVComponentState.PaymentAttachment
    private let paymentModel: TSPaymentModel?
    private let paymentAmount: UInt64?
    private let contactName: String
    private let messageStatus: MessageReceiptStatus
    private let footerState: CVComponentFooter.State?

    init(
        itemModel: CVItemModel,
        paymentAttachment: CVComponentState.PaymentAttachment,
        paymentModel: TSPaymentModel?,
        contactName: String,
        paymentAmount: UInt64?,
        messageStatus: MessageReceiptStatus?,
        footerState: CVComponentFooter.State?
    ) {
        self.paymentAttachment = paymentAttachment
        self.paymentModel = paymentModel
        self.contactName = contactName
        self.paymentAmount = paymentAmount
        self.footerState = footerState

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
        paymentAttachment.notification.memoMessage?.nilIfEmpty
    }

    private var amountNumberText: String {
        guard !PaymentsDisplayPreferences.shared.isBalanceHidden else {
            return PaymentsFormat.hiddenBalanceString
        }
        guard let mob = paymentAmount else {
            return OWSLocalizedString(
                "PAYMENTS_INFO_UNAVAILABLE_MESSAGE",
                comment: "Status indicator for invalid payments which could not be processed."
            )
        }
        if PaymentsDisplayPreferences.shared.isSatoshiEnabled {
            return "\(mob)"
        }
        return PaymentsFormat.format(picoMob: mob, isShortForm: false) ?? "\(mob)"
    }

    private var amountUnitText: String {
        " " + (PaymentsDisplayPreferences.shared.isSatoshiEnabled ? "sats" : "BTC")
    }

    private var badgeText: String {
        let paymentType = paymentModel?.paymentType
        let interactionType = itemModel.interaction.interactionType
        switch (paymentType, interactionType, messageStatus) {
        case (_, _, .sending):
            return OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_IN_CHAT_PROCESSING",
                comment: "Payment status context while sending"
            )
        case (_, .incomingMessage, _),
            (.incomingPayment, _, _),
            (.incomingUnidentified, _, _):
            return OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_RECEIVED",
                comment: "Badge label shown on received payment bubbles in chat"
            )
        case (_, .outgoingMessage, .failed):
            return OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_FAILED",
                comment: "Badge label shown on failed payment bubbles in chat"
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
        CVComponentViewPaymentAttachment()
    }

    public func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate
    ) {
        guard let componentView = componentViewParam as? CVComponentViewPaymentAttachment else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let textColor = conversationStyle.bubbleTextColor(isIncoming: isIncoming)
        let dimTextColor = textColor.withAlphaComponent(isIncoming ? 0.5 : 0.75)
        let statusTextColor = conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming)
        let accentBgColor: UIColor = isIncoming
            ? UIColor.black.withAlphaComponent(0.12)
            : UIColor.white.withAlphaComponent(0.15)

        // Badge pill
        componentView.badgePillView.backgroundColor = accentBgColor
        componentView.badgeLabel.text = badgeText
        componentView.badgeLabel.textColor = textColor
        let arrowSymbol = isIncoming ? "arrow.down.right" : "arrow.up.right"
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

        // Fiat label (hidden — no fiat data available for payment attachments yet)
        componentView.fiatLabel.isHidden = true

        // Footer timestamp and status indicator
        let timestampText = footerState?.timestampText ?? ""

        // Note section
        if let note = noteText {
            // Footer lives inside the note section
            componentView.topFooterStack.isHidden = true

            componentView.noteLabel.text = note
            componentView.noteLabel.textColor = textColor
            componentView.noteSectionView.backgroundColor = accentBgColor
            componentView.noteSectionView.isHidden = false

            componentView.noteTimestampLabel.text = timestampText
            componentView.noteTimestampLabel.textColor = statusTextColor
            configureStatusView(
                componentView.noteStatusView,
                widthConstraint: componentView.noteStatusWidthConstraint,
                heightConstraint: componentView.noteStatusHeightConstraint,
                tintColor: statusTextColor
            )
            componentView.noteFooterStack.isHidden = false
        } else {
            // Footer lives in the top section, bottom-right
            componentView.noteSectionView.isHidden = true

            componentView.topTimestampLabel.text = timestampText
            componentView.topTimestampLabel.textColor = statusTextColor
            configureStatusView(
                componentView.topStatusView,
                widthConstraint: componentView.topStatusWidthConstraint,
                heightConstraint: componentView.topStatusHeightConstraint,
                tintColor: statusTextColor
            )
            componentView.topFooterStack.isHidden = false
        }
    }

    private func configureStatusView(
        _ statusView: UIImageView,
        widthConstraint: NSLayoutConstraint?,
        heightConstraint: NSLayoutConstraint?,
        tintColor: UIColor
    ) {
        if let si = footerState?.statusIndicator, let icon = UIImage(named: si.imageName) {
            statusView.image = icon.withRenderingMode(.alwaysTemplate)
            statusView.tintColor = tintColor
            widthConstraint?.constant = si.imageSize.width
            heightConstraint?.constant = si.imageSize.height
            statusView.isHidden = false
        } else {
            statusView.isHidden = true
        }
    }

    // MARK: - Measurement

    public func measure(
        maxWidth: CGFloat,
        measurementBuilder: CVCellMeasurement.Builder
    ) -> CGSize {
        owsAssertDebug(maxWidth > 0)
        return CVComponentArchivedPayment.measurePaymentBubble(
            noteText: noteText,
            badgeText: badgeText,
            amountNumberText: amountNumberText,
            amountUnitText: amountUnitText,
            maxWidth: maxWidth
        )
    }

    // MARK: - CVComponentView

    public class CVComponentViewPaymentAttachment: NSObject, CVComponentView {

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

        // Top section footer row (shown when no note)
        let topFooterStack = UIStackView()
        let topTimestampLabel = UILabel()
        let topStatusView = UIImageView()
        var topStatusWidthConstraint: NSLayoutConstraint?
        var topStatusHeightConstraint: NSLayoutConstraint?

        // Note section
        let noteSectionView = UIView()
        let noteLabel = UILabel()

        // Note section footer row (shown when note is present)
        let noteFooterStack = UIStackView()
        let noteTimestampLabel = UILabel()
        let noteStatusView = UIImageView()
        var noteStatusWidthConstraint: NSLayoutConstraint?
        var noteStatusHeightConstraint: NSLayoutConstraint?

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

            badgePillView.heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true

            // Badge wrapper — keeps pill left-aligned within the fill-aligned stack
            let badgeWrapperView = UIView()
            badgeWrapperView.addSubview(badgePillView)
            badgePillView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                badgePillView.topAnchor.constraint(equalTo: badgeWrapperView.topAnchor),
                badgePillView.leadingAnchor.constraint(equalTo: badgeWrapperView.leadingAnchor),
                badgePillView.bottomAnchor.constraint(equalTo: badgeWrapperView.bottomAnchor)
                // No trailing — pill hugs its content width
            ])

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

            // Top footer row (timestamp + status, right-aligned)
            topTimestampLabel.font = UIFont.systemFont(ofSize: 13)
            topTimestampLabel.numberOfLines = 1
            topTimestampLabel.setContentHuggingPriority(.required, for: .horizontal)

            topFooterStack.addArrangedSubview(topStatusView)
            let topStatusWC = topStatusView.widthAnchor.constraint(equalToConstant: 12)
            let topStatusHC = topStatusView.heightAnchor.constraint(equalToConstant: 12)
            topStatusWC.isActive = true
            topStatusHC.isActive = true
            topStatusWidthConstraint = topStatusWC
            topStatusHeightConstraint = topStatusHC
            topStatusView.contentMode = .scaleAspectFit

            let topFooterSpacer = UIView()
            topFooterSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            topFooterSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            topFooterStack.axis = .horizontal
            topFooterStack.spacing = 3
            topFooterStack.alignment = .center
            topFooterStack.removeArrangedSubview(topStatusView)
            topStatusView.removeFromSuperview()
            topFooterStack.addArrangedSubview(topFooterSpacer)
            topFooterStack.addArrangedSubview(topTimestampLabel)
            topFooterStack.addArrangedSubview(topStatusView)

            // Top content stack — .fill so topFooterStack can stretch to full width
            let topContentStack = UIStackView(arrangedSubviews: [badgeWrapperView, amountRow, fiatLabel, topFooterStack])
            topContentStack.axis = .vertical
            topContentStack.spacing = 4
            topContentStack.alignment = .fill
            topContentStack.isLayoutMarginsRelativeArrangement = true
            topContentStack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

            // Note section
            noteLabel.font = UIFont.systemFont(ofSize: 16)
            noteLabel.numberOfLines = 0

            // Note footer row (timestamp + status, right-aligned within note section)
            noteTimestampLabel.font = UIFont.systemFont(ofSize: 13)
            noteTimestampLabel.numberOfLines = 1
            noteTimestampLabel.setContentHuggingPriority(.required, for: .horizontal)

            noteFooterStack.addArrangedSubview(noteStatusView)
            let noteStatusWC = noteStatusView.widthAnchor.constraint(equalToConstant: 12)
            let noteStatusHC = noteStatusView.heightAnchor.constraint(equalToConstant: 12)
            noteStatusWC.isActive = true
            noteStatusHC.isActive = true
            noteStatusWidthConstraint = noteStatusWC
            noteStatusHeightConstraint = noteStatusHC
            noteStatusView.contentMode = .scaleAspectFit

            let noteFooterSpacer = UIView()
            noteFooterSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            noteFooterSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            noteFooterStack.axis = .horizontal
            noteFooterStack.spacing = 3
            noteFooterStack.alignment = .center
            noteFooterStack.removeArrangedSubview(noteStatusView)
            noteStatusView.removeFromSuperview()
            noteFooterStack.addArrangedSubview(noteFooterSpacer)
            noteFooterStack.addArrangedSubview(noteTimestampLabel)
            noteFooterStack.addArrangedSubview(noteStatusView)

            noteSectionView.addSubview(noteLabel)
            noteSectionView.addSubview(noteFooterStack)
            noteLabel.translatesAutoresizingMaskIntoConstraints = false
            noteFooterStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                noteLabel.topAnchor.constraint(equalTo: noteSectionView.topAnchor, constant: 12),
                noteLabel.leadingAnchor.constraint(equalTo: noteSectionView.leadingAnchor, constant: 12),
                noteLabel.trailingAnchor.constraint(equalTo: noteSectionView.trailingAnchor, constant: -12),
                noteLabel.bottomAnchor.constraint(equalTo: noteFooterStack.topAnchor, constant: -4),
                noteFooterStack.leadingAnchor.constraint(equalTo: noteSectionView.leadingAnchor, constant: 12),
                noteFooterStack.trailingAnchor.constraint(equalTo: noteSectionView.trailingAnchor, constant: -12),
                noteFooterStack.bottomAnchor.constraint(equalTo: noteSectionView.bottomAnchor, constant: -12)
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
            topTimestampLabel.text = nil
            topStatusView.image = nil
            topStatusView.isHidden = true
            topFooterStack.isHidden = false
            noteLabel.text = nil
            noteSectionView.isHidden = true
            noteTimestampLabel.text = nil
            noteStatusView.image = nil
            noteStatusView.isHidden = true
            noteFooterStack.isHidden = true
        }
    }

    // MARK: - Tap handler

    public override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem
    ) -> Bool {
        guard let paymentModel = paymentModel else { return false }
        let paymentHistoryItem = PaymentsHistoryModelItem(
            paymentModel: paymentModel,
            displayName: contactName
        )
        componentDelegate.didTapPayment(paymentHistoryItem)
        return true
    }
}

// MARK: - Accessibility

extension CVComponentPaymentAttachment: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        let amount = amountNumberText + amountUnitText
        if let note = noteText {
            return amount + ". " + note
        }
        return amount
    }
}
