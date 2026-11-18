//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol ByteArrayInitializable: ByteArray {
    init(contents: Data) throws
}

extension ReceiptCredentialRequestContext: ByteArrayInitializable {}
extension ReceiptCredentialPresentation: ByteArrayInitializable {}
extension ReceiptCredential: ByteArrayInitializable {}

public struct ByteArrayCodable<T: ByteArrayInitializable>: Codable {
    public let wrappedValue: T

    public init(_ wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try T(contents: container.decode(Data.self)))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wrappedValue.serialize())
    }
}
