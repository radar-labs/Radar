//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

enum CropRegion {
    // The sides of the crop region.
    case left
    case right
    case top
    case bottom
    // The corners of the crop region.
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

private class CropCornerView: UIView {

    let cropRegion: CropRegion

    var size: CGSize = CGSize(square: CropView.desiredCornerSize) {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    init(cropRegion: CropRegion) {
        self.cropRegion = cropRegion

        super.init(frame: .zero)

        isUserInteractionEnabled = false

        // We need to track `UITraitUserInterfaceStyle` on all iOS versions because
        // the view wouldn't receive it's final interface style until after being added to the superview.
        updateColor()
        if #available(iOS 17, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self], handler: { (self: Self, _) in
                self.updateColor()
            })
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize { size }

    override class var layerClass: AnyClass {
        return CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer? {
        return layer as? CAShapeLayer
    }

    override var bounds: CGRect {
        didSet {
            if bounds != oldValue {
                updatePath()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #unavailable(iOS 17), traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            updateColor()
        }
    }

    private func updateColor() {
        shapeLayer?.fillColor = UIColor.Signal.label.cgColor
    }

    private func updatePath() {
        guard let shapeLayer else {
            return
        }

        let cornerThickness: CGFloat = 2
        let shapeFrame = bounds.insetBy(dx: -cornerThickness, dy: -cornerThickness)
        let bezierPath = UIBezierPath()
        switch cropRegion {
        case .topLeft:
            bezierPath.addRegion(withPoints: [
                shapeFrame.origin,
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.minY),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.minX, y: shapeFrame.maxY - cornerThickness),
            ])
        case .topRight:
            bezierPath.addRegion(withPoints: [
                CGPoint(x: shapeFrame.maxX, y: shapeFrame.minY),
                CGPoint(x: shapeFrame.maxX, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.minY),
            ])
        case .bottomLeft:
            bezierPath.addRegion(withPoints: [
                CGPoint(x: shapeFrame.minX, y: shapeFrame.maxY),
                CGPoint(x: shapeFrame.minX, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.maxY),
            ])
        case .bottomRight:
            bezierPath.addRegion(withPoints: [
                CGPoint(x: shapeFrame.maxX, y: shapeFrame.maxY),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.maxY),
                CGPoint(x: shapeFrame.minX + cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.maxY - cornerThickness),
                CGPoint(x: shapeFrame.maxX - cornerThickness, y: shapeFrame.minY + cornerThickness),
                CGPoint(x: shapeFrame.maxX, y: shapeFrame.minY + cornerThickness),
            ])
        default:
            owsFailDebug("Invalid crop region: \(cropRegion)")
        }

        shapeLayer.path = bezierPath.cgPath
    }
}

private class CropBackgroundView: UIView {

    enum Style {
        case blur
        case darkening
        case blackout
    }

    var style: Style {
        didSet {
            updateStyle()
        }
    }

    private let blurView = UIVisualEffectView()
    private let darkeningView: UIView = {
        let view = UIView()
        view.backgroundColor = .Signal.mediaBackground
        return view
    }()

    init(style: Style) {
        self.style = style

        super.init(frame: .zero)

        isUserInteractionEnabled = false
        addSubview(blurView)
        addSubview(darkeningView)
        updateStyle()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        blurView.frame = bounds
        darkeningView.frame = bounds
    }

    private func updateStyle() {
        switch style {
        case .blur:
            darkeningView.alpha = 0
            blurView.effect = UIBlurEffect(style: .regular)

        case .darkening:
            darkeningView.alpha = 0.5
            blurView.effect = nil

        case .blackout:
            darkeningView.alpha = 1
        }
    }

    var lastKnownMaskRect: CGRect?

    fileprivate func setMaskRect(_ maskRect: CGRect, animationDuration: TimeInterval) {
        if let lastKnownMaskRect, lastKnownMaskRect == maskRect {
            return
        }

        let maskLayer: CAShapeLayer
        if let existingMaskLayer = layer.mask as? CAShapeLayer {
            maskLayer = existingMaskLayer
        } else {
            maskLayer = CAShapeLayer()
            maskLayer.fillRule = .evenOdd
            layer.mask = maskLayer
        }
        maskLayer.frame = layer.bounds

        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(maskRect)

        if animationDuration > 0 {
            let animation = CABasicAnimation(keyPath: #keyPath(CAShapeLayer.path))
            animation.duration = animationDuration
            animation.fromValue = maskLayer.path
            animation.toValue = path
            maskLayer.add(animation, forKey: "path")
        }

        maskLayer.path = path

        lastKnownMaskRect = maskRect
    }
}

final class CropView: UIView {

