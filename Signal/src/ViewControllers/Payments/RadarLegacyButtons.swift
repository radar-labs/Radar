//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

// Radar: upstream deleted `OWSFlatButton` (5f62f84e5a) and `OWSButton`
// (7cb50b40dd) after moving its own screens to `UIButton.Configuration`.
// Radar's Lightning payment screens were built on them, so this file keeps
// the members those screens use, copied unchanged from the fork base
// (9ea0a9c0f4), to keep their look and behaviour exactly as before.
// Only Radar code uses these types.

class OWSFlatButton: UIView {

    let button: UIButton

    override var accessibilityIdentifier: String? {
        didSet {
            guard let accessibilityIdentifier = self.accessibilityIdentifier else {
                return
            }
            button.accessibilityIdentifier = "\(accessibilityIdentifier).button"
        }
    }

    override var backgroundColor: UIColor? {
        willSet {
            owsFailDebug("Use setBackgroundColors(upColor:) instead.")
        }
    }

    override var tintColor: UIColor! {
        get {
            return button.tintColor
        }
        set {
            button.tintColor = newValue
        }
    }

    init() {
        AssertIsOnMainThread()

        button = UIButton(type: .custom)

        super.init(frame: CGRect.zero)

        self.addSubview(button)
        button.autoPinEdgesToSuperviewEdges()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    class func insetButton(
        title: String,
        font: UIFont,
        titleColor: UIColor,
        backgroundColor: UIColor,
        target: Any,
        selector: Selector,
    ) -> OWSFlatButton {
        return OWSFlatButton.button(
            title: title,
            font: font,
            titleColor: titleColor,
            backgroundColor: backgroundColor,
            target: target,
            selector: selector,
            cornerRadius: CornerStyle.inset,
        )
    }

    private class func button(
        title: String,
        font: UIFont,
        titleColor: UIColor,
        backgroundColor: UIColor,
        cornerRadius: CGFloat,
    ) -> OWSFlatButton {
        let button = OWSFlatButton()
        button.setTitle(
            title: title,
            font: font,
            titleColor: titleColor,
        )
        button.setBackgroundColors(upColor: backgroundColor)
        button.layer.cornerRadius = cornerRadius
        button.clipsToBounds = true
        return button
    }

    class func button(
        title: String,
        font: UIFont,
        titleColor: UIColor,
        backgroundColor: UIColor,
        target: Any,
        selector: Selector,
        cornerRadius: CGFloat = CornerStyle.default,
    ) -> OWSFlatButton {
        let button = button(title: title, font: font, titleColor: titleColor, backgroundColor: backgroundColor, cornerRadius: cornerRadius)
        button.addTarget(target: target, selector: selector)
        return button
    }

    class func heightForFont(_ font: UIFont) -> CGFloat {
        font.lineHeight * 2.5
    }

    // MARK: Methods

    func setTitleColor(_ color: UIColor) {
        button.setTitleColor(color, for: .normal)
    }

    func setTitle(title: String? = nil, font: UIFont? = nil, titleColor: UIColor? = nil) {
        title.map { button.setTitle($0, for: .normal) }
        font.map { button.titleLabel?.font = $0 }
        titleColor.map { setTitleColor($0) }
    }

    func setBackgroundColors(
        upColor: UIColor,
        downColor: UIColor,
    ) {
        button.setBackgroundImage(UIImage.image(color: upColor), for: .normal)
        button.setBackgroundImage(UIImage.image(color: downColor), for: .highlighted)
    }

    func setBackgroundColors(upColor: UIColor) {
        let downColor = upColor == .clear ? upColor : upColor.withAlphaComponent(0.7)
        setBackgroundColors(upColor: upColor, downColor: downColor)
    }

    func setEnabled(_ isEnabled: Bool) {
        button.isEnabled = isEnabled
    }

    func addTarget(
        target: Any,
        selector: Selector,
    ) {
        button.addTarget(target, action: selector, for: .touchUpInside)
    }

    var font: UIFont? {
        return button.titleLabel?.font
    }

    func autoSetHeightUsingFont(extraVerticalInsets: CGFloat = 0) {
        guard let font else {
            owsFailDebug("Missing button font.")
            return
        }
        autoSetDimension(.height, toSize: Self.heightForFont(font) + CGFloat(extraVerticalInsets * 2.0))
    }

    override var intrinsicContentSize: CGSize {
        button.intrinsicContentSize
    }

    enum CornerStyle {
        static let `default`: CGFloat = 5.0
        static let inset: CGFloat = 14.0
    }
}

// MARK: -

class OWSButton: UIButton {

    var block: () -> Void = {}

    var dimsWhenHighlighted = false {
        didSet { updateAlpha() }
    }

    var dimsWhenDisabled = false {
        didSet { updateAlpha() }
    }

    override var isHighlighted: Bool {
        didSet { updateAlpha() }
    }

    override var isEnabled: Bool {
        didSet { updateAlpha() }
    }

    init(block: @escaping () -> Void = {}) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }

    init(
        imageName: String,
        tintColor: UIColor?,
        dimsWhenHighlighted: Bool = false,
        block: @escaping () -> Void = {},
    ) {
        self.dimsWhenHighlighted = dimsWhenHighlighted
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        setImage(imageName: imageName)
        self.tintColor = tintColor
    }

    func setImage(imageName: String?) {
        guard let imageName else {
            setImage(nil, for: .normal)
            return
        }

        if let image = UIImage(named: imageName) {
            setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            owsFailDebug("Missing asset: \(imageName)")
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func didTap() {
        block()
    }

    private func updateAlpha() {
        let isDimmed = (
            (dimsWhenHighlighted && isHighlighted) ||
                (dimsWhenDisabled && !isEnabled)
        )
        alpha = isDimmed ? 0.4 : 1
    }
}
