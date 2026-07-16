//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
import LibSignalClient
import BreezSdkSpark

// MARK: - ParsedBreezReceipt

/// Everything Radar consumes from a payment receipt, independent of which
/// breez_sdk_spark generation serialized it.
public struct ParsedBreezReceipt {
    public let paymentId: String?
    /// The spark/lightning HTLC payment hash — mirrors `Payment.hash` semantics
    /// (nil for deposits, withdrawals, token payments).
    public let paymentHash: String?
    public let amountSats: UInt64
    public let feeSats: UInt64
    public let timestampSeconds: UInt64
    public let isFailed: Bool

    /// Sats amount under the name display call sites already use.
    /// (This fork stores sats in fields named `picoMob`/`value`; picoMobPerSatoshi == 1.)
    public var value: UInt64 { amountSats }

    public var tsPaymentAmount: TSPaymentAmount {
        TSPaymentAmount(currency: .bitcoin, picoMob: amountSats)
    }
}

// MARK: - BreezReceiptParser

/// Decodes a payment receipt blob from any known generation.
///
/// Receipts are uniffi-serialized `LnurlPayResponse` values, and uniffi's wire format is
/// positional and NOT stable across breez_sdk_spark releases: 0.18.0 added a trailing field to
/// `PaymentDetails.lightning`, so 0.18.0 cannot read 0.14.0 blobs (it runs off the end of the
/// buffer). A receipt travels from the sender's build to the receiver's build, so both layouts
/// exist in the wild and both must stay readable — an unreadable receipt is what rendered
/// received payments as "UNAVAILABLE sats".
///
/// Android additionally appends a version-stable proto tail after the uniffi bytes
/// (`RDRCPT01` magic, see the Android `ReceiptCodec`); positional readers ignore trailing
/// bytes, so those blobs parse here through the uniffi branch unchanged.
public enum BreezReceiptParser {

    /// Parses `data` as the current SDK's layout, then as the frozen 0.14.0 layout.
    /// Returns nil only when no known generation can read it — callers must treat
    /// that as a skip, never a fatal error.
    public static func parse(_ data: Data?) -> ParsedBreezReceipt? {
        guard let data, !data.isEmpty else { return nil }
        if let receipt = parseCurrentSdkLayout(data) {
            return receipt
        }
        return Breez014ReceiptReader.read(data)
    }

    private static func parseCurrentSdkLayout(_ data: Data) -> ParsedBreezReceipt? {
        var input = (data: data, offset: 0)
        guard let response = try? FfiConverterTypeLnurlPayResponse.read(from: &input) else {
            return nil
        }
        let payment = response.payment
        // U128 (BInt) → UInt64 via its decimal text: non-trapping, and receipts hold
        // sat amounts, which are far below UInt64.max.
        guard
            let amountSats = UInt64(payment.amount.description),
            let feeSats = UInt64(payment.fees.description)
        else {
            return nil
        }
        return ParsedBreezReceipt(
            paymentId: payment.id,
            paymentHash: payment.hash,
            amountSats: amountSats,
            feeSats: feeSats,
            timestampSeconds: payment.timestamp,
            isFailed: payment.status == .failed
        )
    }
}

// MARK: - Breez014ReceiptReader

