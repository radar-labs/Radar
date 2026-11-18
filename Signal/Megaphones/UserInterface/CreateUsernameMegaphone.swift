//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

class CreateUsernameMegaphone: Megaphone {
    init(
        usernameSelectionCoordinator: UsernameSelectionCoordinator,
        experienceUpgrade: ExperienceUpgrade,
        fromViewController: UIViewController,
    ) {
        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString(
            "CREATE_USERNAME_MEGAPHONE_TITLE",
            comment: "Title for an interactive in-app prompt to set up a Signal username.",
        )

        bodyText = OWSLocalizedString(
            "CREATE_USERNAME_MEGAPHONE_BODY",
            comment: "Body text for an interactive in-app prompt to set up a Signal username.",
        )

        image = .usernames48
        imageContentMode = .center

        let setUpButton = Button(title: CommonStrings.learnMore) { [weak self, weak fromViewController] in
            guard
                let self,
                let fromViewController
            else { return }

            markAsCompleteWithSneakyTransaction()
            usernameSelectionCoordinator.present(fromViewController: fromViewController)
        }

        let notNowButton = Button(title: CommonStrings.notNowButton) { [weak self] in
            guard let self else { return }
            markAsCompleteWithSneakyTransaction()
        }

        buttons = [setUpButton, notNowButton]
    }
}
