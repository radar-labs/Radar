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

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        // Buttons in the top right corner.
        var transferButtonTrailingAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> = contentLayoutGuide.trailingAnchor
        if !RegistrationUtils.isPrimaryByDefault {
            let modeSwitchButton = UIButton(
                configuration: .plain(),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapModeSwitch()
                },
            )
            modeSwitchButton.configuration?.image = .link
            modeSwitchButton.tintColor = .ows_gray25

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

        // Radar: keep the device transfer button. Upstream removed it together
        // with its legacy QR screen (d6ac807f06); it now opens the current
        // transfer flow, the same as "I already have an account" → "Set up my
        // new phone": this phone shows a QR code that the old phone scans.
        let transferButton = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapTransfer()
            },
        )
        transferButton.configuration?.image = Theme.iconImage(.transfer).resized(maxDimensionPoints: 24)
        transferButton.accessibilityIdentifier = "registration.splash.transfer"
        transferButton.accessibilityLabel = OWSLocalizedString(
            "ONBOARDING_SPLASH_SET_UP_NEW_PHONE_TITLE",
            comment: "Title for the 'set up my new phone' choice of the 'Restore or Transfer' prompt",
        )

        view.addSubview(transferButton)
        transferButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            transferButton.widthAnchor.constraint(equalToConstant: 40),
            transferButton.heightAnchor.constraint(equalToConstant: 40),
            transferButton.trailingAnchor.constraint(equalTo: transferButtonTrailingAnchor),
            transferButton.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
        ])

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
                    comment: "Title of the 'onboarding splash' view.",
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
                comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.showTOSPP()
            },
        )
        tosPPButton.configuration?.baseForegroundColor = .Signal.secondaryLabel
        tosPPButton.enableMultilineLabel()
        tosPPButton.accessibilityIdentifier = "registration.splash.explanationLabel"

        // Large buttons enclosed in a container with some extra horizontal padding.
        let continueButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "ONBOARDING_SPLASH_NEW_TO_SIGNAL_BUTTON_TITLE",
                comment: "Primary button on the 'onboarding splash' view for users who are new to the app.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.continuePressed()
            },
        )
        continueButton.enableMultilineLabel()
        continueButton.accessibilityIdentifier = "registration.splash.continueButton"

        let restoreOrTransferButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "ONBOARDING_SPLASH_RESTORE_OR_TRANSFER_BUTTON_TITLE",
                comment: "Button for restoring or transferring account in the 'onboarding splash' view.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapRestoreOrTransfer()
            },
        )
        restoreOrTransferButton.enableMultilineLabel()
        restoreOrTransferButton.accessibilityIdentifier = "registration.splash.continueButton"

        let largeButtonsContainer = UIStackView.verticalButtonStack(buttons: [continueButton, restoreOrTransferButton])

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
        presenter?.setHasOldDevice(true)
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
                    if hasOldDevice {
                        self?.presenter?.setHasOldDevice(true)
                    } else {
                        self?.showMigrateFromSignalBackupDisclaimer()
                    }
                }
            },
            showRelinkingBlock: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.presenter?.showRelinking()
                }
            },
        )
        self.present(sheet, animated: true)
    }

    private func showMigrateFromSignalBackupDisclaimer() {
        let disclaimer = MigrateFromSignalBackupDisclaimerViewController(
            completedBackupBlock: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.presenter?.setHasOldDevice(false)
                }
            },
        )
        present(disclaimer, animated: true)
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

    override open var sheetBackgroundColor: UIColor { .Signal.secondaryBackground }

    override func viewDidLoad() {
        super.viewDidLoad()
        stackView.spacing = 16

        let migrateFromSignalButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_MIGRATE_FROM_SIGNAL_TITLE",
                comment: "Title for the 'migrate from Signal' choice of the 'Restore or Transfer' prompt",
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_SPLASH_MIGRATE_FROM_SIGNAL_BODY",
                comment: "Explanation of the 'migrate from Signal' flow for the 'Restore or Transfer' prompt",
            ),
            iconName: "signal-app-48",
            iconRenderingMode: .alwaysOriginal,
            primaryAction: UIAction { [weak self] _ in
                self?.setHasOldDeviceBlock(false)
            },
        )
        stackView.addArrangedSubview(migrateFromSignalButton)

        let hasDeviceButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_SET_UP_NEW_PHONE_TITLE",
                comment: "Title for the 'set up my new phone' choice of the 'Restore or Transfer' prompt",
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_SPLASH_SET_UP_NEW_PHONE_BODY",
                comment: "Explanation of the 'set up my new phone' flow for the 'Restore or Transfer' prompt",
            ),
            iconName: "transfer-phone-48",
            primaryAction: UIAction { [weak self] _ in
                self?.setHasOldDeviceBlock(true)
            },
        )
        stackView.addArrangedSubview(hasDeviceButton)

        let linkDeviceButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "ONBOARDING_SPLASH_LINK_DEVICE_TITLE",
                comment: "Title for the 'link device' choice of the 'Restore or Transfer' prompt",
            ),
            subtitle: OWSLocalizedString(
                "ONBOARDING_SPLASH_LINK_DEVICE_BODY",
                comment: "Explanation of the 'link device' flow for the 'Restore or Transfer' prompt",
            ),
            iconName: "link-48",
            primaryAction: UIAction { [weak self] _ in
                self?.showRelinkingBlock()
            },
        )
        stackView.addArrangedSubview(linkDeviceButton)
    }
}

