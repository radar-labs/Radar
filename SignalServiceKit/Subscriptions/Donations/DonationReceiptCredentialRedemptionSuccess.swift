//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Represents a successful receipt credential request and the subsequent
/// redemption of that receipt credential.
///
/// These are persisted in the ``SubscriptionReceiptCredentialRequestResultStore``
/// by the ``DonationReceiptCredentialRedemptionJobQueue``.
public struct DonationReceiptCredentialRedemptionSuccess: Codable {
    public let badgesSnapshotBeforeJob: ProfileBadgesSnapshot
    public let badgeID: String
    public let paymentMethod: DonationPaymentMethod?

    public init(
        badgesSnapshotBeforeJob: ProfileBadgesSnapshot,
        badgeID: String,
        paymentMethod: DonationPaymentMethod?,
    ) {
        self.badgesSnapshotBeforeJob = badgesSnapshotBeforeJob
        self.badgeID = badgeID
        self.paymentMethod = paymentMethod
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case badgesSnapshotBeforeJob
        // Deserialize-only; see usage.
        case badge
        case badgeID
        case paymentMethod
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        badgesSnapshotBeforeJob = try container.decode(ProfileBadgesSnapshot.self, forKey: .badgesSnapshotBeforeJob)

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

        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod).map { rawValue throws in
            guard let paymentMethod = DonationPaymentMethod(rawValue: rawValue) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: [CodingKeys.paymentMethod],
                    debugDescription: "Unexpected payment method raw value: \(rawValue)",
                ))
            }

            return paymentMethod
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(badgesSnapshotBeforeJob, forKey: .badgesSnapshotBeforeJob)
        try container.encode(badgeID, forKey: .badgeID)
        try container.encodeIfPresent(paymentMethod?.rawValue, forKey: .paymentMethod)
    }
}
