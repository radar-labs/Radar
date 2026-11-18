//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - RegistrationTwoFactorPasskeyPresenter

protocol RegistrationTwoFactorPasskeyPresenter: RegistrationTwoFactorAuthPresenter {
    func continueWithPasskey()
}

// MARK: - RegistrationTwoFactorPasskeyViewController

class RegistrationTwoFactorPasskeyViewController: OWSViewController {

    private enum Constants {
        static let stackEdgeInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 10, trailing: 18)
        static let sectionSpacing: CGFloat = 8
        static let bodyLabelMargins: CGFloat = 20
    }

    private weak var presenter: RegistrationTwoFactorPasskeyPresenter?

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.directionalLayoutMargins = Constants.stackEdgeInsets
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = Constants.sectionSpacing
        return stackView
    }()

    private lazy var titleImageView: UIImageView = {
        let titleImageView = UIImageView(image: .twoFactorPasskey)
        titleImageView.translatesAutoresizingMaskIntoConstraints = false
        titleImageView.contentMode = .center
        return titleImageView
    }()

    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_TWO_FACTOR_AUTH_TITLE",
                comment: "Title for the 2fa screens shown during registration.",
            ),
        )
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
    }()

    private lazy var bodyLabel: UIView = {
        let bodyLabel = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "ONBOARDING_TWO_FACTOR_AUTH_PASSKEY_BODY",
                comment: "Description for the screen asking the user to verify their account with a passkey during registration.",
            ),
        )
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        let bodyLabelContainer = UIView.transparentContainer()
        bodyLabelContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyLabelContainer.addSubview(bodyLabel)
        NSLayoutConstraint.activate([
            bodyLabel.topAnchor.constraint(equalTo: bodyLabelContainer.topAnchor),
            bodyLabel.bottomAnchor.constraint(equalTo: bodyLabelContainer.bottomAnchor),
            bodyLabel.centerXAnchor.constraint(equalTo: bodyLabelContainer.centerXAnchor),
            bodyLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: bodyLabelContainer.leadingAnchor,
                constant: Constants.bodyLabelMargins,
            ),
            bodyLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: bodyLabelContainer.trailingAnchor,
                constant: -Constants.bodyLabelMargins,
            ),
        ])
        return bodyLabelContainer
    }()

    init(presenter: RegistrationTwoFactorPasskeyPresenter) {
        self.presenter = presenter

        super.init()
        navigationItem.hidesBackButton = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        // Spacer.
        let spacer = SpacerView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)

        // Continue & Cancel Buttons
        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.continueButton),
            primaryAction: UIAction { [weak self] _ in
                self?.presenter?.continueWithPasskey()
            },
        )
        let cancelButton = UIButton(
            configuration: .largeSecondary(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.presenter?.cancelTwoFactorAuth()
            },
        )

        stackView.addArrangedSubviews([
            titleImageView,
            titleLabel,
            bodyLabel,
            spacer,
            [continueButton, cancelButton].enclosedInVerticalStackView(isFullWidthButtons: true),
        ])
        stackView.setCustomSpacing(16, after: titleImageView)
    }

    @available(*, unavailable)
    override init() {
        owsFail("Not implemented")
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationTwoFactorPasskeyPresenter: RegistrationTwoFactorPasskeyPresenter {
    func continueWithPasskey() {
        print("continueWithPasskey")
    }

    func cancelTwoFactorAuth() { }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationTwoFactorPasskeyPresenter()
    return UINavigationController(
        rootViewController: RegistrationTwoFactorPasskeyViewController(presenter: presenter),
    )
}

#endif
