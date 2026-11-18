//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class ChunkedOutputStreamTransform: StreamTransform {

    public func transform(data: Data, options: Options) throws -> Data {
        return data.prefixedWithVarintLength()
    }
}

// MARK: -

extension Data {

    /// Returns a `Data` containing ourselves, prefixed with a varint
    /// representing the length of ourselves.
    public func prefixedWithVarintLength() -> Data {
        var result = Data()

        var v = UInt32(self.count)
        while v > 0x7F {
            result.append(contentsOf: [UInt8(v & 0x7f | 0x80)])
            v >>= 7
        }
        result.append(contentsOf: [UInt8(v)])

        result.append(self)
        return result
    }
}
