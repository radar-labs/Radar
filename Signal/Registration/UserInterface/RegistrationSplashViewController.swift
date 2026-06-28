//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
public import SignalUI

// MARK: - RegistrationSplashPresenter

public protocol RegistrationSplashPresenter: AnyObject {
    func continueFromSplash()
    func setHasOldDevice(_ hasOldDevice: Bool)

    func switchToDeviceLinkingMode()
    func transferDevice()
    func showRelinking()
}

// MARK: - RegistrationSplashViewController

public class RegistrationSplashViewController: OWSViewController, OWSNavigationChildController {

    public var prefersNavigationBarHidden: Bool {
        true
    }

    private weak var presenter: RegistrationSplashPresenter?

    public init(presenter: RegistrationSplashPresenter) {
        self.presenter = presenter
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        // Buttons in the top right corner.
        let canSwitchModes = UIDevice.current.isIPad
        var transferButtonTrailingAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> = contentLayoutGuide.trailingAnchor
        if canSwitchModes {
            let modeSwitchButton = UIButton(
                configuration: .plain(),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapModeSwitch()
                }
            )
            modeSwitchButton.configuration?.image = .init(named: UIDevice.current.isIPad ? "link" : "link-slash")
            modeSwitchButton.tintColor = .ows_gray25
            modeSwitchButton.accessibilityIdentifier = "registration.splash.modeSwitch"

            view.addSubview(modeSwitchButton)
            modeSwitchButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                modeSwitchButton.widthAnchor.constraint(equalToConstant: 40),
                modeSwitchButton.heightAnchor.constraint(equalToConstant: 40),
                modeSwitchButton.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
                modeSwitchButton.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            ])

            transferButtonTrailingAnchor = modeSwitchButton.leadingAnchor
        }

        if BuildFlags.preRegDeviceTransfer {
            let transferButton = UIButton(
                configuration: .plain(),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapTransfer()
                }
            )
            transferButton.configuration?.image = Theme.iconImage(.transfer).resizedImage(to: .square(24))
            transferButton.accessibilityIdentifier = "registration.splash.transfer"

            view.addSubview(transferButton)
            transferButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                transferButton.widthAnchor.constraint(equalToConstant: 40),
                transferButton.heightAnchor.constraint(equalToConstant: 40),
                transferButton.trailingAnchor.constraint(equalTo: transferButtonTrailingAnchor),
                transferButton.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            ])
        }

        // App icon at the top.
        let iconSize: CGFloat = 160
        let appIconView = UIImageView(image: UIImage(named: "AppIconPreview/default"))
        appIconView.contentMode = .scaleAspectFit
        appIconView.layer.cornerRadius = iconSize * 53.125 / 200
        appIconView.layer.masksToBounds = true
        appIconView.accessibilityIdentifier = "registration.splash.heroImageView"
        appIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            appIconView.widthAnchor.constraint(equalToConstant: iconSize),
            appIconView.heightAnchor.constraint(equalToConstant: iconSize),
        ])

        // "Radar." wordmark below icon.
        let wordmarkView = UILabel()
        wordmarkView.text = "Radar."
        // Match the orange of the app icon (#F46300).
        wordmarkView.textColor = UIColor(red: 244 / 255, green: 99 / 255, blue: 0 / 255, alpha: 1)
        wordmarkView.font = UIFont.systemFont(ofSize: 48, weight: .bold)
        wordmarkView.textAlignment = .center
        wordmarkView.accessibilityIdentifier = "registration.splash.wordmark"

        let iconStack = UIStackView(arrangedSubviews: [appIconView, wordmarkView])
        iconStack.axis = .vertical
        iconStack.alignment = .center
        iconStack.spacing = 18

        // Fixed top spacer gives the icon breathing room below the status bar.
        let topSpacer = UIView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topSpacer.heightAnchor.constraint(equalToConstant: 40),
        ])

        // Flexible spacer absorbs all remaining vertical space between the ToS link
        // and the bottom buttons, keeping the buttons anchored at the bottom.
        let bottomSpacer = UIView()
        bottomSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)

        // Welcome text.
        let titleText = {
            if TSConstants.isUsingProductionService {
                return OWSLocalizedString(
                    "ONBOARDING_SPLASH_TITLE",
                    comment: "Title of the 'onboarding splash' view."
                )
            } else {
                return "Internal Staging Build\n\(AppVersionImpl.shared.currentAppVersion)"
            }
        }()
        let titleLabel = UILabel.titleLabelForRegistration(text: titleText)
        titleLabel.accessibilityIdentifier = "registration.splash.titleLabel"

        // Terms of service and privacy policy.
        let tosPPButton = UIButton(
            configuration: .smallBorderless(title: OWSLocalizedString(
                "ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
                comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view."
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.showTOSPP()
            }
        )
        tosPPButton.configuration?.baseForegroundColor = .Signal.secondaryLabel
        tosPPButton.enableMultilineLabel()
        tosPPButton.accessibilityIdentifier = "registration.splash.explanationLabel"

        // Large buttons enclosed in a container with some extra horizontal padding.
        let continueButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "ONBOARDING_SPLASH_NEW_TO_SIGNAL_BUTTON_TITLE",
                comment: "Primary button on the 'onboarding splash' view for users who are new to the app."
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.continuePressed()
            }
        )
        continueButton.enableMultilineLabel()
        continueButton.accessibilityIdentifier = "registration.splash.continueButton"

        let largeButtonsContainer: UIView
        if BuildFlags.Backups.registrationFlow {
            let restoreOrTransferButton = UIButton(
                configuration: .largeSecondary(title: OWSLocalizedString(
                    "ONBOARDING_SPLASH_RESTORE_OR_TRANSFER_BUTTON_TITLE",
                    comment: "Button for restoring or transferring account in the 'onboarding splash' view."
                )),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapRestoreOrTransfer()
                }
            )
            restoreOrTransferButton.enableMultilineLabel()
            restoreOrTransferButton.accessibilityIdentifier = "registration.splash.continueButton"

            largeButtonsContainer = UIStackView.verticalButtonStack(buttons: [ continueButton, restoreOrTransferButton ])
        } else {
            largeButtonsContainer = UIStackView.verticalButtonStack(buttons: [ continueButton ])
        }

        // Main content view.
        let stackView = addStaticContentStackView(arrangedSubviews: [
            topSpacer,
            iconStack,
            titleLabel,
            tosPPButton,
            bottomSpacer,
            largeButtonsContainer,
        ])
        stackView.setCustomSpacing(32, after: topSpacer)
        stackView.setCustomSpacing(32, after: iconStack)
        stackView.setCustomSpacing(12, after: titleLabel)
        stackView.setCustomSpacing(0, after: tosPPButton)

        view.sendSubviewToBack(stackView)
    }

    // MARK: - Events

    private func didTapModeSwitch() {
        Logger.info("")
        presenter?.switchToDeviceLinkingMode()
    }

    private func didTapTransfer() {
        Logger.info("")
        presenter?.transferDevice()
    }

    private func showTOSPP() {
        let safariVC = SFSafariViewController(url: TSConstants.legalTermsUrl)
        present(safariVC, animated: true)
    }

    private func continuePressed() {
        Logger.info("")
        guard let presenter else { return }
        let signUpVC = RegistrationSignUpViewController(presenter: presenter)
        navigationController?.pushViewController(signUpVC, animated: true)
    }

    private func didTapRestoreOrTransfer() {
        Logger.info("")
        let sheet = RestoreOrTransferPickerController(
            setHasOldDeviceBlock: { [weak self] hasOldDevice in
                self?.dismiss(animated: true) {
                    self?.presenter?.setHasOldDevice(hasOldDevice)
                }
            }, showRelinkingBlock: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.presenter?.showRelinking()
                }
            }
        )
        self.present(sheet, animated: true)
    }
}

