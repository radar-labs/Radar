//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

struct SentSenderKey {
    var recipient: ServiceId
    var messages: [SentDeviceMessage]
}

struct OldSenderKeyStore {
    typealias DistributionId = UUID
    typealias KeyId = String

    static func buildKeyId(authorAci: Aci, distributionId: DistributionId) -> KeyId {
        return "\(authorAci.serviceIdUppercaseString).\(distributionId.uuidString)"
    }

    func resetAll(tx: DBWriteTransaction) {
        keyMetadataStore.removeAll(tx: tx)
    }

    // MARK: - Storage

    private let keyMetadataStore = NewKeyValueStore(collection: "SenderKeyStore_KeyMetadata")

    func loadSenderKey(
        forSenderAci senderAci: Aci,
        distributionId: UUID,
        tx: DBReadTransaction,
    ) -> Data? {
        let keyId = Self.buildKeyId(authorAci: senderAci, distributionId: distributionId)
        return try? getKeyMetadata(forKeyId: keyId, tx: tx)?.serializedRecord
    }

    func getKeyMetadata(forKeyId keyId: KeyId, tx: DBReadTransaction) throws -> KeyMetadata? {
        return try keyMetadataStore.fetchJSONAsValue(KeyMetadata.self, forKey: keyId, tx: tx)
    }

    func removeKeyMetadata(forKeyId keyId: KeyId, tx: DBWriteTransaction) {
        keyMetadataStore.removeValue(forKey: keyId, tx: tx)
    }
}

// MARK: -

/// Stores information about a sent SKDM
/// Currently just tracks the sent timestamp and the recipient.
struct SKDMSendInfo: Codable {
    let keyRecipient: SenderKeySentToRecipient
}

// MARK: -

struct SenderKeySentToDevice: Codable, Hashable {
    let deviceId: DeviceId
    let registrationId: UInt32
}

// MARK: -

/// Stores information about a recipient of a sender key
/// Helpful for diffing across deviceId and registrationId changes.
/// If a new device shows up, we need to make sure that we send a copy of our sender key to the address
struct SenderKeySentToRecipient: Codable {

    enum CodingKeys: String, CodingKey {
        case devices

        // We previously stored "ownerAddress" on the recipient. This is redundant
        // because "sentKeyInfo" stores the same value, and that's the one we use.
    }

    let devices: Set<SenderKeySentToDevice>

    fileprivate init(devices: Set<SenderKeySentToDevice>) {
        self.devices = devices
    }
}

// MARK: KeyMetadata

/// Stores information about a sender key, it's owner, it's distributionId, and all recipients who have been sent the sender key
struct KeyMetadata {
    let distributionId: OldSenderKeyStore.DistributionId
    @AciUuid var ownerAci: Aci
    let ownerDeviceId: DeviceId

    var keyId: String { OldSenderKeyStore.buildKeyId(authorAci: ownerAci, distributionId: distributionId) }

    let serializedRecord: Data
    let creationDate: Date
    let isForEncrypting: Bool
    let sentKeyInfo: [SignalServiceAddress: SKDMSendInfo]

    init(
        record: LibSignalClient.SenderKeyRecord,
        senderAci: Aci,
        senderDeviceId: DeviceId,
        localIdentifiers: LocalIdentifiers,
        localDeviceId: LocalDeviceId,
        distributionId: OldSenderKeyStore.DistributionId,
    ) {
        self.serializedRecord = record.serialize()
        self.distributionId = distributionId
        self._ownerAci = AciUuid(wrappedValue: senderAci)
        self.ownerDeviceId = senderDeviceId
        self.isForEncrypting = senderAci == localIdentifiers.aci && localDeviceId.equals(senderDeviceId)
        self.creationDate = Date()
        self.sentKeyInfo = [:]
    }
}

extension KeyMetadata: Codable {
    enum CodingKeys: String, CodingKey {
        case distributionId
        case ownerAci = "ownerUuid"
        case ownerDeviceId
        case serializedRecord

        case creationDate
        case sentKeyInfo
        case isForEncrypting

        enum LegacyKeys: String, CodingKey {
            case keyRecipients
            case recordData
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyValues = try decoder.container(keyedBy: CodingKeys.LegacyKeys.self)

        distributionId = try container.decode(OldSenderKeyStore.DistributionId.self, forKey: .distributionId)
        _ownerAci = try container.decode(AciUuid.self, forKey: .ownerAci)
        ownerDeviceId = try container.decode(DeviceId.self, forKey: .ownerDeviceId)
        creationDate = try container.decode(Date.self, forKey: .creationDate)
        isForEncrypting = try container.decode(Bool.self, forKey: .isForEncrypting)

        // We used to store this as an Array, but that serializes poorly in most Codable formats. Now we use Data.
        if let serializedRecord = try container.decodeIfPresent(Data.self, forKey: .serializedRecord) {
            self.serializedRecord = serializedRecord
        } else if let recordData = try legacyValues.decodeIfPresent([UInt8].self, forKey: .recordData) {
            serializedRecord = Data(recordData)
        } else {
            // We lost the entire record. "This should never happen."
            throw OWSAssertionError("failed to deserialize SenderKey record")
        }

        // There have been a few iterations of our delivery tracking. Briefly we have:
        // - V1: We just recorded a mapping from UUID -> Set<DeviceIds>
        // - V2: Record a mapping of SignalServiceAddress -> SenderKeySentToRecipient. This allowed us to
        //       track additional info about the recipient of a key like registrationId
        // - V3: Record a mapping of SignalServiceAddress -> SKDMSendInfo. This allows us to
        //       record even more information about the send that's not specific to the recipient.
        //       Right now, this is just used to record the SKDM timestamp.
        //
        // Hopefully this doesn't need to change in the future. We now have a place to hang information
        // about the recipient (SenderKeySentToRecipient) and the context of the sent SKDM (SKDMSendInfo)
        if let sendInfo = try container.decodeIfPresent([SignalServiceAddress: SKDMSendInfo].self, forKey: .sentKeyInfo) {
            sentKeyInfo = sendInfo
        } else if let keyRecipients = try legacyValues.decodeIfPresent([SignalServiceAddress: SenderKeySentToRecipient].self, forKey: .keyRecipients) {
            sentKeyInfo = keyRecipients.mapValues { SKDMSendInfo(keyRecipient: $0) }
        } else {
            // There's no way to migrate from our V1 storage. That's okay, we can just reset the dictionary. The only
            // consequence here is we'll resend an SKDM that our recipients already have. No big deal.
            sentKeyInfo = [:]
        }
    }
}