// MARK: - MigrateFromSignalBackupDisclaimerViewController

class MigrateFromSignalBackupDisclaimerViewController: OWSViewController {

    private let completedBackupBlock: () -> Void

    init(completedBackupBlock: @escaping () -> Void) {
        self.completedBackupBlock = completedBackupBlock
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let iconsView = UIImageView(image: UIImage(named: "migrate-from-signal-icons"))
        iconsView.contentMode = .scaleAspectFit
        iconsView.accessibilityIdentifier = "registration.migrateFromSignalBackup.iconsView"

        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "MIGRATE_FROM_SIGNAL_BACKUP_TITLE",
            comment: "Title of the view asking the user to back up their Signal conversations before migrating from Signal.",
        ))
        titleLabel.accessibilityIdentifier = "registration.migrateFromSignalBackup.titleLabel"

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "MIGRATE_FROM_SIGNAL_BACKUP_SUBTITLE",
            comment: "Subtitle of the view asking the user to back up their Signal conversations before migrating from Signal.",
        )
        subtitleLabel.textColor = .Signal.accent
        subtitleLabel.font = UIFont.dynamicTypeTitle3Clamped.medium()
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping

        let stepsStack = UIStackView(arrangedSubviews: [
            Self.stepLabel(number: 1, text: OWSLocalizedString(
                "MIGRATE_FROM_SIGNAL_BACKUP_STEP_1",
                comment: "First step of the view asking the user to back up their Signal conversations before migrating from Signal.",
            )),
            Self.stepLabel(number: 2, text: OWSLocalizedString(
                "MIGRATE_FROM_SIGNAL_BACKUP_STEP_2",
                comment: "Second step of the view asking the user to back up their Signal conversations before migrating from Signal.",
            )),
        ])
        stepsStack.axis = .vertical

        let completedBackupButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "MIGRATE_FROM_SIGNAL_BACKUP_COMPLETED_BUTTON",
                comment: "Button confirming that the user has completed a Signal backup, on the view asking them to back up their Signal conversations before migrating from Signal.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCompletedBackup()
            },
        )
        completedBackupButton.enableMultilineLabel()
        completedBackupButton.accessibilityIdentifier = "registration.migrateFromSignalBackup.completedBackupButton"

        // Flexible spacers of equal height center the content vertically
        // between the top of the view and the bottom button.
        let topSpacer = UIView()
        topSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        let bottomSpacer = UIView()
        bottomSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)

        let stackView = addStaticContentStackView(arrangedSubviews: [
            topSpacer,
            iconsView,
            titleLabel,
            subtitleLabel,
            stepsStack,
            bottomSpacer,
            UIStackView.verticalButtonStack(buttons: [completedBackupButton], isFullWidthButtons: false),
        ])
        stackView.alignment = .center
        stackView.setCustomSpacing(48, after: iconsView)
        stackView.setCustomSpacing(32, after: titleLabel)
        stackView.setCustomSpacing(32, after: subtitleLabel)

        let subtitleWidthConstraint = subtitleLabel.widthAnchor.constraint(equalToConstant: 308)
        subtitleWidthConstraint.priority = .defaultHigh
        let stepsWidthConstraint = stepsStack.widthAnchor.constraint(equalToConstant: 308)
        stepsWidthConstraint.priority = .defaultHigh
        let buttonWidthConstraint = completedBackupButton.widthAnchor.constraint(equalToConstant: 288)
        buttonWidthConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            iconsView.heightAnchor.constraint(equalToConstant: 75),
            topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: stackView.widthAnchor),
            subtitleWidthConstraint,
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualTo: stackView.widthAnchor),
            stepsWidthConstraint,
            stepsStack.widthAnchor.constraint(lessThanOrEqualTo: stackView.widthAnchor),
            buttonWidthConstraint,
            completedBackupButton.widthAnchor.constraint(lessThanOrEqualTo: stackView.widthAnchor),
        ])
    }

    private static func stepLabel(number: Int, text: String) -> UILabel {
        let markerColumnWidth: CGFloat = 26
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .natural, location: markerColumnWidth)]
        paragraphStyle.defaultTabInterval = markerColumnWidth
        paragraphStyle.headIndent = markerColumnWidth

        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: "\(number).\t\(text)",
            attributes: [
                .font: UIFont.dynamicTypeBodyClamped.medium(),
                .foregroundColor: UIColor { traitCollection in
                    UIColor(white: traitCollection.userInterfaceStyle == .dark ? 1 : 0, alpha: 0.5)
                },
                .paragraphStyle: paragraphStyle,
            ],
        )
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    // MARK: - Events

    private func didTapCompletedBackup() {
        Logger.info("")
        completedBackupBlock()
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
