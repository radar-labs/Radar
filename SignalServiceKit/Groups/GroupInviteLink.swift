//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct GroupInviteLink: Hashable {
    public let masterKey: GroupMasterKey
    public let inviteLinkPassword: Data

    public init(masterKey: GroupMasterKey, inviteLinkPassword: Data) throws {
        if inviteLinkPassword.isEmpty {
            throw OWSGenericError("inviteLinkPassword must not be empty")
        }
        self.masterKey = masterKey
        self.inviteLinkPassword = inviteLinkPassword
    }

    private static let inviteLinkPasswordLength: UInt = 16

    public static func generateInviteLinkPassword() -> Data {
        return Randomness.generateRandomBytes(inviteLinkPasswordLength)
    }

    public static func parseFrom(_ url: PossibleGroupInviteLinkUrl) throws -> Self {
        let encodedInviteLink = try Data.data(fromBase64Url: url.rawValue.fragment ?? "")
        let inviteLink = try GroupsProtoGroupInviteLink(serializedData: encodedInviteLink)
        switch inviteLink.contents {
        case .contentsV1(let contents):
            let masterKey = try GroupMasterKey(contents: contents.groupMasterKey ?? Data())
            return try Self(masterKey: masterKey, inviteLinkPassword: contents.inviteLinkPassword ?? Data())
        case nil:
            throw OWSGenericError("missing contents")
        }
    }

    public func url() -> URL {
        var contentsV1Builder = GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1.builder()
        contentsV1Builder.setGroupMasterKey(masterKey.serialize())
        contentsV1Builder.setInviteLinkPassword(inviteLinkPassword)

        var builder = GroupsProtoGroupInviteLink.builder()
        builder.setContents(GroupsProtoGroupInviteLinkOneOfContents.contentsV1(contentsV1Builder.buildInfallibly()))
        let protoData = failIfThrows { try builder.buildSerializedData() }

        let protoBase64Url = protoData.asBase64Url

        let urlString = "https://signal.group/#\(protoBase64Url)"
        return URL(string: urlString).owsFailUnwrap("must be able to construct URL")
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(masterKey.serialize())
        hasher.combine(inviteLinkPassword)
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        return (
            lhs.masterKey.serialize().ows_constantTimeIsEqual(to: rhs.masterKey.serialize())
                && lhs.inviteLinkPassword.ows_constantTimeIsEqual(to: rhs.inviteLinkPassword),
        )
    }
}

// MARK: -

public struct PossibleGroupInviteLinkUrl {
    public let rawValue: URL

    private init(rawValue: URL) {
        self.rawValue = rawValue
    }

    public static func parseFrom(_ url: URL) -> Self? {
        let possibleHosts: [String]
        if url.scheme == "https" {
            possibleHosts = ["signal.group"]
        } else if url.scheme == "sgnl" {
            possibleHosts = ["signal.group", "joingroup"]
        } else {
            possibleHosts = []
        }
        guard let host = url.host, possibleHosts.contains(host) else {
            return nil
        }
        return Self(rawValue: url)
    }
}
