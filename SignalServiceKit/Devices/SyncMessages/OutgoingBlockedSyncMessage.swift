//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSBlockedPhoneNumbersMessage)
final class OutgoingBlockedSyncMessage: OutgoingSyncMessage {

    struct BlockedItem<T: Hashable>: Hashable {
        var rawValue: T
        var blockedAt: BlockedTimestamp
    }

    let phoneNumbers: [BlockedItem<String>]
    let acis: [BlockedItem<Aci>]
    let groupIds: [BlockedItem<Data>]

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(groupIds.map(\.rawValue), forKey: "groupIds")
        coder.encode(groupIds.map(\.blockedAt.rawValue), forKey: "groupIdBlockedAts")
        coder.encode(phoneNumbers.map(\.rawValue), forKey: "phoneNumbers")
        coder.encode(phoneNumbers.map(\.blockedAt.rawValue), forKey: "phoneNumberBlockedAts")
        coder.encode(acis.map(\.rawValue.serviceIdString), forKey: "uuids")
        coder.encode(acis.map(\.blockedAt.rawValue), forKey: "aciBlockedAts")
    }

    required init?(coder: NSCoder) {
        self.groupIds = Self.decodeBlockedAts(
            coder: coder,
            forKey: "groupIdBlockedAts",
            mergingWith: coder.decodeArrayOfObjects(ofClass: NSData.self, forKey: "groupIds") as [Data]? ?? [],
        )
        self.phoneNumbers = Self.decodeBlockedAts(
            coder: coder,
            forKey: "phoneNumberBlockedAts",
            mergingWith: coder.decodeArrayOfObjects(ofClass: NSString.self, forKey: "phoneNumbers") as [String]? ?? [],
        )
        let aciStrings = Self.decodeBlockedAts(
            coder: coder,
            forKey: "aciBlockedAts",
            mergingWith: coder.decodeArrayOfObjects(ofClass: NSString.self, forKey: "uuids") as [String]? ?? [],
        )
        self.acis = aciStrings.compactMap { blockedItem -> BlockedItem<Aci>? in
            guard let aci = Aci.parseFrom(aciString: blockedItem.rawValue) else {
                return nil
            }
            return BlockedItem(rawValue: aci, blockedAt: blockedItem.blockedAt)
        }
        super.init(coder: coder)
    }

    private static func decodeBlockedAts<T>(coder: NSCoder, forKey key: String, mergingWith otherElements: [T]) -> [BlockedItem<T>] {
        let numberValues = coder.decodeArrayOfObjects(ofClass: NSNumber.self, forKey: key) as [NSNumber]? ?? []
        var timestampValues = numberValues.map { BlockedTimestamp(clamping: $0.int64Value) }
        if timestampValues.count < otherElements.count {
            timestampValues += Array(repeating: .unspecified, count: otherElements.count - timestampValues.count)
        }
        return zip(otherElements, timestampValues).map { BlockedItem(rawValue: $0, blockedAt: $1) }
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.groupIds)
        hasher.combine(self.phoneNumbers)
        hasher.combine(self.acis)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.groupIds == object.groupIds else { return false }
        guard self.phoneNumbers == object.phoneNumbers else { return false }
        guard self.acis == object.acis else { return false }
        return true
    }

    init(
        localThread: TSContactThread,
        phoneNumbers: [BlockedItem<String>],
        acis: [BlockedItem<Aci>],
        groupIds: [BlockedItem<Data>],
        tx: DBReadTransaction,
    ) {
        self.phoneNumbers = phoneNumbers
        self.acis = acis
        self.groupIds = groupIds
        super.init(localThread: localThread, tx: tx)
    }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let blockedBuilder = SSKProtoSyncMessageBlocked.builder()
        blockedBuilder.setNumbers(self.phoneNumbers.map(\.rawValue))
        blockedBuilder.setBlockedE164s(self.phoneNumbers.map {
            let builder = SSKProtoSyncMessageBlockedBlockedE164.builder()
            builder.setE164($0.rawValue)
            builder.setTimestamp($0.blockedAt.asMilliseconds)
            return builder.buildInfallibly()
        })
        blockedBuilder.setAcisBinary(self.acis.map(\.rawValue.serviceIdBinary))
        blockedBuilder.setBlockedAcis(self.acis.map {
            let builder = SSKProtoSyncMessageBlockedBlockedAci.builder()
            builder.setAciBinary($0.rawValue.serviceIdBinary)
            builder.setTimestamp($0.blockedAt.asMilliseconds)
            return builder.buildInfallibly()
        })
        blockedBuilder.setGroupIds(self.groupIds.map(\.rawValue))
        blockedBuilder.setBlockedGroups(self.groupIds.map {
            let builder = SSKProtoSyncMessageBlockedBlockedGroup.builder()
            builder.setGroupID($0.rawValue)
            builder.setTimestamp($0.blockedAt.asMilliseconds)
            return builder.buildInfallibly()
        })

        let blockedProto = blockedBuilder.buildInfallibly()

        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        syncMessageBuilder.setBlocked(blockedProto)
        return syncMessageBuilder
    }

    override var isUrgent: Bool { false }
}
