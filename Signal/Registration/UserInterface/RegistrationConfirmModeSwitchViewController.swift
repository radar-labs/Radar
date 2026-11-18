//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol RegistrationConfimModeSwitchPresenter: AnyObject {
    func confirmSwitchToDeviceLinkingMode()
}

class RegistrationConfirmModeSwitchViewController: OWSViewController {
    weak var presenter: RegistrationConfimModeSwitchPresenter?

    init(presenter: RegistrationConfimModeSwitchPresenter) {
        self.presenter = presenter
        super.init()
    }

    private var titleText: String {
        OWSLocalizedString(
            "ONBOARDING_MODE_SWITCH_TITLE_REGISTERING",
            comment: "header text indicating to the user they're switching from registering to linking flow",
        )
    }

    private var subtitleText: String {
        OWSLocalizedString(
            "ONBOARDING_MODE_SWITCH_EXPLANATION_REGISTERING",
            comment: "explanation to the user they're switching from registering to linking flow",
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let titleLabel = UILabel.titleLabelForRegistration(text: titleText)
        let explanationLabel = UILabel.explanationLabelForRegistration(text: subtitleText)

        let nextButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "ONBOARDING_MODE_SWITCH_BUTTON_REGISTERING",
                comment: "button indicating that the user will link this device",
            )),
            primaryAction: UIAction { [weak presenter] _ in
                presenter?.confirmSwitchToDeviceLinkingMode()
            },
        )
        nextButton.accessibilityIdentifier = "onboarding.modeSwitch.nextButton"

        addStaticContentStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            .vStretchingSpacer(),
            nextButton.enclosedInVerticalStackView(isFullWidthButton: true),
        ])
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationConfimModeSwitchPresenter: RegistrationConfimModeSwitchPresenter {
    func confirmSwitchToDeviceLinkingMode() {
        print("confirmSwitchToDeviceLinkingMode")
    }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationConfimModeSwitchPresenter()
    return UINavigationController(
        rootViewController: RegistrationConfirmModeSwitchViewController(
            presenter: presenter,
        ),
    )
}

#endif
