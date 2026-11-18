//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Represents an error encountered while making a receipt credential request.
public struct DonationReceiptCredentialRequestError: Codable, Equatable {
    public let errorCode: ReceiptCredentialRequestError.ErrorCode
    public let badgeID: String
    public let amount: FiatMoney
    public let paymentMethod: DonationPaymentMethod?
    public let creationDate: Date

    /// If our error code is `.paymentFailed`, this should hold the associated
    /// charge failure.
    public let chargeFailureCodeIfPaymentFailed: String?

    public init(
        errorCode: ReceiptCredentialRequestError.ErrorCode,
        chargeFailureCodeIfPaymentFailed: String?,
        badgeID: String,
        amount: FiatMoney,
        paymentMethod: DonationPaymentMethod?,
        now: Date,
    ) {
        owsPrecondition(
            chargeFailureCodeIfPaymentFailed == nil || errorCode == .paymentFailed,
            "Charge failure must only be populated if the error code is payment failed!",
        )

        self.errorCode = errorCode
        self.chargeFailureCodeIfPaymentFailed = chargeFailureCodeIfPaymentFailed
        self.badgeID = badgeID
        self.amount = amount
        self.paymentMethod = paymentMethod
        self.creationDate = now
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case errorCode
        case chargeFailureCodeIfPaymentFailed
        // Deserialize-only; see usage.
        case badge
        case badgeID
        case amount
        case paymentMethod
        case timestampMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawErrorCode = try container.decode(Int.self, forKey: .errorCode)
        if
            let errorCode = ReceiptCredentialRequestError.ErrorCode(
                rawValue: rawErrorCode,
            )
        {
            self.errorCode = errorCode
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [CodingKeys.errorCode],
                debugDescription: "Unexpected error code value: \(rawErrorCode)",
            ))
        }

        if let paymentMethodString = try container.decodeIfPresent(String.self, forKey: .paymentMethod) {
            guard let paymentMethod = DonationPaymentMethod(rawValue: paymentMethodString) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: [CodingKeys.paymentMethod],
                    debugDescription: "Unexpected payment method value: \(paymentMethodString)",
                ))
            }

            self.paymentMethod = paymentMethod
        } else {
            self.paymentMethod = nil
        }

        let timestampMs = try container.decode(UInt64.self, forKey: .timestampMs)
        creationDate = Date(millisecondsSince1970: timestampMs)

        if container.contains(.badgeID) {
            badgeID = try container.decode(String.self, forKey: .badgeID)
        } else {
            // In the past, we persisted this with a full ProfileBadge property.
            // We've since migrated to only storing the badge ID, but we may
            // need to decode legacy ProfileBadge objects to get their ID.
            struct LegacyProfileBadge: Decodable {
                let id: String
            }
            let legacyProfileBadge = try container.decode(LegacyProfileBadge.self, forKey: .badge)
            badgeID = legacyProfileBadge.id
        }

        amount = try container.decode(FiatMoney.self, forKey: .amount)
        chargeFailureCodeIfPaymentFailed = try container.decodeIfPresent(String.self, forKey: .chargeFailureCodeIfPaymentFailed)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(chargeFailureCodeIfPaymentFailed, forKey: .chargeFailureCodeIfPaymentFailed)
        try container.encode(badgeID, forKey: .badgeID)
        try container.encode(amount, forKey: .amount)
        try container.encode(creationDate.ows_millisecondsSince1970, forKey: .timestampMs)
        try container.encode(errorCode.rawValue, forKey: .errorCode)
        try container.encodeIfPresent(paymentMethod?.rawValue, forKey: .paymentMethod)
    }
}
