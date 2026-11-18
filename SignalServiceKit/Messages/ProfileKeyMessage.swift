//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

@objc(OWSProfileKeyMessage)
public final class ProfileKeyMessage: TransientOutgoingMessage {

    let profileKey: ProfileKey?

    public init(
        thread: TSContactThread,
        profileKey: ProfileKey,
        tx: DBReadTransaction,
    ) {
        self.profileKey = profileKey
        super.init(
            outgoingMessageWith: TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override public class var supportsSecureCoding: Bool { true }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let profileKey {
            coder.encode(profileKey.serialize(), forKey: "profileKey")
        }
    }

    public required init?(coder: NSCoder) {
        self.profileKey = (coder.decodeObject(of: NSData.self, forKey: "profileKey") as Data?).flatMap { try? ProfileKey(contents: $0) }
        super.init(coder: coder)
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(profileKey?.serialize())
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.profileKey?.serialize() == object.profileKey?.serialize() else { return false }
        return true
    }

    override public func shouldSyncTranscript() -> Bool {
        return false
    }

    override public func buildDataMessage(_ thread: TSThread, transaction: DBReadTransaction) -> SSKProtoDataMessage? {
        let builder = self.dataMessageBuilder(with: thread, transaction: transaction)
        guard let builder else {
            owsFailDebug("could not build protobuf")
            return nil
        }
        builder.setTimestamp(self.timestamp)
        ProtoUtils.addLocalProfileKeyIfNecessary(
            forThread: thread,
            profileKeySnapshot: self.profileKey,
            dataMessageBuilder: builder,
            transaction: transaction,
        )
        builder.setFlags(UInt32(SSKProtoDataMessageFlags.profileKeyUpdate.rawValue))

        let dataProto: SSKProtoDataMessage
        do {
            dataProto = try builder.build()
        } catch {
            owsFailDebug("could not build protobuf: \(error)")
            return nil
        }
        if dataProto.profileKey == nil {
            // If we couldn't include the profile key, drop it.
            Logger.warn("Dropping profile key message without a profile key")
            return nil
        }
        return dataProto
    }

    override public var contentHint: SealedSenderContentHint { .implicit }

    override public var isUrgent: Bool { false }
}
