//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSLinkedDeviceReadReceipt)
final class LinkedDeviceReadReceipt: NSObject, NSSecureCoding {

    let messageUniqueId: String? // Only nil if decoding old values
    let messageIdTimestamp: UInt64
    let readTimestamp: UInt64

    let senderPhoneNumber: String?
    let senderAci: Aci?

    init(
        senderAci: Aci,
        messageUniqueId: String?,
        messageIdTimestamp: UInt64,
        readTimestamp: UInt64,
    ) {
        owsAssertDebug(messageIdTimestamp > 0)
        self.senderPhoneNumber = nil
        self.senderAci = senderAci
        self.messageUniqueId = messageUniqueId
        self.messageIdTimestamp = messageIdTimestamp
        self.readTimestamp = readTimestamp
    }

    static var supportsSecureCoding: Bool { true }

    func encode(with coder: NSCoder) {
        coder.encode(NSNumber(value: 1), forKey: "linkedDeviceReadReceiptSchemaVersion")
        coder.encode(NSNumber(value: self.messageIdTimestamp), forKey: "messageIdTimestamp")
        if let messageUniqueId {
            coder.encode(messageUniqueId, forKey: "messageUniqueId")
        }
        coder.encode(NSNumber(value: self.readTimestamp), forKey: "readTimestamp")
        if let senderPhoneNumber {
            coder.encode(senderPhoneNumber, forKey: "senderPhoneNumber")
        }
        if let senderAci {
            coder.encode(senderAci.serviceIdUppercaseString, forKey: "senderUUID")
        }
    }

    init?(coder: NSCoder) {
        let schemaVersion = coder.decodeObject(of: NSNumber.self, forKey: "linkedDeviceReadReceiptSchemaVersion")?.uintValue ?? 0
        let messageUniqueId = coder.decodeObject(of: NSString.self, forKey: "messageUniqueId") as String?

        let senderAciString = coder.decodeObject(of: NSString.self, forKey: "senderUUID") as String?
        if let senderAciString {
            guard let senderAci = Aci.parseFrom(aciString: senderAciString) else {
                return nil
            }
            self.senderAci = senderAci
        } else {
            self.senderAci = nil
        }

        // renamed timestamp -> messageIdTimestamp
        let messageIdTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "messageIdTimestamp") ?? coder.decodeObject(of: NSNumber.self, forKey: "timestamp")
        guard let messageIdTimestamp else {
            return nil
        }

        // For legacy objects, before we were tracking read time, use the original messages "sent" timestamp
        // as the local read time. This will always be at least a little bit earlier than the message was
        // actually read, which isn't ideal, but safer than persisting a disappearing message too long, especially
        // since we know they read it on their linked desktop.
        let readTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "readTimestamp") ?? messageIdTimestamp

        let senderPhoneNumber: String?
        if schemaVersion < 1 {
            senderPhoneNumber = coder.decodeObject(of: NSString.self, forKey: "senderId") as String?
            owsAssertDebug(senderPhoneNumber != nil)
        } else {
            senderPhoneNumber = coder.decodeObject(of: NSString.self, forKey: "senderPhoneNumber") as String?
        }

        self.messageUniqueId = messageUniqueId
        self.messageIdTimestamp = messageIdTimestamp.uint64Value
        self.readTimestamp = readTimestamp.uint64Value
        self.senderPhoneNumber = senderPhoneNumber
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.messageIdTimestamp)
        hasher.combine(self.messageUniqueId)
        hasher.combine(self.readTimestamp)
        hasher.combine(self.senderPhoneNumber)
        hasher.combine(self.senderAci)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.messageIdTimestamp == object.messageIdTimestamp else { return false }
        guard self.messageUniqueId == object.messageUniqueId else { return false }
        guard self.readTimestamp == object.readTimestamp else { return false }
        guard self.senderPhoneNumber == object.senderPhoneNumber else { return false }
        guard self.senderAci == object.senderAci else { return false }
        return true
    }

    var senderAddress: SignalServiceAddress {
        return SignalServiceAddress.legacyAddress(serviceId: self.senderAci, phoneNumber: self.senderPhoneNumber)
    }
}
