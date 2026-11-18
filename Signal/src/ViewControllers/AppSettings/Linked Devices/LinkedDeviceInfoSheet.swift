//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class LinkedDeviceInfoSheet: HeroSheetViewController {
    init() {
        let header = OWSLocalizedString(
            "LINKED_DEVICE_INFO_SHEET_HEADER",
            comment: "Lead paragraph for a sheet explaining linked devices. The text within the <bold></bold> tags is styled bold.",
        ).styled(
            with: .font(.dynamicTypeBody),
            .xmlRules([.style("bold", .init(.font(.dynamicTypeBody.semibold())))]),
        )

        super.init(
            hero: .image(.allDevices),
            title: nil,
            body: HeroSheetViewController.Body([
                .text(.attributed(header), alignment: .left, color: .Signal.label),
                .customSpacing(16),
                .bullets(hMargin: 0, [
                    .init(style: .dot, text: OWSLocalizedString(
                        "LINKED_DEVICE_INFO_SHEET_BULLET_1",
                        comment: "Bullet point on the linked devices info sheet, describing what can be linked.",
                    )),
                    .init(style: .dot, text: OWSLocalizedString(
                        "LINKED_DEVICE_INFO_SHEET_BULLET_2",
                        comment: "Bullet point on the linked devices info sheet, describing that the primary device manages linking.",
                    )),
                    .init(style: .dot, text: OWSLocalizedString(
                        "LINKED_DEVICE_INFO_SHEET_BULLET_3",
                        comment: "Bullet point on the linked devices info sheet, describing that some settings are primary-only.",
                    )),
                ]),
            ]),
            primary: nil,
            secondary: nil,
        )
    }
}

#if DEBUG
@available(iOS 17, *)
#Preview {
    SheetPreviewViewController(sheet: LinkedDeviceInfoSheet())
}
#endif
