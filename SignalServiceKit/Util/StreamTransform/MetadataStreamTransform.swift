//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation

public class MetadataStreamTransform: StreamTransform, FinalizableStreamTransform {
    public var hasFinalized: Bool { result != nil }

    private var result: SHA256.Digest?
    private var hasher: SHA256

    public func digest() throws -> Data {
        guard let result else {
            throw OWSAssertionError("Reading digest before finalized")
        }
        return Data(result)
    }

    init() {
        self.hasher = SHA256()
    }

    public private(set) var count: Int = 0

    public func transform(data: Data, options: Options) -> Data {
        hasher.update(data: data)
        count += data.count
        return data
    }

    public func finalize() -> Data {
        owsPrecondition(result == nil)
        result = hasher.finalize()
        return Data()
    }
}

public class ByteCountStreamTransform: StreamTransform, FinalizableStreamTransform {
    public var hasFinalized = false

    public private(set) var count: Int = 0

    public func transform(data: Data, options: Options) -> Data {
        count += data.count
        return data
    }

    public func finalize() -> Data {
        hasFinalized = true
        return Data()
    }
}
