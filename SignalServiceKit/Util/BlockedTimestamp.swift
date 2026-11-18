//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct BlockedTimestamp: Comparable, Equatable, Hashable, Codable {
    public let rawValue: Int64

    public init(clamping value: Date) {
        self.init(clamping: value.ows_millisecondsSince1970)
    }

    public init(clamping value: some FixedWidthInteger) {
        self.rawValue = Int64(clamping: UInt64(clamping: value))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(clamping: try container.decode(Int64.self))
    }

    public static var unspecified: Self {
        return Self(clamping: 0)
    }

    public static func now() -> Self {
        return Self(clamping: Date())
    }

    public var asDate: Date? {
        if rawValue == 0 {
            return nil
        }
        return Date(millisecondsSince1970: self.asMilliseconds)
    }

    var asMilliseconds: UInt64 {
        return UInt64(self.rawValue)
    }

    public static func <(lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}
