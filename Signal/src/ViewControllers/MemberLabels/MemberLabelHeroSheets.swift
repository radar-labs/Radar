//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class MemberLabelAboutOverrideHeroSheet: HeroSheetViewController {
    init(dontShowAgainHandler: @escaping () -> Void) {
        super.init(
            hero: .image(.tag22, tintColor: UIColor.Signal.label),
            title: OWSLocalizedString(
                "MEMBER_LABEL_HERO_SHEET_ABOUT_OVERRIDE_TITLE",
                comment: "Title for a sheet shown if a user will show their member label over their About message in a group.",
            ),
            body: OWSLocalizedString(
                "MEMBER_LABEL_HERO_SHEET_ABOUT_OVERRIDE_BODY",
                comment: "Body for a sheet shown if a user will show their member label over their About message in a group.",
            ),
            primaryButton: HeroSheetViewController.Button(
                title: CommonStrings.okButton,
                action: .dismiss,
            ),
            secondaryButton: HeroSheetViewController.Button(
                title: CommonStrings.dontShowAgainButton,
                style: .secondary,
                action: .custom({ sheet in
                    sheet.dismiss(animated: true)
                    dontShowAgainHandler()
                }),
            ),
        )
    }
}

class MemberLabelEducationHeroSheet: HeroSheetViewController {
    init(hasMemberLabel: Bool, editMemberLabelHandler: (() -> Void)?) {
        let memberLabelEditString: String
        if hasMemberLabel {
            memberLabelEditString = OWSLocalizedString("MEMBER_LABEL_EDIT", comment: "Text for a button to set a member label")
        } else {
            memberLabelEditString = OWSLocalizedString("MEMBER_LABEL_SET", comment: "Text for a button to edit an existing member label")
        }

        let title = OWSLocalizedString(
            "MEMBER_LABEL_HERO_SHEET_EDUCATION_TITLE",
            comment: "Title for a sheet shown if a user taps on someone else's member label.",
        )
        let body = OWSLocalizedString(
            "MEMBER_LABEL_HERO_SHEET_EDUCATION_BODY",
            comment: "Body for a sheet shown if a user taps on someone else's member label.",
        )

        let primaryButton: HeroSheetViewController.Button
        var secondaryButton: HeroSheetViewController.Button?
        if let editMemberLabelHandler {
            primaryButton = HeroSheetViewController.Button(
                title: memberLabelEditString,
                action: .custom({ sheet in
                    sheet.dismiss(animated: true)
                    editMemberLabelHandler()
                }),
            )
            secondaryButton = HeroSheetViewController.Button(
                title: CommonStrings.okButton,
                style: .secondary,
                action: .dismiss,
            )
        } else {
            primaryButton = HeroSheetViewController.Button(
                title: CommonStrings.okButton,
                style: .primary,
                action: .dismiss,
            )
        }

        super.init(
            hero: .image(.tag22, tintColor: UIColor.Signal.label),
            title: title,
            body: body,
            primaryButton: primaryButton,
            secondaryButton: secondaryButton,
        )
    }
}
