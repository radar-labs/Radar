//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc(OWSLinkedDeviceViewedReceipt)
final class LinkedDeviceViewedReceipt: NSObject, NSSecureCoding {

    let messageUniqueId: String? // Only nil if decoding old values
    let messageIdTimestamp: UInt64
    let viewedTimestamp: UInt64

    let senderPhoneNumber: String?
    let senderAci: Aci?

    init(
        senderAci: Aci,
        messageUniqueId: String?,
        messageIdTimestamp: UInt64,
        viewedTimestamp: UInt64,
    ) {
        owsAssertDebug(messageIdTimestamp > 0)
        self.senderPhoneNumber = nil
        self.senderAci = senderAci
        self.messageUniqueId = messageUniqueId
        self.messageIdTimestamp = messageIdTimestamp
        self.viewedTimestamp = viewedTimestamp
    }

    static var supportsSecureCoding: Bool { true }

    func encode(with coder: NSCoder) {
        coder.encode(NSNumber(value: self.messageIdTimestamp), forKey: "messageIdTimestamp")
        if let messageUniqueId {
            coder.encode(messageUniqueId, forKey: "messageUniqueId")
        }
        if let senderPhoneNumber {
            coder.encode(senderPhoneNumber, forKey: "senderPhoneNumber")
        }
        if let senderAci {
            coder.encode(senderAci.serviceIdUppercaseString, forKey: "senderUUID")
        }
        coder.encode(NSNumber(value: self.viewedTimestamp), forKey: "viewedTimestamp")
    }

    init?(coder: NSCoder) {
        guard let messageIdTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "messageIdTimestamp") else {
            return nil
        }
        self.messageIdTimestamp = messageIdTimestamp.uint64Value
        self.messageUniqueId = coder.decodeObject(of: NSString.self, forKey: "messageUniqueId") as String?
        self.senderPhoneNumber = coder.decodeObject(of: NSString.self, forKey: "senderPhoneNumber") as String?
        let senderAciString = coder.decodeObject(of: NSString.self, forKey: "senderUUID") as String?
        if let senderAciString {
            guard let senderAci = Aci.parseFrom(aciString: senderAciString) else {
                return nil
            }
            self.senderAci = senderAci
        } else {
            self.senderAci = nil
        }
        guard let viewedTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "viewedTimestamp") else {
            return nil
        }
        self.viewedTimestamp = viewedTimestamp.uint64Value
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.messageIdTimestamp)
        hasher.combine(self.messageUniqueId)
        hasher.combine(self.senderPhoneNumber)
        hasher.combine(self.senderAci)
        hasher.combine(self.viewedTimestamp)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.messageIdTimestamp == object.messageIdTimestamp else { return false }
        guard self.messageUniqueId == object.messageUniqueId else { return false }
        guard self.senderPhoneNumber == object.senderPhoneNumber else { return false }
        guard self.senderAci == object.senderAci else { return false }
        guard self.viewedTimestamp == object.viewedTimestamp else { return false }
        return true
    }

    var senderAddress: SignalServiceAddress {
        return SignalServiceAddress.legacyAddress(serviceId: self.senderAci, phoneNumber: self.senderPhoneNumber)
    }
}
