//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

final class ContactShareAvatarPickerSheet: SheetNavigationController {
    init(
        options: [ContactShareAvatarOption],
        initialsImage: UIImage?,
        selectedSource: ContactShareAvatarOption.Source?,
        didConfirm: @escaping (ContactShareAvatarOption.Source?) -> Void,
    ) {
        super.init(rootViewController: ContactShareAvatarPickerViewController(
            options: options,
            initialsImage: initialsImage,
            selectedSource: selectedSource,
            didConfirm: didConfirm,
        ))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - ContactShareAvatarPickerViewController

private final class ContactShareAvatarPickerViewController: NavStackSheetViewController {

    static let avatarDiameter: CGFloat = 96
    private static let minimumSheetHeight: CGFloat = 300

    private let options: [ContactShareAvatarOption]
    private let initialsImage: UIImage?
    private var selectedSource: ContactShareAvatarOption.Source?
    private let didConfirm: (ContactShareAvatarOption.Source?) -> Void

    private var avatarButtons = [AvatarButton]()

    init(
        options: [ContactShareAvatarOption],
        initialsImage: UIImage?,
        selectedSource: ContactShareAvatarOption.Source?,
        didConfirm: @escaping (ContactShareAvatarOption.Source?) -> Void,
    ) {
        self.options = options
        self.initialsImage = initialsImage
        self.selectedSource = selectedSource
        self.didConfirm = didConfirm
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var stackViewInsets: UIEdgeInsets {
        .init(top: 38, leading: 16, bottom: 0, trailing: 16)
    }

    override var minimumBottomInsetIncludingSafeArea: CGFloat { 32 }

    override func customSheetHeight() -> CGFloat {
        max(super.customSheetHeight(), Self.minimumSheetHeight - view.safeAreaInsets.bottom)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "CONTACT_SHARE_AVATAR_PICKER_TITLE",
            comment: "Title for the sheet for choosing which photo to include when sharing a contact.",
        )
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .dynamicTypeSubheadlineClamped
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .Signal.secondaryLabel
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        navigationItem.titleView = titleLabel
        navigationItem.leftBarButtonItem = .closeButton { [weak self] in
            self?.dismiss(animated: true)
        }
        let confirmButton = UIBarButtonItem.button(icon: .checkmark, isProminent: true) { [weak self] in
            self?.confirm()
        }
        confirmButton.accessibilityLabel = CommonStrings.doneButton
        navigationItem.rightBarButtonItem = confirmButton

        stackView.alignment = .center

        avatarButtons = options.map { makeAvatarButton(image: $0.image, source: $0.source) }
        avatarButtons.append(makeAvatarButton(image: initialsImage, source: nil))

        let avatarStack = UIStackView(arrangedSubviews: avatarButtons)
        avatarStack.axis = .horizontal
        avatarStack.spacing = 16
        avatarStack.distribution = .fillEqually
        stackView.addArrangedSubview(avatarStack)

        updateSelection()
    }

    private func makeAvatarButton(image: UIImage?, source: ContactShareAvatarOption.Source?) -> AvatarButton {
        let button = AvatarButton(image: image, source: source)
        button.accessibilityLabel = ContactShareAvatarOption.localizedVoiceOverName(source: source)
        button.addAction(
            UIAction { [weak self] _ in
                self?.selectedSource = source
                self?.updateSelection()
            },
            for: .touchUpInside,
        )
        return button
    }

    private func updateSelection() {
        for button in avatarButtons {
            button.isSelected = button.source == selectedSource
        }
    }

    private func confirm() {
        let selectedSource = self.selectedSource
        dismiss(animated: true) { [didConfirm] in
            didConfirm(selectedSource)
        }
    }

    // MARK: - AvatarButton

    private final class AvatarButton: UIControl {

        let source: ContactShareAvatarOption.Source?

        private let selectionIndicator = SelectionIndicatorView(style: .media)

        init(image: UIImage?, source: ContactShareAvatarOption.Source?) {
            self.source = source

            super.init(frame: .zero)

            let avatarView = AvatarImageView()
            avatarView.image = image
            avatarView.isUserInteractionEnabled = false
            addSubview(avatarView)
            avatarView.autoPinEdgesToSuperviewEdges()
            avatarView.autoPinToSquareAspectRatio()
            avatarView.autoSetDimension(
                .width,
                toSize: ContactShareAvatarPickerViewController.avatarDiameter,
                relation: .lessThanOrEqual,
            )
            NSLayoutConstraint.autoSetPriority(.defaultHigh) {
                avatarView.autoSetDimension(.width, toSize: ContactShareAvatarPickerViewController.avatarDiameter)
            }

            selectionIndicator.isUserInteractionEnabled = false
            addSubview(selectionIndicator)
            selectionIndicator.autoPinEdge(toSuperviewEdge: .trailing)
            selectionIndicator.autoPinEdge(toSuperviewEdge: .bottom)

            isAccessibilityElement = true
            accessibilityTraits = .button
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var isHighlighted: Bool {
            didSet {
                alpha = isHighlighted ? 0.5 : 1
            }
        }

        override var isSelected: Bool {
            didSet {
                selectionIndicator.isSelected = isSelected
                selectionIndicator.isHidden = !isSelected
                if isSelected {
                    accessibilityTraits.insert(.selected)
                } else {
                    accessibilityTraits.remove(.selected)
                }
            }
        }
    }
}