class RestoreOrTransferPickerController: StackSheetViewController {

    override var placeOnGlassIfAvailable: Bool { false }

    private let setHasOldDeviceBlock: ((Bool) -> Void)
    private let showRelinkingBlock: (() -> Void)
    init(setHasOldDeviceBlock: @escaping (Bool) -> Void, showRelinkingBlock: @escaping () -> Void) {
        self.setHasOldDeviceBlock = setHasOldDeviceBlock
        self.showRelinkingBlock = showRelinkingBlock
        super.init()
    }

    open override var sheetBackgroundColor: UIColor { .Signal.secondaryBackground }

    override func viewDidLoad() {
        super.viewDidLoad()
        stackView.spacing = 16
        
        if BuildFlags.linkedPhones {
            let linkIphoneButton = UIButton.registrationChoiceButton(
                title: "Link your device",
                subtitle: "Scan QR code for link this device to your account.",
                iconName: "qr-code-48",
                primaryAction: UIAction { [weak self] _ in
                    self?.showRelinkingBlock()
                }
            )
            stackView.addArrangedSubview(linkIphoneButton)
        }

        let hasDeviceButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_HAVE_OLD_DEVICE_TITLE",
                comment: "Title for the 'have my old device' choice of the 'Restore or Transfer' prompt"
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_SPLASH_HAVE_OLD_DEVICE_BODY",
                comment: "Explanation of 'have old device' flow for the 'Restore or Transfer' prompt"
            ),
            iconName: "qr-code-48",
            primaryAction: UIAction { [weak self] _ in
                self?.setHasOldDeviceBlock(true)
            }
        )
        stackView.addArrangedSubview(hasDeviceButton)

        let noDeviceButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_DO_NOT_HAVE_OLD_DEVICE_TITLE",
                comment: "Title for the 'do not have my old device' choice of the 'Restore or Transfer' prompt"
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_SPLASH_DO_NOT_HAVE_OLD_DEVICE_BODY",
                comment: "Explanation of 'do not have old device' flow for the 'Restore or Transfer' prompt"
            ),
            iconName: "no-phone-48",
            primaryAction: UIAction { [weak self] _ in
                self?.setHasOldDeviceBlock(false)
            }
        )
        stackView.addArrangedSubview(noDeviceButton)
    }
}

// MARK: -

#if DEBUG
private class PreviewRegistrationSplashPresenter: RegistrationSplashPresenter {
    func continueFromSplash() {
        print("continueFromSplash")
    }

    func setHasOldDevice(_ hasOldDevice: Bool) {
        print("setHasOldDevice: \(hasOldDevice)")
    }

    func switchToDeviceLinkingMode() {
        print("switchToDeviceLinkingMode")
    }

    func transferDevice() {
        print("transferDevice")
    }
    
    func showRelinking() {
        print("showRelinking")
    }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationSplashPresenter()
    return RegistrationSplashViewController(presenter: presenter)
}
#endif
