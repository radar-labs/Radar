//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - RegistrationTwoFactorAuthPresenter

/// Shared by every screen in the two-factor authentication flow.
protocol RegistrationTwoFactorAuthPresenter: AnyObject {
    func cancelTwoFactorAuth()
}

// MARK: - RegistrationTwoFactorAuthMethodPresenter

protocol RegistrationTwoFactorAuthMethodPresenter: RegistrationTwoFactorAuthPresenter {
    func didChooseTwoFactorAuthMethod(_ method: RegistrationTwoFactorAuthMethod)
}

// MARK: - RegistrationTwoFactorAuthMethod

enum RegistrationTwoFactorAuthMethod: CaseIterable {
    case passkey
    case authenticatorApp
}

// MARK: - RegistrationTwoFactorAuthMethodViewController

class RegistrationTwoFactorAuthMethodViewController: OWSViewController {

    private enum Constants {
        static let stackEdgeInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: 18,
            bottom: 10,
            trailing: 18,
        )
        static let sectionSpacing: CGFloat = 16
        static let bodyLabelMargins: CGFloat = 20
    }

    private weak var presenter: RegistrationTwoFactorAuthMethodPresenter?

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
                "ONBOARDING_TWO_FACTOR_AUTH_METHOD_BODY",
                comment: "Description for the 2fa screens shown during registration.",
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

    init(presenter: RegistrationTwoFactorAuthMethodPresenter) {
        self.presenter = presenter
        super.init()
        navigationItem.hidesBackButton = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        // Title
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(8, after: titleLabel)

        // Body
        stackView.addArrangedSubview(bodyLabel)
        stackView.setCustomSpacing(24, after: bodyLabel)

        // Method choices
        for method in RegistrationTwoFactorAuthMethod.allCases {
            stackView.addArrangedSubview(choiceButton(for: method))
        }

        // Spacer.
        let spacer = SpacerView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        stackView.addArrangedSubview(spacer)

        // Cancel Button
        let cancelButton = UIButton(
            configuration: .mediumSecondary(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.presenter?.cancelTwoFactorAuth()
            },
        )
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let cancelButtonContainer = UIView.transparentContainer()
        cancelButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        cancelButtonContainer.addSubview(cancelButton)
        stackView.addArrangedSubview(cancelButtonContainer)
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: cancelButtonContainer.topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: cancelButtonContainer.bottomAnchor),
            cancelButton.centerXAnchor.constraint(equalTo: cancelButtonContainer.centerXAnchor),
            cancelButton.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButtonContainer.leadingAnchor),
            cancelButton.trailingAnchor.constraint(lessThanOrEqualTo: cancelButtonContainer.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    private func choiceButton(for method: RegistrationTwoFactorAuthMethod) -> UIButton {
        switch method {
        case .passkey:
            return UIButton.registrationChoiceButton(
                title: OWSLocalizedString(
                    "ONBOARDING_TWO_FACTOR_AUTH_METHOD_PASSKEY_TITLE",
                    comment: "Title for action to verify with a passkey as a 2fa method.",
                ),
                subtitle: OWSLocalizedString(
                    "ONBOARDING_TWO_FACTOR_AUTH_METHOD_PASSKEY_BODY",
                    comment: "Subtitle for action to verify with a passkey as a 2fa method.",
                ),
                iconName: "person-key",
                imageSize: 36.0,
                primaryAction: UIAction { [weak self] _ in
                    self?.presenter?.didChooseTwoFactorAuthMethod(.passkey)
                },
            )
        case .authenticatorApp:
            return UIButton.registrationChoiceButton(
                title: OWSLocalizedString(
                    "ONBOARDING_TWO_FACTOR_AUTH_METHOD_AUTHENTICATOR_APP_TITLE",
                    comment: "Title for action to verify with an authenticator as a 2fa method.",
                ),
                subtitle: OWSLocalizedString(
                    "ONBOARDING_TWO_FACTOR_AUTH_METHOD_AUTHENTICATOR_APP_BODY",
                    comment: "Subtitle for action to verify with an authenticator as a 2fa method.",
                ),
                iconName: "device-phone",
                imageSize: 36.0,
                primaryAction: UIAction { [weak self] _ in
                    self?.presenter?.didChooseTwoFactorAuthMethod(.authenticatorApp)
                },
            )
        }
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationTwoFactorAuthMethodPresenter: RegistrationTwoFactorAuthMethodPresenter {
    func didChooseTwoFactorAuthMethod(_ method: RegistrationTwoFactorAuthMethod) {
        print("method: \(method)")
    }

    func cancelTwoFactorAuth() { }
}

@available(iOS 17, *)
#Preview("All Methods") {
    let presenter = PreviewRegistrationTwoFactorAuthMethodPresenter()
    return UINavigationController(
        rootViewController: RegistrationTwoFactorAuthMethodViewController(presenter: presenter),
    )
}

#endif
