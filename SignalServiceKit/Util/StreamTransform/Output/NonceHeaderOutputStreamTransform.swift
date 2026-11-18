//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class NonceHeaderOutputStreamTransform: StreamTransform {

    private let metadataHeader: BackupNonce.MetadataHeader

    public init(metadataHeader: BackupNonce.MetadataHeader) {
        self.metadataHeader = metadataHeader
    }

    private var hasWrittenHeader = false

    public func transform(data: Data, options: Options) throws -> Data {
        if hasWrittenHeader { return data }
        defer { hasWrittenHeader = true }

        return BackupNonce.magicFileSignature + metadataHeader.data.prefixedWithVarintLength() + data
    }
}
