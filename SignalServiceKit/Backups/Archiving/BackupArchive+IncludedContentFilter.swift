//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension BackupArchive {

    struct IncludedContentFilter {
        /// The minimum absolute expiration time for a message, such that it
        /// is eligible for inclusion.
        ///
        /// For example, a value of 24h will exclude messages with a
        /// "lifetime" of a day or less, regardless of whether they have
        /// been read and their expiration timer has started.
        let minExpirationTimeMs: UInt64

        /// The minimum remaining time before a message will expire, such
        /// that it is eligible for inclusion.
        ///
        /// For example, a value of 24h will exclude messages that will
        /// expire in the next day, regardless of how long their original
        /// "lifetime" was.
        let minRemainingTimeUntilExpirationMs: UInt64

        /// Unviewed view-once messages should be treated as viewed and
        /// tombstoned for this export.
        let shouldTombstoneViewOnce: Bool

        /// Whether or not the plaintext SVR PIN should be included.
        let shouldIncludePin: Bool

        // MARK: -

        init(
            minExpirationTimeMs: UInt64,
            minRemainingTimeUntilExpirationMs: UInt64,
            shouldTombstoneViewOnce: Bool,
            shouldIncludePin: Bool = true,
        ) {
            self.minExpirationTimeMs = minExpirationTimeMs
            self.minRemainingTimeUntilExpirationMs = minRemainingTimeUntilExpirationMs
            self.shouldTombstoneViewOnce = shouldTombstoneViewOnce
            self.shouldIncludePin = shouldIncludePin
        }

        /// A filter for the ephemeral Backup used during LinkAndSync. Includes
        /// all messages.
        static let linkAndSync = IncludedContentFilter(
            minExpirationTimeMs: 0,
            minRemainingTimeUntilExpirationMs: 0,
            shouldTombstoneViewOnce: false,
        )

        /// A filter for Backups being uploaded remotely. Excludes messages
        /// disappearing in the next day.
        static let remoteBackup = IncludedContentFilter(
            // Skip messages with timers of less than a day.
            minExpirationTimeMs: .dayInMs,
            // Skip messages with less than a day before they'll expire.
            minRemainingTimeUntilExpirationMs: .dayInMs,
            shouldTombstoneViewOnce: true,
        )

        /// A filter for plaintext takeouts. Excludes all disappearing messages.
        ///
        /// - Note
        /// This filtering matches what LibSignal's JSON exporter sanitizes.
        /// Filtering it ourselves makes it easier to skip attachments belonging
        /// to messages the sanitization would filter out.
        static let plaintextTakeout = IncludedContentFilter(
            // Skip all expiring messages.
            minExpirationTimeMs: .max,
            minRemainingTimeUntilExpirationMs: 0,
            shouldTombstoneViewOnce: true,
        )

        // MARK: -

        func shouldSkipMessage(
            expirationDetails: ChatItemExpirationDetails,
            currentTimestamp: UInt64,
        ) -> Bool {
            let expiresInMs = expirationDetails.expiresInMs
            let expireStartDate = expirationDetails.expireStartDate

            guard expiresInMs > 0 else {
                // If the message isn't expiring, no reason to skip.
                return false
            }

            if expiresInMs <= self.minExpirationTimeMs {
                // If the expire timer was less than our minimum, we can always skip.
                return true
            } else if let expireStartDate, expireStartDate > 0 {
                // If the expiration timer has started, check whether the
                // remaining time before it expires is sufficient.
                let expirationDate = expireStartDate + expiresInMs
                let minExpirationDate = currentTimestamp + self.minRemainingTimeUntilExpirationMs
                return expirationDate <= minExpirationDate
            } else {
                return false
            }
        }

        /// If this returns true, we will skip scheduling a media tier upload for the
        /// attachment with respect to this owning messager. If the attachment has
        /// other owners (e.g. if deduplicated by content hash), it may still be uploaded.
        func shouldSkipAttachment(
            owningMessage: TSMessage,
            currentTimestamp: UInt64,
        ) -> Bool {
            if
                shouldSkipMessage(
                    expirationDetails: ChatItemExpirationDetails(expiringInteraction: owningMessage),
                    currentTimestamp: currentTimestamp,
                )
            {
                return true
            }
            if
                owningMessage.isViewOnceMessage,
                shouldTombstoneViewOnce
            {
                return true
            }
            return false
        }
    }
}
