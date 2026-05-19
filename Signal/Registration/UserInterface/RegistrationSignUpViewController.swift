//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

// MARK: - RegistrationSignUpViewController

public class RegistrationSignUpViewController: OWSViewController, OWSNavigationChildController {

    public var prefersNavigationBarHidden: Bool { false }

    private weak var presenter: RegistrationSplashPresenter?

    public init(presenter: RegistrationSplashPresenter) {
        self.presenter = presenter
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        // Centered person icon.
        let iconSymbolConfig = UIImage.SymbolConfiguration(pointSize: 92, weight: .regular)
        let iconImage = UIImage(systemName: "person.fill", withConfiguration: iconSymbolConfig)
        let iconView = UIImageView(image: iconImage)
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .Signal.accent
        iconView.accessibilityIdentifier = "registration.signUp.iconView"
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 100),
        ])

        // Title.
        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_SIGN_UP_TITLE",
            comment: "Title of the 'sign up' screen shown after the user taps 'I'm new to Radar' on the onboarding splash."
        ))
        titleLabel.accessibilityIdentifier = "registration.signUp.titleLabel"

        // Body — first paragraph in secondary label color.
        let subtitleLabel = UILabel.explanationLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_SIGN_UP_SUBTITLE",
            comment: "Subtitle on the 'sign up' screen shown after the user taps 'I'm new to Radar' on the onboarding splash."
        ))
        subtitleLabel.accessibilityIdentifier = "registration.signUp.subtitleLabel"

        // Body — second paragraph with the leading phrase highlighted in accent color.
        let signalInfoLabel = UILabel()
        signalInfoLabel.numberOfLines = 0
        signalInfoLabel.textAlignment = .center
        signalInfoLabel.lineBreakMode = .byWordWrapping
        signalInfoLabel.font = .dynamicTypeBodyClamped
        signalInfoLabel.attributedText = Self.makeSignalInfoAttributedString()
        signalInfoLabel.accessibilityIdentifier = "registration.signUp.signalInfoLabel"

        // Buttons.
        let createAccountButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "ONBOARDING_SIGN_UP_CREATE_ACCOUNT_BUTTON_TITLE",
                comment: "Primary button on the 'sign up' screen that begins the new account flow."
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCreateNewAccount()
            }
        )
        createAccountButton.enableMultilineLabel()
        createAccountButton.accessibilityIdentifier = "registration.signUp.createAccountButton"

        let useSignalAccountButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "ONBOARDING_SIGN_UP_USE_SIGNAL_ACCOUNT_BUTTON_TITLE",
                comment: "Secondary text button on the 'sign up' screen that begins the restore / use existing Signal account flow."
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapUseSignalAccount()
            }
        )
        useSignalAccountButton.enableMultilineLabel()
        useSignalAccountButton.accessibilityIdentifier = "registration.signUp.useSignalAccountButton"

        // Vertical spacers keep the icon + text vertically centered while the
        // buttons stay anchored near the bottom of the screen.
        let topSpacer = UIView()
        topSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        let bottomSpacer = UIView()
        bottomSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)

        let iconStack = UIStackView(arrangedSubviews: [iconView])
        iconStack.axis = .vertical
        iconStack.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, signalInfoLabel])
        textStack.axis = .vertical
        textStack.spacing = 20
        textStack.alignment = .fill

        let buttonsStack = UIStackView.verticalButtonStack(buttons: [createAccountButton, useSignalAccountButton])

        let stackView = addStaticContentStackView(arrangedSubviews: [
            topSpacer,
            iconStack,
            textStack,
            bottomSpacer,
            buttonsStack,
        ])
        // Equal-priority top/bottom spacers center the icon+text block vertically.
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor).isActive = true
        stackView.setCustomSpacing(32, after: iconStack)
        stackView.setCustomSpacing(0, after: textStack)
    }

    private static func makeSignalInfoAttributedString() -> NSAttributedString {
        let highlight = OWSLocalizedString(
            "ONBOARDING_SIGN_UP_SIGNAL_INFO_HIGHLIGHT",
            comment: "Highlighted leading phrase of the body text on the 'sign up' onboarding screen. Rendered in the app's accent color."
        )
        let body = OWSLocalizedString(
            "ONBOARDING_SIGN_UP_SIGNAL_INFO_BODY",
            comment: "Continuation of the body text on the 'sign up' onboarding screen. Begins with a leading space and follows the highlighted phrase."
        )

        let result = NSMutableAttributedString(
            string: highlight,
            attributes: [.foregroundColor: UIColor.Signal.accent]
        )
        result.append(NSAttributedString(
            string: body,
            attributes: [.foregroundColor: UIColor.Signal.secondaryLabel]
        ))
        return result
    }

    // MARK: - Events

    private func didTapCreateNewAccount() {
        Logger.info("")
        presenter?.continueFromSplash()
    }

    private func didTapUseSignalAccount() {
        Logger.info("")
        let sheet = RestoreOrTransferPickerController(
            setHasOldDeviceBlock: { [weak self] hasOldDevice in
                self?.dismiss(animated: true) {
                    self?.presenter?.setHasOldDevice(hasOldDevice)
                }
            },
            showRelinkingBlock: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.presenter?.showRelinking()
                }
            }
        )
        self.present(sheet, animated: true)
    }
}

// MARK: -

#if DEBUG
private class PreviewRegistrationSignUpPresenter: RegistrationSplashPresenter {
    func continueFromSplash() { print("continueFromSplash") }
    func setHasOldDevice(_ hasOldDevice: Bool) { print("setHasOldDevice: \(hasOldDevice)") }
    func switchToDeviceLinkingMode() { print("switchToDeviceLinkingMode") }
    func transferDevice() { print("transferDevice") }
    func showRelinking() { print("showRelinking") }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationSignUpPresenter()
    return RegistrationSignUpViewController(presenter: presenter)
}
#endif