    static let desiredCornerSize: CGFloat = 22 // adjusted for stroke width, visible size is 24
    private(set) var cornerSize = CGSize(square: CropView.desiredCornerSize)

    private lazy var backgroundView = CropBackgroundView(style: CropView.backgroundStyle(forState: state))

    private let cropFrameView = UIView()

    private let cropCornerViews: [CropCornerView] = [
        CropCornerView(cropRegion: .topLeft),
        CropCornerView(cropRegion: .topRight),
        CropCornerView(cropRegion: .bottomLeft),
        CropCornerView(cropRegion: .bottomRight),
    ]

    private let verticalGridLines: [UIView] = [UIView(), UIView()]
    private let horizontalGridLines: [UIView] = [UIView(), UIView()]

    enum State {
        case initial // no crop frame visible, background set to `blackout`
        case normal // default look: crop frame visible, grid lines hidden, background set to `blur`
        case resizing // user is resizing: crop frame and grid lines visible, background set to `darkening`
    }

    private var state: State = .initial

    // Defines crop frame.
    let cropFrameLayoutGuide = UILayoutGuide()

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false

        addSubview(backgroundView)

        // Crop Frame
        cropFrameLayoutGuide.identifier = "CropFrame"
        addLayoutGuide(cropFrameLayoutGuide)

        cropFrameView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cropFrameView)
        NSLayoutConstraint.activate([
            cropFrameView.leadingAnchor.constraint(equalTo: cropFrameLayoutGuide.leadingAnchor),
            cropFrameView.topAnchor.constraint(equalTo: cropFrameLayoutGuide.topAnchor),
            cropFrameView.trailingAnchor.constraint(equalTo: cropFrameLayoutGuide.trailingAnchor),
            cropFrameView.bottomAnchor.constraint(equalTo: cropFrameLayoutGuide.bottomAnchor),
        ])

        // Crop Frame Corners
        for cropCornerView in cropCornerViews {
            cropCornerView.translatesAutoresizingMaskIntoConstraints = false
            cropFrameView.addSubview(cropCornerView)

            // Note that we use "left" and "right" here.
            switch cropCornerView.cropRegion {
            case .topLeft, .bottomLeft:
                NSLayoutConstraint.activate([cropCornerView.leftAnchor.constraint(equalTo: cropFrameView.leftAnchor)])
            case .topRight, .bottomRight:
                NSLayoutConstraint.activate([cropCornerView.rightAnchor.constraint(equalTo: cropFrameView.rightAnchor)])
            default:
                owsFailDebug("Invalid crop region: \(String(describing: cropCornerView.cropRegion))")
            }
            switch cropCornerView.cropRegion {
            case .topLeft, .topRight:
                NSLayoutConstraint.activate([cropCornerView.topAnchor.constraint(equalTo: cropFrameView.topAnchor)])
            case .bottomLeft, .bottomRight:
                NSLayoutConstraint.activate([cropCornerView.bottomAnchor.constraint(equalTo: cropFrameView.bottomAnchor)])
            default:
                owsFailDebug("Invalid crop region: \(String(describing: cropCornerView.cropRegion))")
            }
        }

        // Spacer Layout Guide that allows to space grid lines evenly
        let spacerLayoutGuide = UILayoutGuide()
        cropFrameView.addLayoutGuide(spacerLayoutGuide)
        NSLayoutConstraint.activate([
            spacerLayoutGuide.leftAnchor.constraint(equalTo: cropFrameView.leftAnchor),
            spacerLayoutGuide.topAnchor.constraint(equalTo: cropFrameView.topAnchor),
            spacerLayoutGuide.widthAnchor.constraint(
                equalTo: cropFrameView.widthAnchor,
                multiplier: 1 / CGFloat(verticalGridLines.count + 1),
            ),
            spacerLayoutGuide.heightAnchor.constraint(
                equalTo: cropFrameView.heightAnchor,
                multiplier: 1 / CGFloat(horizontalGridLines.count + 1),
            ),
        ])

