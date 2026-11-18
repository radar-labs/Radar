//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CVComponentContactShare: CVComponentBase, CVComponent, CVAccessibilityComponent {

    var componentKey: CVComponentKey { .contactShare }

    private let contactShareState: CVComponentState.ContactShare

    private var contactShare: ContactShareViewModel {
        contactShareState.state.contactShare
    }

    init(itemModel: CVItemModel, contactShareState: CVComponentState.ContactShare) {
        self.contactShareState = contactShareState

        super.init(itemModel: itemModel)
    }

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewContactShare()
    }

    func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentViewParam as? CVComponentViewContactShare else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let contactShareView = componentView.contactShareView
        contactShareView.configureForRendering(
            state: contactShareState.state,
            cellMeasurement: cellMeasurement,
        )
    }

    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        return CVContactShareView.measure(
            maxWidth: maxWidth,
            measurementBuilder: measurementBuilder,
            state: contactShareState.state,
        )
    }

    override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {

        componentDelegate.didTapContactShare(contactShare)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    class CVComponentViewContactShare: CVComponentView {

        fileprivate let contactShareView = CVContactShareView(name: "CVContactShareView")

        var isDedicatedCellView = false

        var rootView: UIView {
            contactShareView
        }

        func setIsCellVisible(_ isCellVisible: Bool) {}

        func reset() {
            contactShareView.reset()
        }

    }

    // MARK: - CVAccessibilityComponent

    var accessibilityDescription: String {
        if let contactName = contactShare.displayName.filterForDisplay.nilIfEmpty {
            let format = OWSLocalizedString(
                "ACCESSIBILITY_LABEL_CONTACT_FORMAT",
                comment: "Accessibility label for contact. Embeds: {{ the contact name }}.",
            )
            return String.nonPluralLocalizedStringWithFormat(format, contactName)
        } else {
            return OWSLocalizedString(
                "ACCESSIBILITY_LABEL_CONTACT",
                comment: "Accessibility label for contact.",
            )
        }
    }
}
