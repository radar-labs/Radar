//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CVComponentGiftBadge: CVComponentBase, CVComponent {

    var componentKey: CVComponentKey { .giftBadge }

    private let giftBadge: CVComponentState.GiftBadge

    private let viewState: ViewState

    // Component state objects are derived from TSInteractions, and they're
    // only updated when the underlying interaction changes. The "N days
    // remaining" label depends on the current time, so we need to use
    // CVItemViewState, which is refreshed even when the underlying interaction
    // hasn't changed. This is similar to how the time in the footer works.
    struct ViewState: Equatable {
        let timeRemainingText: String
        let profileBadge: ProfileBadge?
    }

    static func buildViewState(_ giftBadge: CVComponentState.GiftBadge) -> ViewState {
        ViewState(
            timeRemainingText: GiftBadgeView.timeRemainingText(for: giftBadge.expirationDate),
            profileBadge: giftBadge.profileBadge,
        )
    }

    private var state: GiftBadgeView.State {
        return GiftBadgeView.State(
            profileBadge: self.giftBadge.profileBadge,
            messageUniqueId: self.giftBadge.messageUniqueId,
            timeRemainingText: self.viewState.timeRemainingText,
            otherUserShortName: self.giftBadge.otherUserShortName,
            redemptionState: self.giftBadge.redemptionState,
            isIncoming: self.isIncoming,
            conversationStyle: self.conversationStyle,
        )
    }

    init(itemModel: CVItemModel, giftBadge: CVComponentState.GiftBadge, viewState: ViewState) {
        self.giftBadge = giftBadge
        self.viewState = viewState
        super.init(itemModel: itemModel)
    }

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewGiftBadge(componentDelegate: componentDelegate)
    }

    func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentView as? CVComponentViewGiftBadge else {
            owsFailDebug("unexpected componentView")
            componentView.reset()
            return
        }

        componentView.messageUniqueId = self.giftBadge.messageUniqueId
        componentView.giftBadgeView.configureForRendering(
            state: self.state,
            cellMeasurement: cellMeasurement,
            componentDelegate: componentDelegate,
        )
    }

    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        return GiftBadgeView.measurement(for: self.state, maxWidth: maxWidth, measurementBuilder: measurementBuilder)
    }

    func configureGiftWrapIfNeeded(componentView: CVComponentView) -> (ManualLayoutView, OWSBubbleViewPartner)? {
        guard let componentView = componentView as? CVComponentViewGiftBadge else {
            owsFailDebug("unexpected componentView")
            return nil
        }
        guard let giftWrap = componentView.giftBadgeView.giftWrap else {
            return nil
        }
        return (giftWrap.rootView, giftWrap.bubbleViewPartner)
    }

    override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {

        guard let componentView = componentView as? CVComponentViewGiftBadge else {
            owsFailDebug("unexpected componentView")
            return false
        }
        let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
        let giftBadgeView = componentView.giftBadgeView

        if giftBadgeView.giftWrap != nil {
            componentDelegate.willUnwrapGift(itemViewModel)
            giftBadgeView.animateUnwrap()
            return true
        }

        guard let profileBadge = self.viewState.profileBadge else {
            // If there's not a badge, it's still showing the loading indicator.
            return false
        }

        let buttonView = giftBadgeView.buttonStack
        guard buttonView.bounds.contains(sender.location(in: buttonView)) else {
            return false
        }

        let giftBadge = self.giftBadge
        componentDelegate.didTapGiftBadge(
            itemViewModel,
            profileBadge: profileBadge,
            isExpired: giftBadge.expirationDate.isBeforeNow,
            isRedeemed: giftBadge.redemptionState == .redeemed,
        )
        return true
    }

    class CVComponentViewGiftBadge: CVComponentView {
        fileprivate let giftBadgeView = GiftBadgeView(name: "GiftBadgeView")

        fileprivate var messageUniqueId: String?

        private weak var componentDelegate: CVComponentDelegate?

        var isDedicatedCellView = false

        var rootView: UIView { giftBadgeView }

        init(componentDelegate: CVComponentDelegate) {
            self.componentDelegate = componentDelegate
        }

        func setIsCellVisible(_ isCellVisible: Bool) {
            guard
                isCellVisible,
                let giftWrap = self.giftBadgeView.giftWrap,
                let componentDelegate = self.componentDelegate,
                let messageUniqueId = self.messageUniqueId,
                componentDelegate.willShakeGift(messageUniqueId)
            else {
                return
            }

            _ = componentDelegate.beginCellAnimation(maximumDuration: GiftWrap.shakeAnimationDuration)
            giftWrap.animateShake()
        }

        func reset() {
            self.messageUniqueId = nil
            giftBadgeView.reset()
        }
    }
}
