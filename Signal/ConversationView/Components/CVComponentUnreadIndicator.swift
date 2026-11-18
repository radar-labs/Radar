//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CVComponentUnreadIndicator: CVComponentBase, CVRootComponent {

    var componentKey: CVComponentKey { .unreadIndicator }

    var cellReuseIdentifier: CVCellReuseIdentifier {
        CVCellReuseIdentifier.unreadIndicator
    }

    let isDedicatedCell = true

    override init(itemModel: CVItemModel) {
        super.init(itemModel: itemModel)
    }

    func configureCellRootComponent(
        cellView: UIView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
        messageSwipeActionState: CVMessageSwipeActionState,
        componentView: CVComponentView,
    ) {
        Self.configureCellRootComponent(
            rootComponent: self,
            cellView: cellView,
            cellMeasurement: cellMeasurement,
            componentDelegate: componentDelegate,
            componentView: componentView,
        )
    }

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewUnreadIndicator()
    }

    func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentView as? CVComponentViewUnreadIndicator else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let themeHasChanged = conversationStyle.isDarkThemeEnabled != componentView.isDarkThemeEnabled
        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper

        let isReusing = (
            componentView.rootView.superview != nil &&
                !themeHasChanged &&
                !wallpaperModeHasChanged,
        )

        if !isReusing {
            componentView.reset(resetReusableState: true)
        }

        componentView.isDarkThemeEnabled = conversationStyle.isDarkThemeEnabled
        componentView.hasWallpaper = hasWallpaper

        let outerStack = componentView.outerStack
        let innerStack = componentView.innerStack
        let titleLabel = componentView.titleLabel
        let strokeViewLeading = componentView.strokeViewLeading
        let strokeViewTrailing = componentView.strokeViewTrailing

        titleLabelConfig.applyForRendering(label: titleLabel)

        if isReusing {
            innerStack.configureForReuse(
                config: innerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_innerStack,
            )
            outerStack.configureForReuse(
                config: outerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerStack,
            )
        } else {
            outerStack.reset()

            let visualEffectView: UIVisualEffectView
            if #available(iOS 26, *) {
                let glassEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
                glassEffectView.contentView.addSubview(titleLabel)
                glassEffectView.cornerConfiguration = .capsule()
                visualEffectView = glassEffectView
            } else {
                let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
                blurEffectView.contentView.addSubview(titleLabel)
                blurEffectView.layer.masksToBounds = true
                visualEffectView = blurEffectView
            }
            titleLabel.autoPinEdgesToSuperviewEdges(with: Self.titleLabelMargins)

            let wrapper = ManualLayoutView.wrapSubviewUsingIOSAutoLayout(visualEffectView)
            if #unavailable(iOS 26) {
                wrapper.addLayoutBlock { view in
                    visualEffectView.layer.cornerRadius = view.bounds.size.smallerAxis / 2
                }
            }

            innerStack.reset()
            innerStack.configure(
                config: innerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_innerStack,
                subviews: [wrapper],
            )

            let strokeViewStyle: StrokeView.Style = hasWallpaper ? .double : .single
            strokeViewLeading.style = strokeViewStyle
            strokeViewTrailing.style = strokeViewStyle

            outerStack.configure(
                config: outerStackConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_outerStack,
                subviews: [
                    strokeViewLeading,
                    innerStack,
                    strokeViewTrailing,
                ],
            )
        }
    }

    private var titleLabelConfig: CVLabelConfig {
        CVLabelConfig.unstyledText(
            OWSLocalizedString(
                "MESSAGES_VIEW_UNREAD_INDICATOR",
                comment: "Indicator that separates read from unread messages.",
            ),
            font: UIFont.dynamicTypeFootnote.medium(),
            textColor: Theme.primaryTextColor,
            numberOfLines: 0,
            lineBreakMode: .byTruncatingTail,
            textAlignment: .center,
        )
    }

    private static var titleLabelMargins = UIEdgeInsets(hMargin: 12, vMargin: 3)

    private var outerStackConfig: CVStackViewConfig {
        let cellLayoutMargins = UIEdgeInsets(
            top: 8,
            leading: conversationStyle.fullWidthGutterLeading,
            bottom: 8,
            trailing: conversationStyle.fullWidthGutterTrailing,
        )
        return CVStackViewConfig(
            axis: .horizontal,
            alignment: .center,
            spacing: 6,
            layoutMargins: cellLayoutMargins,
        )
    }

    private var innerStackConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: .center,
            spacing: 0,
            layoutMargins: .zero,
        )
    }

    private static let measurementKey_outerStack = "CVComponentUnreadIndicator.measurementKey_outerStack"
    private static let measurementKey_innerStack = "CVComponentUnreadIndicator.measurementKey_innerStack"

    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let availableWidth = max(0, maxWidth - (Self.titleLabelMargins.totalWidth + outerStackConfig.layoutMargins.totalWidth))
        let labelSize = CVText.measureLabel(config: titleLabelConfig, maxWidth: availableWidth) + Self.titleLabelMargins.asSize

        let strokeSize = CGSize(width: 0, height: 2)

        let labelInfo = labelSize.asManualSubviewInfo
        let innerStackMeasurement = ManualStackView.measure(
            config: innerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_innerStack,
            subviewInfos: [labelInfo],
        )

        let strokeInfo = strokeSize.asManualSubviewInfo(hasFixedHeight: true)
        let innerStackInfo = innerStackMeasurement.measuredSize.asManualSubviewInfo(hasFixedWidth: true)
        let hStackSubviewInfos = [
            strokeInfo,
            innerStackInfo,
            strokeInfo,
        ]
        let hStackMeasurement = ManualStackView.measure(
            config: outerStackConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_outerStack,
            subviewInfos: hStackSubviewInfos,
            maxWidth: maxWidth,
        )
        return hStackMeasurement.measuredSize
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    class CVComponentViewUnreadIndicator: CVComponentView {

        fileprivate let outerStack = ManualStackView(name: "unreadIndicator.outerStack")
        fileprivate let innerStack = ManualStackView(name: "unreadIndicator.innerStack")

        fileprivate let titleLabel = CVLabel()

        fileprivate var hasWallpaper = false
        fileprivate var isDarkThemeEnabled = false

        fileprivate let strokeViewLeading = StrokeView()
        fileprivate let strokeViewTrailing = StrokeView()

        var isDedicatedCellView = false

        var rootView: UIView {
            outerStack
        }

        // MARK: -

        func setIsCellVisible(_ isCellVisible: Bool) {}

        func reset() {
            reset(resetReusableState: false)
        }

        func reset(resetReusableState: Bool) {
            owsAssertDebug(isDedicatedCellView)

            titleLabel.text = nil

            if resetReusableState {
                outerStack.reset()
                innerStack.reset()

                hasWallpaper = false
                isDarkThemeEnabled = false
            }
        }
    }

    fileprivate class StrokeView: ManualLayoutView {
        enum Style {
            case single
            case double
        }

        var style: Style = .single {
            didSet {
                updateStokeStyle()
            }
        }

        private let topStrokeView = UIView()
        private let middleStrokeView = UIView()
        private let bottomStrokeView = UIView()

        init() {
            super.init(name: "StrokeView")

            clipsToBounds = true

            topStrokeView.backgroundColor = UIColor(white: 0, alpha: 0.32)
            middleStrokeView.backgroundColor = UIColor.Signal.quaternaryLabel
            bottomStrokeView.backgroundColor = UIColor(white: 1, alpha: 0.16)

            addSubview(topStrokeView)
            addSubview(middleStrokeView)
            addSubview(bottomStrokeView)

            addDefaultLayoutBlock()
            updateStokeStyle()
        }

        private func addDefaultLayoutBlock() {
            addLayoutBlock { [weak self] _ in
                guard let self else { return }

                let strokeViewSize = CGSize(width: self.bounds.width, height: 1)

                self.topStrokeView.frame = CGRect(
                    origin: CGPoint(x: self.bounds.minX, y: self.bounds.midY - strokeViewSize.height),
                    size: strokeViewSize,
                )
                self.middleStrokeView.frame = CGRect(
                    origin: CGPoint(x: self.bounds.minX, y: self.bounds.midY - strokeViewSize.height / 2),
                    size: strokeViewSize,
                )
                self.bottomStrokeView.frame = CGRect(
                    origin: CGPoint(x: self.bounds.minX, y: self.bounds.midY),
                    size: strokeViewSize,
                )
            }
        }

        private func updateStokeStyle() {
            topStrokeView.isHidden = style == .single
            bottomStrokeView.isHidden = style == .single
            middleStrokeView.isHidden = style == .double
        }
    }
}
