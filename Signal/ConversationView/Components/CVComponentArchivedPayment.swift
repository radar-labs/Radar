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
    private let footerState: CVComponentFooter.State?

    init(
        itemModel: CVItemModel,
        archivedPaymentAttachment: CVComponentState.ArchivedPaymentAttachment,
        messageStatus: MessageReceiptStatus?,
        footerState: CVComponentFooter.State?
    ) {
        self.archivedPaymentAttachment = archivedPaymentAttachment
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
        archivedPaymentAttachment.note?.nilIfEmpty
    }

    private var amountNumberText: String {
        guard !PaymentsDisplayPreferences.shared.isBalanceHidden else {
            return PaymentsFormat.hiddenBalanceString
        }
        if let mob = archivedPaymentAttachment.recoveredAmountPicoMob {
            if PaymentsDisplayPreferences.shared.isSatoshiEnabled {
                return "\(mob)"
            }
            return PaymentsFormat.format(picoMob: mob, isShortForm: false) ?? "\(mob)"
        }
        return archivedPaymentAttachment.amount ?? OWSLocalizedString(
            "PAYMENTS_INFO_UNAVAILABLE_MESSAGE",
            comment: "Status indicator for invalid payments which could not be processed."
        )
    }

    private var amountUnitText: String {
        // The "sats" suffix only matches the value when it came from the picoMob receipt.
        // The fallback string is in BTC display units, so force "BTC".
        let useSats = archivedPaymentAttachment.recoveredAmountPicoMob != nil
            && PaymentsDisplayPreferences.shared.isSatoshiEnabled
        return " " + (useSats ? "sats" : "BTC")
    }

    private var badgeText: String {
        switch itemModel.interaction.interactionType {
        case .incomingMessage:
            return OWSLocalizedString(
                "PAYMENTS_PAYMENT_STATUS_RECEIVED",
                comment: "Badge label shown on received payment bubbles in chat"
            )
        default:
            if messageStatus == .failed {
                return OWSLocalizedString(
                    "PAYMENTS_PAYMENT_STATUS_FAILED",
                    comment: "Badge label shown on failed payment bubbles in chat"
                )
            }
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

        // Amount — archived payments are always complete; never dim based on message sending state
        let amountAlpha: CGFloat = messageStatus == .failed ? 0.5 : 1
        componentView.amountNumberLabel.text = amountNumberText
        componentView.amountNumberLabel.textColor = textColor
        componentView.amountNumberLabel.alpha = amountAlpha
        componentView.amountUnitLabel.text = amountUnitText
        componentView.amountUnitLabel.textColor = dimTextColor
        componentView.amountUnitLabel.alpha = amountAlpha

        // Fiat label (hidden — no fiat data available for archived payments yet)
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
        return Self.measurePaymentBubble(
            noteText: noteText,
            badgeText: badgeText,
            amountNumberText: amountNumberText,
            amountUnitText: amountUnitText,
            maxWidth: maxWidth
        )
    }

    static func measurePaymentBubble(
        noteText: String?,
        badgeText: String,
        amountNumberText: String,
        amountUnitText: String,
        maxWidth: CGFloat
    ) -> CGSize {
        let outerPadding: CGFloat = 12
        let itemSpacing: CGFloat = 4
        let footerRowHeight: CGFloat = 16

        let badgeFont = UIFont.systemFont(ofSize: 12)
        let badgeHeight = max(22, ceil(badgeFont.lineHeight) + 6)

        let amountFont = UIFont.systemFont(ofSize: 28, weight: .medium)
        let amountHeight = ceil(amountFont.lineHeight)

        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Badge pill: icon(16) + spacing(2) + label + pill h-padding(8+8) + bubble h-padding
        let badgeLabelWidth = ceil((badgeText as NSString).boundingRect(
            with: unbounded,
            options: .usesLineFragmentOrigin,
            attributes: [.font: badgeFont],
            context: nil
        ).width)
        let badgeTotalWidth = outerPadding + 8 + 16 + 2 + badgeLabelWidth + 8 + outerPadding

        // Amount row: number + spacing(2) + unit + bubble h-padding
        let amountNumberWidth = ceil((amountNumberText as NSString).boundingRect(
            with: unbounded,
            options: .usesLineFragmentOrigin,
            attributes: [.font: amountFont],
            context: nil
        ).width)
        let amountUnitWidth = ceil((amountUnitText as NSString).boundingRect(
            with: unbounded,
            options: .usesLineFragmentOrigin,
            attributes: [.font: amountFont],
            context: nil
        ).width)
        let amountTotalWidth = outerPadding + amountNumberWidth + 2 + amountUnitWidth + outerPadding

        var naturalWidth = max(badgeTotalWidth, amountTotalWidth)

        // Note text may widen the bubble (capped at maxWidth)
        if let note = noteText, !note.isEmpty {
            let noteFont = UIFont.systemFont(ofSize: 16)
            let noteOneLine = (note as NSString).boundingRect(
                with: unbounded,
                options: .usesLineFragmentOrigin,
                attributes: [.font: noteFont],
                context: nil
            )
            let noteLineWidth = outerPadding + ceil(noteOneLine.width) + outerPadding
            naturalWidth = max(naturalWidth, min(noteLineWidth, maxWidth))
        }

        let constrainedWidth = min(maxWidth, max(naturalWidth, 120))

        let hasNote = noteText?.isEmpty == false

        let topSectionHeight: CGFloat
        if hasNote {
            topSectionHeight = outerPadding + badgeHeight + itemSpacing + amountHeight + outerPadding
        } else {
            topSectionHeight = outerPadding + badgeHeight + itemSpacing + amountHeight + itemSpacing + footerRowHeight + outerPadding
        }

        var noteSectionHeight: CGFloat = 0
        if let note = noteText, !note.isEmpty {
            let noteFont = UIFont.systemFont(ofSize: 16)
            let noteMaxWidth = constrainedWidth - outerPadding * 2
            let noteRect = (note as NSString).boundingRect(
                with: CGSize(width: max(1, noteMaxWidth), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: noteFont],
                context: nil
            )
            noteSectionHeight = outerPadding + ceil(noteRect.height) + itemSpacing + footerRowHeight + outerPadding
        }

        return CGSize(width: constrainedWidth, height: topSectionHeight + noteSectionHeight)
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

            let badgePillHeightConstraint = badgePillView.heightAnchor.constraint(greaterThanOrEqualToConstant: 22)
            badgePillHeightConstraint.isActive = true

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
            // Re-arrange: spacer first, then timestamp, then icon
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
