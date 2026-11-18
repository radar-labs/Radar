//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(MobileCoinPayment)
public final class MobileCoinPayment: NSObject, NSSecureCoding {

    // This property is only used for transfer in/out flows.
    public let recipientPublicAddressData: Data?

    // Optional. Only set for outgoing mobileCoin payments.
    public let transactionData: Data?

    // Optional. Set for incoming and outgoing mobileCoin payments.
    public let receiptData: Data?

    // Optional. Set for incoming and outgoing mobileCoin payments.
    public let incomingTransactionPublicKeys: [Data]?

    // The image keys for the TXOs spent in this outgoing MC transaction.
    public let spentKeyImages: [Data]?

    // The TXOs spent in this outgoing MC transaction.
    public let outputPublicKeys: [Data]?

    // This value is zero if not set.
    public let ledgerBlockTimestamp: UInt64

    // This value is zero if not set.
    //
    // This only applies to mobilecoin.
    public let ledgerBlockIndex: UInt64

    // Optional. Only set for outgoing mobileCoin payments.
    public let feeAmount: TSPaymentAmount?

    public init(
        recipientPublicAddressData: Data?,
        transactionData: Data?,
        receiptData: Data?,
        incomingTransactionPublicKeys: [Data]?,
        spentKeyImages: [Data]?,
        outputPublicKeys: [Data]?,
        ledgerBlockTimestamp: UInt64,
        ledgerBlockIndex: UInt64,
        feeAmount: TSPaymentAmount?,
    ) {
        self.recipientPublicAddressData = recipientPublicAddressData
        self.transactionData = transactionData
        self.receiptData = receiptData
        self.incomingTransactionPublicKeys = incomingTransactionPublicKeys
        self.spentKeyImages = spentKeyImages
        self.outputPublicKeys = outputPublicKeys
        self.ledgerBlockTimestamp = ledgerBlockTimestamp
        self.ledgerBlockIndex = ledgerBlockIndex
        self.feeAmount = feeAmount
    }

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        if let recipientPublicAddressData {
            coder.encode(recipientPublicAddressData, forKey: "recipientPublicAddressData")
        }
        if let transactionData {
            coder.encode(transactionData, forKey: "transactionData")
        }
        if let receiptData {
            coder.encode(receiptData, forKey: "receiptData")
        }
        if let incomingTransactionPublicKeys {
            coder.encode(incomingTransactionPublicKeys, forKey: "incomingTransactionPublicKeys")
        }
        if let spentKeyImages {
            coder.encode(spentKeyImages, forKey: "spentKeyImages")
        }
        if let outputPublicKeys {
            coder.encode(outputPublicKeys, forKey: "outputPublicKeys")
        }
        coder.encode(NSNumber(value: self.ledgerBlockTimestamp), forKey: "ledgerBlockTimestamp")
        coder.encode(NSNumber(value: self.ledgerBlockIndex), forKey: "ledgerBlockIndex")
        if let feeAmount {
            coder.encode(feeAmount, forKey: "feeAmount")
        }
    }

    public init?(coder: NSCoder) {
        self.feeAmount = coder.decodeObject(of: TSPaymentAmount.self, forKey: "feeAmount")
        self.incomingTransactionPublicKeys = coder.decodeArrayOfObjects(ofClass: NSData.self, forKey: "incomingTransactionPublicKeys") as [Data]?
        self.ledgerBlockIndex = coder.decodeObject(of: NSNumber.self, forKey: "ledgerBlockIndex")?.uint64Value ?? 0
        self.ledgerBlockTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "ledgerBlockTimestamp")?.uint64Value ?? 0
        self.outputPublicKeys = coder.decodeArrayOfObjects(ofClass: NSData.self, forKey: "outputPublicKeys") as [Data]?
        self.receiptData = coder.decodeObject(of: NSData.self, forKey: "receiptData") as Data?
        self.recipientPublicAddressData = coder.decodeObject(of: NSData.self, forKey: "recipientPublicAddressData") as Data?
        self.spentKeyImages = coder.decodeArrayOfObjects(ofClass: NSData.self, forKey: "spentKeyImages") as [Data]?
        self.transactionData = coder.decodeObject(of: NSData.self, forKey: "transactionData") as Data?
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.feeAmount)
        hasher.combine(self.incomingTransactionPublicKeys)
        hasher.combine(self.ledgerBlockIndex)
        hasher.combine(self.ledgerBlockTimestamp)
        hasher.combine(self.outputPublicKeys)
        hasher.combine(self.receiptData)
        hasher.combine(self.recipientPublicAddressData)
        hasher.combine(self.spentKeyImages)
        hasher.combine(self.transactionData)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.feeAmount == object.feeAmount else { return false }
        guard self.incomingTransactionPublicKeys == object.incomingTransactionPublicKeys else { return false }
        guard self.ledgerBlockIndex == object.ledgerBlockIndex else { return false }
        guard self.ledgerBlockTimestamp == object.ledgerBlockTimestamp else { return false }
        guard self.outputPublicKeys == object.outputPublicKeys else { return false }
        guard self.receiptData == object.receiptData else { return false }
        guard self.recipientPublicAddressData == object.recipientPublicAddressData else { return false }
        guard self.spentKeyImages == object.spentKeyImages else { return false }
        guard self.transactionData == object.transactionData else { return false }
        return true
    }

    public var ledgerBlockDate: Date? {
        if self.ledgerBlockTimestamp > 0 {
            return Date(millisecondsSince1970: self.ledgerBlockTimestamp)
        } else {
            return nil
        }
    }

    static func copy(_ oldCopy: MobileCoinPayment?, withLedgerBlockIndex ledgerBlockIndex: UInt64) -> MobileCoinPayment {
        owsAssertDebug(ledgerBlockIndex > 0)
        return MobileCoinPayment(
            recipientPublicAddressData: oldCopy?.recipientPublicAddressData,
            transactionData: oldCopy?.transactionData,
            receiptData: oldCopy?.receiptData,
            incomingTransactionPublicKeys: oldCopy?.incomingTransactionPublicKeys,
            spentKeyImages: oldCopy?.spentKeyImages,
            outputPublicKeys: oldCopy?.outputPublicKeys,
            ledgerBlockTimestamp: oldCopy?.ledgerBlockTimestamp ?? 0,
            ledgerBlockIndex: ledgerBlockIndex,
            feeAmount: oldCopy?.feeAmount,
        )
    }

    static func copy(_ oldCopy: MobileCoinPayment?, withLedgerBlockTimestamp ledgerBlockTimestamp: UInt64) -> MobileCoinPayment {
        owsAssertDebug(ledgerBlockTimestamp > 0)
        return MobileCoinPayment(
            recipientPublicAddressData: oldCopy?.recipientPublicAddressData,
            transactionData: oldCopy?.transactionData,
            receiptData: oldCopy?.receiptData,
            incomingTransactionPublicKeys: oldCopy?.incomingTransactionPublicKeys,
            spentKeyImages: oldCopy?.spentKeyImages,
            outputPublicKeys: oldCopy?.outputPublicKeys,
            ledgerBlockTimestamp: ledgerBlockTimestamp,
            ledgerBlockIndex: oldCopy?.ledgerBlockIndex ?? 0,
            feeAmount: oldCopy?.feeAmount,
        )
    }
}
