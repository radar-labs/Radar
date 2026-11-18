//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import UIKit

extension UIColor {
    public convenience init(rgbHex value: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((value >> 16) & 0xff) / 255.0
        let green = CGFloat((value >> 8) & 0xff) / 255.0
        let blue = CGFloat((value >> 0) & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    public var rgbHex: UInt32 {
        let (red, green, blue, _) = components() ?? (0, 0, 0, 0)
        return UInt32(red * 255) << 16 | UInt32(green * 255) << 8 | UInt32(blue * 255) << 0
    }

    public convenience init(argbHex value: UInt32) {
        let alpha = CGFloat((value >> 24) & 0xff) / 255.0
        let red = CGFloat((value >> 16) & 0xff) / 255.0
        let green = CGFloat((value >> 8) & 0xff) / 255.0
        let blue = CGFloat((value >> 0) & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    public var argbHex: UInt32 {
        let (red, green, blue, alpha) = components() ?? (0, 0, 0, 0)
        return UInt32(alpha * 255) << 24 | UInt32(red * 255) << 16 | UInt32(green * 255) << 8 | UInt32(blue * 255) << 0
    }

    public func isEqualToColor(_ color: UIColor, tolerance: CGFloat = 0) -> Bool {
        let (r1, g1, b1, a1) = self.components() ?? (0, 0, 0, 0)
        let (r2, g2, b2, a2) = color.components() ?? (0, 0, 0, 0)

        return abs(r1 - r2) <= tolerance &&
            abs(g1 - g2) <= tolerance &&
            abs(b1 - b2) <= tolerance &&
            abs(a1 - a2) <= tolerance
    }

    public func components() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        var alpha = CGFloat.zero
        let result = unsafe getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return result ? (red, green, blue, alpha) : nil
    }
}