/// Frozen, read-only decoder for `LnurlPayResponse` blobs serialized by **breez_sdk_spark
/// 0.14.0** — receipts from senders on old-breez builds. The current bindings cannot read them.
///
/// The layout was derived from the real 0.14.0 bindings and is pinned by golden blobs those
/// bindings produced (uniffi's wire format is language-independent, so old-iOS and old-Android
/// senders emit identical bytes). NEVER update this to a newer SDK layout — it exists precisely
/// to keep the 0.14.0 generation readable. Newer generations are handled by the SDK itself.
///
/// uniffi encoding (all big-endian): String = i32 length + UTF-8; u128 = String holding the
/// decimal value; Option<T> = flag byte (0/1) + T; enum = i32, 1-based; bool = 1 byte.
///
/// ```
/// LnurlPayResponse = Payment, Opt<SuccessActionProcessed>
/// Payment          = id:Str, paymentType:Enum(2), status:Enum(3), amount:u128, fees:u128,
///                    timestamp:u64, method:Enum(6), Opt<PaymentDetails>, Opt<ConversionDetails>
/// PaymentDetails   = variant:i32 of
///   1 spark     = Opt<SparkInvoicePaymentDetails>, Opt<SparkHtlcDetails>, Opt<ConversionInfo>
///   2 token     = TokenMetadata, txHash:Str, txType:Enum(3), Opt<SparkInvoicePaymentDetails>, Opt<ConversionInfo>
///   3 lightning = Opt<Str>, invoice:Str, destinationPubkey:Str, SparkHtlcDetails,
///                 Opt<LnurlPayInfo>, Opt<LnurlWithdrawInfo:Str>, Opt<LnurlReceiveMetadata>
///   4 withdraw  = txId:Str
///   5 deposit   = txId:Str
/// SparkInvoicePaymentDetails = Opt<Str>, Str
/// SparkHtlcDetails           = paymentHash:Str, Opt<Str>, expiryTime:u64, status:Enum(3)
/// TokenMetadata              = Str, Str, Str, Str, decimals:i32, maxSupply:u128, bool
/// ConversionInfo             = Str, Str, status:Enum(5), Opt<u128>, Opt<ConversionPurpose>, Opt<Enum(2)>
/// ConversionPurpose          = variant:i32 of 1:{Str}, 2:{}, 3:{}
/// ConversionDetails          = status:Enum(5), Opt<ConversionStep>, Opt<ConversionStep>
/// ConversionStep             = Str, u128, u128, method:Enum(6), Opt<TokenMetadata>, Opt<Enum(2)>
/// LnurlPayInfo               = Opt<Str> x4, Opt<SuccessActionProcessed>, Opt<SuccessAction>
/// LnurlReceiveMetadata       = Opt<Str> x3
/// SuccessActionProcessed     = variant:i32 of 1 aes:{AesResult}, 2 message:{Str}, 3 url:{UrlData}
/// AesResult                  = variant:i32 of 1 decrypted:{Str,Str}, 2 errorStatus:{Str}
/// SuccessAction              = variant:i32 of 1 aes:{Str,Str,Str}, 2 message:{Str}, 3 url:{UrlData}
/// UrlData                    = Str, Str, bool
/// ```
enum Breez014ReceiptReader {

    /// Parses `data` as a 0.14.0-layout blob, returning nil on any structural anomaly.
    /// Trailing bytes are permitted by design: pre-fix Android stored uniffi's worst-case
    /// allocation (zero padding), and Android's current format appends a proto tail.
    static func read(_ data: Data) -> ParsedBreezReceipt? {
        return try? Walker(data).readLnurlPayResponse()
    }

    private enum BadLayout: Error {
        case bad
    }

    private final class Walker {
        /// Bounds string allocations against garbage that parses as a huge length.
        private static let maxStringBytes = 1 << 20

        private let bytes: [UInt8]
        private var index = 0

        init(_ data: Data) {
            self.bytes = [UInt8](data)
        }

        func readLnurlPayResponse() throws -> ParsedBreezReceipt {
            // Payment
            let paymentId = try str()
            _ = try enumValue(max: 2) // paymentType
            let status = try enumValue(max: 3) // 1 completed, 2 pending, 3 failed
            let amount = try u128()
            let fees = try u128()
            let timestamp = try u64()
            _ = try enumValue(max: 6) // method

            var paymentHash: String?
            try opt { // details
                switch try self.enumValue(max: 5) {
                case 1: // spark
                    try self.opt { try self.sparkInvoicePaymentDetails() }
                    try self.opt { paymentHash = try self.sparkHtlcDetails() }
                    try self.opt { try self.conversionInfo() }
                case 2: // token
                    try self.tokenMetadata()
                    _ = try self.str() // txHash
                    _ = try self.enumValue(max: 3) // txType
                    try self.opt { try self.sparkInvoicePaymentDetails() }
                    try self.opt { try self.conversionInfo() }
                case 3: // lightning
                    try self.opt { _ = try self.str() } // description
                    _ = try self.str() // invoice
                    _ = try self.str() // destinationPubkey
                    paymentHash = try self.sparkHtlcDetails()
                    try self.opt { try self.lnurlPayInfo() }
                    try self.opt { _ = try self.str() } // LnurlWithdrawInfo
                    try self.opt { try self.lnurlReceiveMetadata() }
                default: // 4 withdraw, 5 deposit — txId; Payment.hash semantics keep these nil
                    _ = try self.str()
                }
            }
            try opt { try self.conversionDetails() }
            try opt { try self.successActionProcessed() }
            // Trailing bytes are allowed; do not require exact consumption.

            guard
                let amountSats = UInt64(amount),
                let feeSats = UInt64(fees)
            else {
                throw BadLayout.bad
            }
            return ParsedBreezReceipt(
                paymentId: paymentId,
                paymentHash: paymentHash,
                amountSats: amountSats,
                feeSats: feeSats,
                timestampSeconds: timestamp,
                isFailed: status == 3
            )
        }

