//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BackupConfirmKeyViewController: EnterAccountEntropyPoolViewController, OWSNavigationChildController {
    private let aep: AccountEntropyPool

    init(
        aep: AccountEntropyPool,
        onConfirmed: @escaping (BackupConfirmKeyViewController) -> Void,
        onSeeKeyAgain: @escaping () -> Void,
    ) {
        self.aep = aep

        super.init()

        OWSTableViewController2.removeBackButtonText(viewController: self)

        let seeKeyAgainButtonTitle = OWSLocalizedString(
            "BACKUP_ONBOARDING_CONFIRM_KEY_SEE_KEY_AGAIN_BUTTON_TITLE",
            comment: "Title for a button offering to let users see their 'Recovery Key'.",
        )

        configure(
            aepValidationPolicy: .acceptOnly(aep),
            colorConfig: ColorConfig(
                background: UIColor.Signal.groupedBackground,
                aepEntryBackground: UIColor.Signal.secondaryGroupedBackground,
            ),
            headerStrings: HeaderStrings(
                title: OWSLocalizedString(
                    "BACKUP_ONBOARDING_CONFIRM_KEY_TITLE",
                    comment: "Title for a view asking users to confirm their 'Recovery Key'.",
                ),
                subtitle: OWSLocalizedString(
                    "BACKUP_ONBOARDING_CONFIRM_KEY_SUBTITLE",
                    comment: "Subtitle for a view asking users to confirm their 'Recovery Key'.",
                ),
            ),
            footerButtonConfig: FooterButtonConfig(
                title: seeKeyAgainButtonTitle,
                action: {
                    onSeeKeyAgain()
                },
            ),
            onEntryConfirmed: { [weak self] _ in
                guard let self else { return }

                present(
                    BackupKeepKeySafeSheet(
                        onContinue: { onConfirmed(self) },
                        secondaryButton: HeroSheetViewController.Button(
                            title: seeKeyAgainButtonTitle,
                            style: .secondary,
                            action: .custom({ sheet in
                                sheet.dismiss(animated: true) {
                                    onSeeKeyAgain()
                                }
                            }),
                        ),
                    ),
                    animated: true,
                )
            },
        )
    }

    // MARK: OWSNavigationChildController

    var navbarBackgroundColorOverride: UIColor? {
        .Signal.groupedBackground
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    let aep = try! AccountEntropyPool(key: String(
        repeating: "a",
        count: AccountEntropyPool.Constants.byteLength,
    ))

    return UINavigationController(
        rootViewController: BackupConfirmKeyViewController(
            aep: aep,
            onConfirmed: { _ in print("Confirmed...!") },
            onSeeKeyAgain: { print("Seeing key again...!") },
        ),
    )
}

#endif
