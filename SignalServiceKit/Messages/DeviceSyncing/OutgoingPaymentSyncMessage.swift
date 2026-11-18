//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OutgoingPaymentSyncMessage)
public final class OutgoingPaymentSyncMessage: OutgoingSyncMessage {

    let mobileCoin: OutgoingPaymentMobileCoin

    public init(
        localThread: TSContactThread,
        mobileCoin: OutgoingPaymentMobileCoin,
        tx: DBReadTransaction,
    ) {
        self.mobileCoin = mobileCoin
        super.init(localThread: localThread, tx: tx)
    }

    override public class var supportsSecureCoding: Bool { true }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(self.mobileCoin, forKey: "mobileCoin")
    }

    public required init?(coder: NSCoder) {
        guard let mobileCoin = coder.decodeObject(of: OutgoingPaymentMobileCoin.self, forKey: "mobileCoin") else {
            return nil
        }
        self.mobileCoin = mobileCoin
        super.init(coder: coder)
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.mobileCoin)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.mobileCoin == object.mobileCoin else { return false }
        return true
    }

    override public func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        do {
            let amountPicoMob = mobileCoin.amountPicoMob
            let feePicoMob = mobileCoin.feePicoMob
            let ledgerBlockIndex = mobileCoin.blockIndex
            let spentKeyImages = mobileCoin.spentKeyImages
            let outputPublicKeys = mobileCoin.outputPublicKeys
            let receiptData = mobileCoin.receiptData
            let mobileCoinBuilder = SSKProtoSyncMessageOutgoingPaymentMobileCoin.builder(
                amountPicoMob: amountPicoMob,
                feePicoMob: feePicoMob,
                ledgerBlockIndex: ledgerBlockIndex,
            )
            mobileCoinBuilder.setSpentKeyImages(spentKeyImages)
            mobileCoinBuilder.setOutputPublicKeys(outputPublicKeys)
            if let recipientAddress = mobileCoin.recipientAddress {
                mobileCoinBuilder.setRecipientAddress(recipientAddress)
            }
            if mobileCoin.blockTimestamp > 0 {
                mobileCoinBuilder.setLedgerBlockTimestamp(mobileCoin.blockTimestamp)
            }
            mobileCoinBuilder.setReceipt(receiptData)

            let outgoingPaymentBuilder = SSKProtoSyncMessageOutgoingPayment.builder()
            if let recipientAci = mobileCoin.recipientAci {
                outgoingPaymentBuilder.setRecipientServiceID(recipientAci.serviceIdString)
            }
            outgoingPaymentBuilder.setMobileCoin(try mobileCoinBuilder.build())
            if let memoMessage = mobileCoin.memoMessage {
                outgoingPaymentBuilder.setNote(memoMessage)
            }

            let builder = SSKProtoSyncMessage.builder()
            builder.setOutgoingPayment(try outgoingPaymentBuilder.build())
            return builder
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    override public var isUrgent: Bool { false }
}