        // Grid Lines
        for (index, line) in verticalGridLines.enumerated() {
            line.backgroundColor = .white // fixed color by design
            line.translatesAutoresizingMaskIntoConstraints = false
            cropFrameView.addSubview(line)
            NSLayoutConstraint.activate([
                line.widthAnchor.constraint(equalToConstant: 1),
                line.topAnchor.constraint(equalTo: cropFrameView.topAnchor),
                line.bottomAnchor.constraint(equalTo: cropFrameView.bottomAnchor),
                NSLayoutConstraint(
                    item: line,
                    attribute: .centerX,
                    relatedBy: .equal,
                    toItem: spacerLayoutGuide,
                    attribute: .right,
                    multiplier: CGFloat(index + 1),
                    constant: 0,
                ),
            ])
        }
        for (index, line) in horizontalGridLines.enumerated() {
            line.backgroundColor = .white // fixed color by design
            line.translatesAutoresizingMaskIntoConstraints = false
            cropFrameView.addSubview(line)
            NSLayoutConstraint.activate([
                line.heightAnchor.constraint(equalToConstant: 1),
                line.leftAnchor.constraint(equalTo: cropFrameView.leftAnchor),
                line.rightAnchor.constraint(equalTo: cropFrameView.rightAnchor),
                NSLayoutConstraint(
                    item: line,
                    attribute: .centerY,
                    relatedBy: .equal,
                    toItem: spacerLayoutGuide,
                    attribute: .bottom,
                    multiplier: CGFloat(index + 1),
                    constant: 0,
                ),
            ])
        }
        setState(.initial, animated: false)

        cropFrameView.layer.borderWidth = 1
        updateFrameColor()
        if #available(iOS 17, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self], handler: { (self: Self, _) in
                self.updateFrameColor()
            })
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #unavailable(iOS 17), traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            updateFrameColor()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        backgroundView.frame = bounds
        // `inheritedAnimationDuration` will return a non-zero value when called from within an animation block.
        // That allows me to attach CAAnimation with the correct duration (if necessary).
        let animationDuration = UIView.inheritedAnimationDuration
        let maskRect = backgroundView.convert(cropFrameView.frame, from: self)
        backgroundView.setMaskRect(maskRect, animationDuration: animationDuration)

        updateCornerSize()
    }

    func setState(_ state: State, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        let cropFrameAlpha: CGFloat = state == .initial ? 0 : 1
        let gridLinesAlpha: CGFloat = state == .resizing ? 1 : 0
        let backgroundStyle = CropView.backgroundStyle(forState: state)
        let layoutBlock = {
            self.cropFrameView.alpha = cropFrameAlpha
            self.verticalGridLines.forEach { $0.alpha = gridLinesAlpha }
            self.horizontalGridLines.forEach { $0.alpha = gridLinesAlpha }
            self.backgroundView.style = backgroundStyle
        }
        if animated {
            UIView.animate(withDuration: 0.15, animations: layoutBlock, completion: completion)
        } else {
            layoutBlock()
            completion?(true)
        }
    }

    private class func backgroundStyle(forState state: State) -> CropBackgroundView.Style {
        switch state {
        case .initial: return .blackout
        case .normal: return .blur
        case .resizing: return .darkening
        }
    }

    private func updateCornerSize() {
        guard cropFrameView.frame.size.isNonEmpty else { return }

        cornerSize = CGSize(
            width: min(cropFrameView.frame.size.width * 0.5, CropView.desiredCornerSize),
            height: min(cropFrameView.frame.size.height * 0.5, CropView.desiredCornerSize),
        )
        cropCornerViews.forEach { $0.size = cornerSize }
    }

    private func updateFrameColor() {
        cropFrameView.layer.borderColor = UIColor.Signal.label.cgColor
    }
}

private extension UIBezierPath {
    func addRegion(withPoints points: [CGPoint]) {
        guard let first = points.first else {
            owsFailDebug("No points.")
            return
        }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
        addLine(to: first)
    }
}