        /// - Returns: the paymentHash
        private func sparkHtlcDetails() throws -> String {
            let paymentHash = try str()
            try opt { _ = try self.str() } // preimage
            _ = try u64() // expiryTime
            _ = try enumValue(max: 3) // status
            return paymentHash
        }

        private func sparkInvoicePaymentDetails() throws {
            try opt { _ = try self.str() }
            _ = try str()
        }

        private func tokenMetadata() throws {
            _ = try str(); _ = try str(); _ = try str(); _ = try str()
            _ = try i32() // decimals
            _ = try u128() // maxSupply
            try bool()
        }

        private func conversionInfo() throws {
            _ = try str(); _ = try str()
            _ = try enumValue(max: 5) // status
            try opt { _ = try self.u128() }
            try opt { try self.conversionPurpose() }
            try opt { _ = try self.enumValue(max: 2) } // AmountAdjustmentReason
        }

        private func conversionPurpose() throws {
            if try enumValue(max: 3) == 1 {
                _ = try str() // ongoingPayment(paymentId); variants 2/3 carry no fields
            }
        }

        private func conversionDetails() throws {
            _ = try enumValue(max: 5) // status
            try opt { try self.conversionStep() }
            try opt { try self.conversionStep() }
        }

        private func conversionStep() throws {
            _ = try str()
            _ = try u128()
            _ = try u128()
            _ = try enumValue(max: 6) // method
            try opt { try self.tokenMetadata() }
            try opt { _ = try self.enumValue(max: 2) } // AmountAdjustmentReason
        }

        private func lnurlPayInfo() throws {
            try opt { _ = try self.str() }
            try opt { _ = try self.str() }
            try opt { _ = try self.str() }
            try opt { _ = try self.str() }
            try opt { try self.successActionProcessed() }
            try opt { try self.successAction() }
        }

        private func lnurlReceiveMetadata() throws {
            try opt { _ = try self.str() }
            try opt { _ = try self.str() }
            try opt { _ = try self.str() }
        }

        private func successActionProcessed() throws {
            switch try enumValue(max: 3) {
            case 1: try aesResult()
            case 2: _ = try str() // MessageSuccessActionData
            default: try urlData() // 3
            }
        }

        private func aesResult() throws {
            switch try enumValue(max: 2) {
            case 1: _ = try str(); _ = try str() // decrypted(description, plaintext)
            default: _ = try str() // 2 errorStatus(reason)
            }
        }

        private func successAction() throws {
            switch try enumValue(max: 3) {
            case 1: _ = try str(); _ = try str(); _ = try str() // AesSuccessActionData
            case 2: _ = try str() // MessageSuccessActionData
            default: try urlData() // 3
            }
        }

        private func urlData() throws {
            _ = try str()
            _ = try str()
            try bool()
        }

        // MARK: Primitives

        private func byte() throws -> UInt8 {
            guard index < bytes.count else { throw BadLayout.bad }
            defer { index += 1 }
            return bytes[index]
        }

        private func i32() throws -> Int {
            guard index + 4 <= bytes.count else { throw BadLayout.bad }
            var value: Int32 = 0
            for _ in 0..<4 {
                value = (value << 8) | Int32(bytes[index])
                index += 1
            }
            return Int(value)
        }

        private func u64() throws -> UInt64 {
            guard index + 8 <= bytes.count else { throw BadLayout.bad }
            var value: UInt64 = 0
            for _ in 0..<8 {
                value = (value << 8) | UInt64(bytes[index])
                index += 1
            }
            return value
        }

        private func bool() throws {
            guard try byte() <= 1 else { throw BadLayout.bad }
        }

        /// uniffi Option flag: strictly 0 or 1 — anything else means we are reading garbage.
        private func opt(_ readValue: () throws -> Void) throws {
            switch try byte() {
            case 0: return
            case 1: try readValue()
            default: throw BadLayout.bad
            }
        }

        /// 1-based uniffi enum index, validated against the 0.14.0 variant count.
        private func enumValue(max: Int) throws -> Int {
            let value = try i32()
            guard value >= 1, value <= max else { throw BadLayout.bad }
            return value
        }

        private func str() throws -> String {
            let length = try i32()
            guard length >= 0, length <= Self.maxStringBytes, index + length <= bytes.count else {
                throw BadLayout.bad
            }
            defer { index += length }
            guard let string = String(bytes: bytes[index..<(index + length)], encoding: .utf8) else {
                throw BadLayout.bad
            }
            return string
        }

