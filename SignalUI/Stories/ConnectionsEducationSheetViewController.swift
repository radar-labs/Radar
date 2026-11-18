//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class ConnectionsEducationSheetViewController: HeroSheetViewController {
    public init() {
        let header = OWSLocalizedString(
            "STORY_SETTINGS_LEARN_MORE_SHEET_HEADER_FORMAT",
            comment: "Header for the explainer sheet for signal connections",
        ).styled(
            with: .font(.dynamicTypeBody),
            .xmlRules([.style("bold", .init(.font(UIFont.dynamicTypeHeadline)))]),
        )

        super.init(
            hero: .image(UIImage(named: "connections-display-bold")!, tintColor: .Signal.label, height: 56),
            title: nil,
            body: .init(font: .dynamicTypeBody, [
                .text(.attributed(header), alignment: .natural, color: .Signal.label),
                .customSpacing(20),
                .bullets(hMargin: 12, [
                    .init(style: .dash, text: OWSLocalizedString(
                        "STORY_SETTINGS_LEARN_MORE_SHEET_BULLET_1",
                        comment: "First bullet point for the explainer sheet for signal connections",
                    )),
                    .init(style: .dash, text: OWSLocalizedString(
                        "STORY_SETTINGS_LEARN_MORE_SHEET_BULLET_2",
                        comment: "Second bullet point for the explainer sheet for signal connections",
                    )),
                    .init(style: .dash, text: OWSLocalizedString(
                        "STORY_SETTINGS_LEARN_MORE_SHEET_BULLET_3",
                        comment: "Third bullet point for the explainer sheet for signal connections",
                    )),
                ]),
                .customSpacing(20),
                .text(
                    .plain(OWSLocalizedString(
                        "STORY_SETTINGS_LEARN_MORE_SHEET_FOOTER",
                        comment: "Footer for the explainer sheet for signal connections",
                    )),
                    alignment: .natural,
                    color: .Signal.label,
                ),
            ]),
            primary: nil,
            secondary: nil,
        )
    }
}

#if DEBUG
@available(iOS 17, *)
#Preview {
    SheetPreviewViewController(sheet: ConnectionsEducationSheetViewController())
}
#endif
