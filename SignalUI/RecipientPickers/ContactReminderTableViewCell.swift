//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class ContactReminderTableViewCell: UITableViewCell, CustomBackgroundColorCell {

    private let learnMoreAction: () -> Void
    private let dismissAction: () -> Void

    init(learnMoreAction: @escaping () -> Void, dismissAction: @escaping () -> Void) {
        self.learnMoreAction = learnMoreAction
        self.dismissAction = dismissAction

        super.init(style: .default, reuseIdentifier: nil)

        contentView.addSubview(contentContainer)
        contentContainer.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .dynamicTypeSubheadline
        label.textColor = .Signal.label
        label.text = OWSLocalizedString(
            "LINKED_DEVICE_MANAGE_CONTACTS_BANNER",
            comment: "Shown in a banner when you tap the 'New Chat' icon at the top of the list of chats.",
        )
        return label
    }()

    private lazy var learnMoreButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(
            OWSLocalizedString(
                "LINKED_DEVICE_MANAGE_CONTACTS_LEARN_MORE",
                comment: "A button shown in a banner when you tap the 'New Chat' icon at the top of the list of chats. Tapping it opens a website with more details.",
            ),
            for: .normal,
        )
        button.setTitleColor(.Signal.label, for: .normal)
        button.titleLabel!.font = .dynamicTypeSubheadline.semibold()
        button.addAction(
            UIAction { [weak self] _ in self?.didTapLearnMore() },
            for: .primaryActionTriggered,
        )
        button.ows_contentEdgeInsets = UIEdgeInsets(top: 6, left: 0, bottom: 3, right: 0)
        button.setCompressionResistanceHigh()
        return button
    }()

    private lazy var contactIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.setTemplateImageName("person-circle", tintColor: .Signal.label)
        imageView.autoSetDimensions(to: CGSize(square: 24))
        return imageView
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTemplateImageName("x-20", tintColor: .Signal.label)
        button.addAction(
            UIAction { [weak self] _ in self?.didTapDismiss() },
            for: .primaryActionTriggered,
        )
        button.setCompressionResistanceHigh()
        return button
    }()

    private lazy var labelContainer: UIView = {
        let stackView = UIStackView(arrangedSubviews: [messageLabel, learnMoreButton])
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        return stackView
    }()

    private lazy var contentContainer: UIView = {
        let stackView = UIStackView(arrangedSubviews: [contactIcon, labelContainer, closeButton])
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.spacing = 12
        return stackView
    }()

    private func didTapLearnMore() {
        learnMoreAction()
    }

    private func didTapDismiss() {
        dismissAction()
    }

    // MARK: - CustomBackgroundColorCell

    var customBackgroundColor: UIColor {
        UIColor.Signal.tertiaryBackground
    }

    var customSelectedBackgroundColor: UIColor {
        customBackgroundColor
    }
}
