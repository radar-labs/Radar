//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

@objc(OutgoingPaymentMobileCoin)
public final class OutgoingPaymentMobileCoin: NSObject, NSSecureCoding {

    let recipientAci: Aci?
    let recipientAddress: Data?
    let amountPicoMob: UInt64
    let feePicoMob: UInt64
    let blockIndex: UInt64
    // This property will be zero if the timestamp is unknown.
    let blockTimestamp: UInt64
    let memoMessage: String?
    let spentKeyImages: [Data]
    let outputPublicKeys: [Data]
    let receiptData: Data
    let isDefragmentation: Bool

    public init(
        recipientAci: Aci?,
        recipientAddress: Data?,
        amountPicoMob: UInt64,
        feePicoMob: UInt64,
        blockIndex: UInt64,
        blockTimestamp: UInt64,
        memoMessage: String?,
        spentKeyImages: [Data],
        outputPublicKeys: [Data],
        receiptData: Data,
        isDefragmentation: Bool,
    ) {
        self.recipientAci = recipientAci
        self.recipientAddress = recipientAddress
        self.amountPicoMob = amountPicoMob
        self.feePicoMob = feePicoMob
        self.blockIndex = blockIndex
        self.blockTimestamp = blockTimestamp
        self.memoMessage = memoMessage
        self.spentKeyImages = spentKeyImages
        self.outputPublicKeys = outputPublicKeys
        self.receiptData = receiptData
        self.isDefragmentation = isDefragmentation
        super.init()
    }

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        coder.encode(NSNumber(value: self.amountPicoMob), forKey: "amountPicoMob")
        coder.encode(NSNumber(value: self.blockIndex), forKey: "blockIndex")
        coder.encode(NSNumber(value: self.blockTimestamp), forKey: "blockTimestamp")
        coder.encode(NSNumber(value: self.feePicoMob), forKey: "feePicoMob")
        coder.encode(NSNumber(value: self.isDefragmentation), forKey: "isDefragmentation")
        if let memoMessage {
            coder.encode(memoMessage, forKey: "memoMessage")
        }
        coder.encode(self.outputPublicKeys, forKey: "outputPublicKeys")
        coder.encode(self.receiptData, forKey: "receiptData")
        if let recipientAddress {
            coder.encode(recipientAddress, forKey: "recipientAddress")
        }
        if let recipientAci {
            coder.encode(recipientAci.serviceIdUppercaseString, forKey: "recipientUuidString")
        }
        coder.encode(self.spentKeyImages, forKey: "spentKeyImages")
    }

    public init?(coder: NSCoder) {
        guard let amountPicoMob = coder.decodeObject(of: NSNumber.self, forKey: "amountPicoMob") else {
            return nil
        }
        self.amountPicoMob = amountPicoMob.uint64Value
        guard let blockIndex = coder.decodeObject(of: NSNumber.self, forKey: "blockIndex") else {
            return nil
        }
        self.blockIndex = blockIndex.uint64Value
        guard let blockTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "blockTimestamp") else {
            return nil
        }
        self.blockTimestamp = blockTimestamp.uint64Value
        guard let feePicoMob = coder.decodeObject(of: NSNumber.self, forKey: "feePicoMob") else {
            return nil
        }
        self.feePicoMob = feePicoMob.uint64Value
        guard let isDefragmentation = coder.decodeObject(of: NSNumber.self, forKey: "isDefragmentation") else {
            return nil
        }
        self.isDefragmentation = isDefragmentation.boolValue
        self.memoMessage = coder.decodeObject(of: NSString.self, forKey: "memoMessage") as String?
        guard let outputPublicKeys = coder.decodeArrayOfObjects(ofClass: NSData.self, forKey: "outputPublicKeys") as [Data]? else {
            return nil
        }
        self.outputPublicKeys = outputPublicKeys
        guard let receiptData = coder.decodeObject(of: NSData.self, forKey: "receiptData") as Data? else {
            return nil
        }
        self.receiptData = receiptData
        self.recipientAddress = coder.decodeObject(of: NSData.self, forKey: "recipientAddress") as Data?
        if let recipientAciString = coder.decodeObject(of: NSString.self, forKey: "recipientUuidString") as String? {
            guard let recipientAci = Aci.parseFrom(aciString: recipientAciString) else {
                return nil
            }
            self.recipientAci = recipientAci
        } else {
            self.recipientAci = nil
        }
        guard let spentKeyImages = coder.decodeArrayOfObjects(ofClass: NSData.self, forKey: "spentKeyImages") as [Data]? else {
            return nil
        }
        self.spentKeyImages = spentKeyImages
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.amountPicoMob)
        hasher.combine(self.blockIndex)
        hasher.combine(self.blockTimestamp)
        hasher.combine(self.feePicoMob)
        hasher.combine(self.isDefragmentation)
        hasher.combine(self.memoMessage)
        hasher.combine(self.outputPublicKeys)
        hasher.combine(self.receiptData)
        hasher.combine(self.recipientAddress)
        hasher.combine(self.recipientAci)
        hasher.combine(self.spentKeyImages)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.amountPicoMob == object.amountPicoMob else { return false }
        guard self.blockIndex == object.blockIndex else { return false }
        guard self.blockTimestamp == object.blockTimestamp else { return false }
        guard self.feePicoMob == object.feePicoMob else { return false }
        guard self.isDefragmentation == object.isDefragmentation else { return false }
        guard self.memoMessage == object.memoMessage else { return false }
        guard self.outputPublicKeys == object.outputPublicKeys else { return false }
        guard self.receiptData == object.receiptData else { return false }
        guard self.recipientAddress == object.recipientAddress else { return false }
        guard self.recipientAci == object.recipientAci else { return false }
        guard self.spentKeyImages == object.spentKeyImages else { return false }
        return true
    }
}
