//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol CVBackgroundContainerDelegate: AnyObject {
    func updateScrollingContent()
}

class CVBackgroundContainer: ManualLayoutViewWithLayer, WallpaperBlurProvider {

    private enum ZPositioning: CGFloat {
        case wallpaperContent = 0
        case wallpaperDimming = 1
        case selectionHighlight = 2
    }

    fileprivate var wallpaperView: WallpaperView?

    weak var delegate: CVBackgroundContainerDelegate?

    init() {
        super.init(name: "CVBackgroundContainer")

        self.shouldDeactivateConstraints = false
        self.isUserInteractionEnabled = false
        // Render all background views behind the collection view.
        self.layer.zPosition = -1

        // Wallpaper blocks voiceover's ability to focus on the
        // correct message when a user opens a conversation since it
        // appears later in the subview array than the message collection view.
        // Hide it from the accessibility tree so voiceover users can read messages properly.
        self.accessibilityElementsHidden = true
    }

    func set(wallpaperView: WallpaperView?) {
        self.wallpaperView?.contentView?.removeFromSuperview()
        self.wallpaperView?.dimmingView?.removeFromSuperview()
        self.wallpaperView = wallpaperView

        if let wallpaperView {
            self.backgroundColor = .clear

            if let contentView = wallpaperView.contentView {
                addSubview(contentView)
                contentView.layer.zPosition = ZPositioning.wallpaperContent.rawValue
            }
            if let dimmingView = wallpaperView.dimmingView {
                addSubview(dimmingView)
                dimmingView.layer.zPosition = ZPositioning.wallpaperDimming.rawValue
            }

            setNeedsLayout()
        } else {
            self.backgroundColor = Theme.backgroundColor
        }
    }

    override func layoutSubviews() {
        AssertIsOnMainThread()

        super.layoutSubviews()

        wallpaperView?.contentView?.frame = bounds
        wallpaperView?.dimmingView?.frame = bounds

        delegate?.updateScrollingContent()
    }

    // MARK: - WallpaperBlurProvider

    var wallpaperBlurState: WallpaperBlurState? {
        wallpaperView?.blurProvider?.wallpaperBlurState
    }
}

// MARK: -

extension ConversationViewController: CVBackgroundContainerDelegate {

    func updateScrollingContent() {
        AssertIsOnMainThread()

        UIView.performWithoutAnimation {
            for cell in collectionView.visibleCells {
                guard let cell = cell as? CVCell else {
                    owsFailDebug("Invalid cell.")
                    continue
                }
                cell.updateScrollingContent()
            }
        }
    }
}
