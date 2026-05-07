//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

extension UIApplication {
    var currentAppIcon: AppIcon {
        if let alternateIconName, let appIcon = AppIcon(alternateIconName: alternateIconName) {
            return appIcon
        }
        return .default
    }
}

enum AppIcon: String {
    case `default` = "AppIcon"

    init?(alternateIconName: String) {
        if let asset = AppIcon(rawValue: alternateIconName) {
            self = asset
        } else {
            owsFailDebug("Unknown alternative app icon name '\(alternateIconName)'")
            return nil
        }
    }

    var alternateIconName: String? {
        if case .default = self {
            nil
        } else {
            rawValue
        }
    }

    var previewImageResource: ImageResource {
        switch self {
        case .default: ImageResource.AppIconPreview.default
        }
    }
}
