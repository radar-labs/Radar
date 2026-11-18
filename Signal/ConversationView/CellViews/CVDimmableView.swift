//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol CVDimmableView: ManualLayoutView {
    /// Can be a dynamic color that will get resolved at rendering time.
    var dimmerColor: UIColor { get set }

    /// When set to `true` dimmer layer will be displayed on top of all subviews.
    /// Applicable when content needs to be dimmed too (eg media bubbles).
    var dimsContent: Bool { get set }

    /// If `dimsContent` is `false` the dimmer layer
    /// will be placed above the sublayer retuned by this method.
    /// If `nil` is returned, dimmerLayer will be placed on top of all sublayers.
    var backgroundLayer: CALayer? { get }

    /// - Parameter animationDuration: Duration for fade-in and fade-out animations.
    /// - Parameter dimDuration: How long the dimmer stays visible.
    func performDimmingAnimation(animationDuration: TimeInterval, dimDuration: TimeInterval)
}

extension CVDimmableView {

    private func sublayerIndexForDimmerLayer() -> UInt32 {
        if
            dimsContent == false,
            let backgroundLayer,
            let backgroundLayerIndex = layer.sublayers!.firstIndex(of: backgroundLayer)
        {
            // Just above background layer if there's one and it is part of the view hierarchy.
            return UInt32(backgroundLayerIndex) + 1
        }
        return UInt32(layer.sublayers!.count)
    }

    func performDimmingAnimation(animationDuration: TimeInterval, dimDuration: TimeInterval) {
        let dimmerLayerIndex = sublayerIndexForDimmerLayer()
        let dimmerLayer = CALayer()
        dimmerLayer.opacity = 0
        dimmerLayer.backgroundColor = dimmerColor.resolvedColor(with: traitCollection).cgColor
        dimmerLayer.frame = layer.bounds
        layer.insertSublayer(dimmerLayer, at: dimmerLayerIndex)

        // Animate fade-in.
        let fadeIn = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = animationDuration
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        dimmerLayer.add(fadeIn, forKey: "fadeIn")

        // Schedule fade-out after delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + dimDuration) {
            let fadeOut = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
            fadeOut.fromValue = 1
            fadeOut.toValue = 0
            fadeOut.duration = animationDuration
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false
            fadeOut.delegate = DimAnimationDelegate(layer: dimmerLayer)
            dimmerLayer.add(fadeOut, forKey: "fadeOut")
        }
    }
}

private class DimAnimationDelegate: NSObject, CAAnimationDelegate {
    private weak var layer: CALayer?

    init(layer: CALayer) {
        self.layer = layer
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        // This is necessary to ensure proper deallocation of both CALayer and DimAnimationDelegate.
        layer?.removeFromSuperlayer()
        layer?.removeAllAnimations()
    }
}
