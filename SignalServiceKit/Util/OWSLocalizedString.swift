//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Bundle {
    @objc(appBundle)
    var app: Bundle {
        if self.bundleURL.pathExtension == "appex" {
            // the bundle of the main app is located in the same directory as
            // the parent of "PlugIns/MyAppExtension.appex" (the location of the app extensions bundle)
            let url = self.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if let otherBundle = Bundle(url: url) {
                return otherBundle
            }
            owsFailDebug("bundle of main app not found")
        }
        return self
    }
}

@inlinable
public func OWSLocalizedString(_ key: String, tableName: String? = nil, value: String = "", comment: String) -> String {
    return NSLocalizedString(key, tableName: tableName, bundle: .main.app, value: value, comment: comment)
}

extension String {
    public static func nonPluralLocalizedStringWithFormat(_ format: String, _ arguments: String...) -> String {
        return nonPluralLocalizedStringWithFormat(format, arguments: arguments)
    }

    public static func nonPluralLocalizedStringWithFormat(_ format: String, arguments: [String]) -> String {
        var result = ""
        var remainingFormat = format[...]
        var remainingArguments = arguments[...]
        while let range = remainingFormat.range(of: "%") {
            result += remainingFormat[..<range.lowerBound]
            remainingFormat = remainingFormat[range.upperBound...]
            let firstCharacter = remainingFormat.removeFirst()
            switch firstCharacter {
            case "%":
                result += "%"
            case "@", "d":
                result += remainingArguments.removeFirst()
            case let digit where digit.isASCII && digit.isNumber && (remainingFormat.hasPrefix("$@") || remainingFormat.hasPrefix("$d")):
                remainingFormat.removeFirst(2)
                result += arguments[arguments.startIndex + digit.wholeNumberValue! - 1]
            default:
                // This is validated by translation-validator before compiling.
                owsFail("can't format string with invalid escape sequence")
            }
        }
        result += remainingFormat
        return result
    }
}

extension NSAttributedString {
    public static func nonPluralLocalizedStringWithFormat(
        _ format: String,
        _ args: NSAttributedString...,
        baseAttributes: [NSAttributedString.Key: Any] = [:],
    ) -> NSAttributedString {
        // Use tokens that can't plausibly appear in real text
        let tokens = args.indices.map { "\u{FFFC}ARG\($0)\u{FFFC}" }
        let formatted = String.nonPluralLocalizedStringWithFormat(format, arguments: tokens)

        let result = NSMutableAttributedString(string: formatted, attributes: baseAttributes)
        for (token, arg) in zip(tokens, args) {
            let range = (result.string as NSString).range(of: token)
            if range.location != NSNotFound {
                result.replaceCharacters(in: range, with: arg)
            }
        }
        return result
    }
}