        /// breez encodes u128 as its decimal-string form.
        private func u128() throws -> String {
            let text = try str()
            guard !text.isEmpty, text.count <= 40, text.allSatisfy({ $0.isNumber }) else {
                throw BadLayout.bad
            }
            return text
        }
    }
}

// MARK: - Incoming payment model construction

extension TSPaymentNotification {
    /// Parses this notification's receipt under any known breez layout and builds the incoming
    /// `TSPaymentModel` exactly as the receive path does. Returns nil when the receipt is
    /// undecodable — callers must treat that as a skip.
    func buildIncomingPaymentModel(senderAci: Aci, isUnread: Bool) -> TSPaymentModel? {
        guard let receipt = BreezReceiptParser.parse(mcReceiptData) else {
            return nil
        }
        let incomingTransactionPublicKeys: [Data]
        if let hashData = receipt.paymentHash?.data(using: .utf8) {
            incomingTransactionPublicKeys = [hashData]
        } else {
            incomingTransactionPublicKeys = []
        }
        let mobileCoin = MobileCoinPayment(recipientPublicAddressData: nil,
                                           transactionData: nil,
                                           receiptData: mcReceiptData,
                                           incomingTransactionPublicKeys: incomingTransactionPublicKeys,
                                           spentKeyImages: nil,
                                           outputPublicKeys: nil,
                                           ledgerBlockTimestamp: 0,
                                           ledgerBlockIndex: 0,
                                           feeAmount: nil)
        return TSPaymentModel(paymentType: .incomingPayment,
                              paymentState: .incomingUnverified,
                              paymentAmount: receipt.tsPaymentAmount,
                              createdDate: Date(timeIntervalSince1970: TimeInterval(receipt.timestampSeconds)),
                              senderOrRecipientAci: AciObjC(senderAci),
                              memoMessage: memoMessage?.nilIfEmpty,
                              isUnread: isUnread,
                              interactionUniqueId: nil,
                              mobileCoin: mobileCoin)
    }
}

// MARK: - BreezPaymentBackfill

/// One-shot repair: builds that could not decode a cross-version receipt inserted the chat
/// message but never created its `TSPaymentModel`, leaving the payment out of the wallet
/// history (and its bubble showing "UNAVAILABLE sats"). Now that `BreezReceiptParser` reads
/// every known layout, re-walk the incoming payment messages and create the missing models.
public enum BreezPaymentBackfill {

    private static let store = KeyValueStore(collection: "BreezPaymentBackfill")
    private static let didRunKey = "didBackfillIncomingPaymentModels1"

    /// Call once the app is ready. Cheap when already done (single KV read).
    public static func runIfNeeded() {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let didRun = databaseStorage.read { store.getBool(didRunKey, defaultValue: false, transaction: $0) }
        guard !didRun else {
            return
        }
        databaseStorage.asyncWrite { transaction in
            backfill(transaction: transaction)
            store.setBool(true, key: didRunKey, transaction: transaction)
        }
    }

    private static func backfill(transaction: DBWriteTransaction) {
        let sql = """
        SELECT * FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .recordType) = ?
        """
        let cursor = TSInteraction.grdbFetchCursor(sql: sql,
                                                   arguments: [SDSRecordType.incomingPaymentMessage.rawValue],
                                                   transaction: transaction)
        var repaired = 0
        var skipped = 0
        do {
            while let interaction = try cursor.next() {
                autoreleasepool {
                    guard
                        let message = interaction as? OWSIncomingPaymentMessage,
                        let paymentNotification = message.paymentNotification,
                        let senderAci = message.authorAddress.aci
                    else {
                        return
                    }
                    guard PaymentFinder.paymentModels(forMcReceiptData: paymentNotification.mcReceiptData,
                                                      transaction: transaction).isEmpty else {
                        return // Model already exists; nothing to repair.
                    }
                    // isUnread false: these payments were already seen in the chat; repairing
                    // them must not re-badge the app.
                    guard
                        let paymentModel = paymentNotification.buildIncomingPaymentModel(senderAci: senderAci, isUnread: false),
                        paymentModel.isValid
                    else {
                        skipped += 1
                        return
                    }
                    paymentModel.anyInsert(transaction: transaction)
                    repaired += 1
                }
            }
        } catch {
            owsFailDebug("Error enumerating incoming payment messages: \(error)")
        }
        Logger.info("Backfilled \(repaired) incoming payment model(s); \(skipped) receipt(s) undecodable.")
    }
}
