//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CVComponentBottomButtons: CVComponentBase, CVComponent {

    var componentKey: CVComponentKey { .bottomButtons }

    private let bottomButtonsState: CVComponentState.BottomButtons

    typealias Action = CVMessageAction
    fileprivate var actions: [Action] { bottomButtonsState.actions }

    init(itemModel: CVItemModel, bottomButtonsState: CVComponentState.BottomButtons) {
        self.bottomButtonsState = bottomButtonsState

        super.init(itemModel: itemModel)
    }

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewBottomButtons()
    }

    func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentViewParam as? CVComponentViewBottomButtons else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        componentView.reset()

        var subviews = [UIView]()
        for action in actions {
            let buttonView = CVMessageActionButton(action: action)
            if isIncoming {
                if conversationStyle.hasWallpaper {
                    buttonView.backgroundColor = .Signal.MaterialBase.button
                } else {
                    buttonView.backgroundColor = .Signal.LightBase.button
                }
                buttonView.textColor = .Signal.label
            } else {
                buttonView.backgroundColor = .Signal.ColorBase.button
                buttonView.textColor = .Signal.ColorBase.labelPrimary
            }
            subviews.append(buttonView)
            componentView.buttonViews.append(buttonView)
        }

        let isHorizontal = cellMeasurement.value(key: Self.measurementKey_isHorizontal) == 1
        let stackView = componentView.stackView
        stackView.reset()
        stackView.configure(
            config: Self.stackConfig(isHorizontal: isHorizontal),
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_stackView,
            subviews: subviews,
        )
    }

    private static func stackConfig(isHorizontal: Bool) -> CVStackViewConfig {
        CVStackViewConfig(
            axis: isHorizontal ? .horizontal : .vertical,
            alignment: .fill,
            spacing: Self.buttonSpacing,
            layoutMargins: .init(top: 6, leading: 12, bottom: 12, trailing: 12),
        )
    }

    fileprivate static var buttonHeight: CGFloat { CVMessageActionButton.buttonHeight }
    private static let buttonSpacing: CGFloat = 8

    private static let measurementKey_stackView = "CVComponentBottomButtons.measurementKey_stackView"
    private static let measurementKey_isHorizontal = "CVComponentBottomButtons.measurementKey_isHorizontal"

    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let contentWidth = max(0, maxWidth - Self.stackConfig(isHorizontal: true).layoutMargins.totalWidth)
        let totalSpacing = Self.buttonSpacing * CGFloat(max(0, actions.count - 1))
        let horizontalButtonWidth = max(0, contentWidth - totalSpacing) / CGFloat(max(1, actions.count))
        let isHorizontal = actions.allSatisfy { action in
            CVMessageActionButton.minimumWidth(title: action.title) <= horizontalButtonWidth
        }
        measurementBuilder.setValue(key: Self.measurementKey_isHorizontal, value: isHorizontal ? 1 : 0)

        let subviewSize = CGSize(width: isHorizontal ? horizontalButtonWidth : contentWidth, height: Self.buttonHeight)
        var subviewInfos = [ManualStackSubviewInfo]()
        for _ in 0..<actions.count {
            subviewInfos.append(subviewSize.asManualSubviewInfo)
        }
        let stackMeasurement = ManualStackView.measure(
            config: Self.stackConfig(isHorizontal: isHorizontal),
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_stackView,
            subviewInfos: subviewInfos,
            maxWidth: maxWidth,
        )
        return stackMeasurement.measuredSize
    }

    // MARK: - Events

    override func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {

        guard let componentView = componentView as? CVComponentViewBottomButtons else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        for buttonView in componentView.buttonViews {
            let location = sender.location(in: buttonView)
            guard buttonView.bounds.contains(location) else {
                continue
            }
            buttonView.action.perform(delegate: componentDelegate)
            return true
        }
        return false
    }

    // MARK: -

    private class CVMessageActionButton: CVLabel {

        let action: CVMessageAction

        init(action: CVMessageAction) {
            self.action = action

            super.init(frame: .zero)

            configure()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func configure() {
            layoutMargins = .zero
            layer.masksToBounds = true
            layer.cornerRadius = Self.buttonHeight / 2
            text = action.title
            font = Self.buttonFont
            textAlignment = .center
        }

        private static var buttonFont: UIFont { UIFont.dynamicTypeFootnoteClamped.medium() }

        private static let buttonVMargin: CGFloat = 5
        private static let minimumTitleHMargin: CGFloat = 12

        static var buttonHeight: CGFloat {
            ceil(buttonFont.lineHeight + buttonVMargin * 2).clamp(28, 44)
        }

        static func minimumWidth(title: String) -> CGFloat {
            let labelConfig = CVLabelConfig.unstyledText(title, font: buttonFont, textColor: .Signal.label)
            let titleSize = CVText.measureLabel(config: labelConfig, maxWidth: .greatestFiniteMagnitude)
            return ceil(titleSize.width) + minimumTitleHMargin * 2
        }
    }

    private class CVComponentViewBottomButtons: CVComponentView {

        let stackView = ManualStackView(name: "bottomButtons")
        var buttonViews = [CVMessageActionButton]()

        var isDedicatedCellView = false

        var rootView: UIView {
            stackView
        }

        func setIsCellVisible(_ isCellVisible: Bool) {}

        func reset() {
            stackView.reset()

            buttonViews.removeAll()
        }
    }
}
