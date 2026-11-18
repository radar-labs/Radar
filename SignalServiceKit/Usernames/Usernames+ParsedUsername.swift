//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

extension LibSignalClient.Username {
    public func components() -> UsernameComponents { UsernameComponents(self) }
}

public struct UsernameComponents {
    public let nickname: String
    public let discriminator: String
    public let originalValue: LibSignalClient.Username

    fileprivate init(_ username: LibSignalClient.Username) {
        let components = username.value.split(separator: ".")
        self.nickname = String(components.first.owsFailUnwrap("must be valid"))
        self.discriminator = String(components.last.owsFailUnwrap("must be valid"))
        self.originalValue = username
    }

    public func adjustingCase(_ nickname: String) -> LibSignalClient.Username? {
        guard nickname.lowercased() == self.nickname.lowercased() else {
            return nil
        }
        // This parsing may fail if a case-folded matching value isn't valid.
        return try? LibSignalClient.Username("\(nickname).\(self.discriminator)")
    }
}
