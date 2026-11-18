//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

extension Usernames {
    public typealias UsernameLink = SignalServiceKit.UsernameLink
}

/// Represents a Signal Dot Me link allowing access to a user's username.
///
/// The username itself is not encoded directly into this link. Instead, the
/// link encodes "entropy data" and a "handle UUID".
///
/// These links look like
/// `{https,sgnl}://signal.me/#eu/{base64url-encoded data}`.
public struct UsernameLink: Equatable {
    private enum LinkUrlComponents {
        static let httpsScheme = "https"
        static let sgnlScheme = "sgnl"
        static let host = "signal.me"
        static let path = "/"
        static let fragmentPrefix = "eu/"
    }

    /// An identifier used to fetch the encrypted form of a username from
    /// the service.
    public let handle: UUID

    /// Entropy used to derive keys with which an encrypted username can be
    /// decrypted.
    public let entropy: Entropy

    public struct Entropy: Equatable {
        public static let length = 32

        public let rawValue: Data

        init(rawValue: Data) throws {
            guard rawValue.count == Self.length else {
                throw OWSGenericError("entropy must be \(Self.length) bytes")
            }
            self.rawValue = rawValue
        }
    }

    public init(handle: UUID, entropy: Entropy) {
        self.handle = handle
        self.entropy = entropy
    }

    public init?(usernameLinkUrl: URL) throws {
        guard let components = URLComponents(url: usernameLinkUrl, resolvingAgainstBaseURL: true) else {
            throw OWSGenericError("malformed url")
        }

        let fragmentPrefix = LinkUrlComponents.fragmentPrefix

        guard
            components.scheme == LinkUrlComponents.httpsScheme || components.scheme == LinkUrlComponents.sgnlScheme,
            components.host == LinkUrlComponents.host,
            components.path == LinkUrlComponents.path || components.path.isEmpty,
            let fragment = components.fragment,
            fragment.hasPrefix(fragmentPrefix)
        else {
            // A valid URL, but not structurally a UsernameLink.
            return nil
        }

        guard
            components.query == nil,
            components.user == nil,
            components.password == nil,
            components.port == nil
        else {
            throw OWSGenericError("malformed url")
        }

        let linkData = try Data.data(fromBase64Url: fragment.dropFirst(fragmentPrefix.count))

        let entropy = try Entropy(rawValue: Data(linkData.prefix(Entropy.length)))

        let handleData = linkData.dropFirst(Entropy.length)
        guard
            let (handle, handleCount) = UUID.from(data: Data(handleData)),
            handleCount == handleData.count
        else {
            throw OWSGenericError("invalid username link handle")
        }

        self.init(handle: handle, entropy: entropy)
    }

    /// Returns this username link as a shareable URL.
    public var url: URL {
        let linkData = entropy.rawValue + handle.data

        var components = URLComponents()
        components.scheme = LinkUrlComponents.httpsScheme
        components.host = LinkUrlComponents.host
        components.path = LinkUrlComponents.path
        components.fragment = "\(LinkUrlComponents.fragmentPrefix)\(linkData.asBase64Url)"

        guard let url = components.url else {
            owsFail("Unexpectedly failed to build shareable username URL!")
        }

        return url
    }

    /// Generate the encrypted username.
    ///
    /// Username links do not directly encode a username. Instead, they encode
    /// "entropy data" and a "handle UUID", which can be used (with support from the
    /// service) to produce a plaintext username.
    ///
    /// Specifically, the server stores an encrypted form of the user's username
    /// which can be retrieved using the handle and decrypted using the entropy.
    /// Importantly, the entropy is never made available to the server, and
    /// consequently the usernames themselves are not exposed to the server.
    ///
    /// This indirection allows the user to rotate their username link without
    /// changing their username, by instead providing the server with a new
    /// encrypted username blob derived from new entropy data (which will
    /// correspond to a new handle).
    ///
    /// Assuming a given link is not outdated, i.e. the link's creator has not
    /// rotated their link, the plaintext username is available by fetching the
    /// encrypted username blob from the service using the handle in the link, and
    /// decrypting it using the entropy in the link.
    ///
    /// - Parameter existingEntropy: Specific entropy to use when encrypting the username.
    public static func encryptUsername(
        _ username: LibSignalClient.Username,
        existingEntropy: Entropy,
    ) -> Data {
        let (entropyData, usernameCiphertext) = failIfThrows {
            return try username.createLink(previousEntropy: existingEntropy.rawValue)
        }
        owsPrecondition(entropyData == existingEntropy.rawValue)
        return usernameCiphertext
    }

    public static func encryptUsername(
        _ username: LibSignalClient.Username,
    ) -> (entropy: Entropy, usernameCiphertext: Data) {
        let (entropyData, usernameCiphertext) = failIfThrows {
            return try username.createLink(previousEntropy: nil)
        }
        return (
            entropy: failIfThrows { try Entropy(rawValue: entropyData) },
            usernameCiphertext: usernameCiphertext,
        )
    }
}
