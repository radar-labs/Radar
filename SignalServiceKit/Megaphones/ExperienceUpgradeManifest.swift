//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

public enum ExperienceUpgradeManifest: Codable, Equatable, Hashable {
    /// Informs the user that a new device was linked if they have
    /// notifications disabled.
    /// See ``NotificationPresenterImpl/scheduleNotifyForNewLinkedDevice(deviceLinkTimestamp:)``
    /// for when notifications are enabled.
    case newLinkedDeviceNotification

    /// Prompts the user to create a PIN, if they did not create one during
    /// registration.
    ///
    /// Skipping a PIN is not user-selectable during registration, but is
    /// possible if KBS returned errors.
    case introducingPins

    /// Prompts the user to enable notifications permissions.
    case notificationPermissionReminder

    /// Prompts the user to create a username.
    case createUsernameReminder

    /// Prompts the user according to the contained ``RemoteMegaphoneModel``.
    ///
    /// Remote megaphones are fetched from the service, and expected to change
    /// over time.
    case remoteMegaphone(megaphone: RemoteMegaphoneModel)

    /// Prompts the user about any "inactive" linked devices that will expire
    /// soon.
    case inactiveLinkedDeviceReminder

    /// Prompts the user on linked devices about any "inactive" primary devices
    /// that will expire soon
    case inactivePrimaryDeviceReminder

    /// Prompts the user to enter their PIN, to help ensure they remember it.
    ///
    /// Note that this upgrade stores state in external components, rather than
    /// in an ``ExperienceUpgrade``.
    case pinReminder

    /// Prompts the user to enable contacts permissions.
    case contactPermissionReminder

    /// Prompts the user to enter their recovery key, to help ensure they remember it.
    case recoveryKeyReminder

    /// Prompts the user to enable backups.
    case backupsUpsellReminder

    /// Notifies the user backups were enabled.
    case backupsEnabledRecentlyNotification

    /// An unrecognized upgrade, which should generally be ignored/discarded.
    ///
    /// This may represent a persisted ``ExperienceUpgrade`` record which refers
    /// to an upgrade that has since been removed.
    case unrecognized(uniqueId: String)

    // MARK: - Codable

    public enum CodingKeys: String, CodingKey {
        /// Keys to the unique ID identifying a manifest.
        case uniqueId
        /// Keys to the remote megaphone for a manifest. Only present if the
        /// manifest represents a remote megaphone.
        case remoteMegaphone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let persistedUniqueId = try container.decode(String.self, forKey: .uniqueId)
        let persistedRemoteMegaphone = try container.decodeIfPresent(RemoteMegaphoneModel.self, forKey: .remoteMegaphone)

        self.init(uniqueId: persistedUniqueId, remoteMegaphone: persistedRemoteMegaphone)

        owsAssertDebug(uniqueId == persistedUniqueId, "Persisted unique ID does not match deserialized model!")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(uniqueId, forKey: .uniqueId)

        if case .remoteMegaphone(let megaphone) = self {
            try container.encode(megaphone, forKey: .remoteMegaphone)
        }
    }

    // MARK: - From persisted unique IDs

    /// Instantiate an ``ExperienceUpgradeManifest`` from the unique ID of a
    /// persisted ``ExperienceUpgrade`` which does not have a manifest.
    ///
    /// This is only relevant for ``ExperienceUpgrade``s that were persisted
    /// before the ``ExperienceUpgradeManifest`` was added.
    static func makeLegacy(fromPersistedExperienceUpgradeUniqueId uniqueId: String) -> ExperienceUpgradeManifest {
        ExperienceUpgradeManifest(uniqueId: uniqueId, remoteMegaphone: nil)
    }

    private init(uniqueId: String, remoteMegaphone: RemoteMegaphoneModel?) {
        self = {
            switch uniqueId {
            case Self.introducingPins.uniqueId:
                return .introducingPins
            case Self.notificationPermissionReminder.uniqueId:
                return .notificationPermissionReminder
            case Self.createUsernameReminder.uniqueId:
                return .createUsernameReminder
            case Self.inactiveLinkedDeviceReminder.uniqueId:
                return .inactiveLinkedDeviceReminder
            case Self.inactivePrimaryDeviceReminder.uniqueId:
                return .inactivePrimaryDeviceReminder
            case Self.pinReminder.uniqueId:
                return .pinReminder
            case Self.contactPermissionReminder.uniqueId:
                return .contactPermissionReminder
            case Self.recoveryKeyReminder.uniqueId:
                return .recoveryKeyReminder
            case Self.backupsUpsellReminder.uniqueId:
                return .backupsUpsellReminder
            case Self.backupsEnabledRecentlyNotification.uniqueId:
                return .backupsEnabledRecentlyNotification
            default:
                break
            }

            if let megaphone = remoteMegaphone {
                return .remoteMegaphone(megaphone: megaphone)
            }

            return .unrecognized(uniqueId: uniqueId)
        }()
    }

    // MARK: - Well-known, local manifests

    /// Contains upgrade manifests that are well-known to the app.
    ///
    /// Examples of manifests _not_ listed here include upgrades that were once
    /// well-known, but have since been removed.
    public static let wellKnownLocalUpgradeManifests: Set<ExperienceUpgradeManifest> = [
        .newLinkedDeviceNotification,
        .introducingPins,
        .notificationPermissionReminder,
        .createUsernameReminder,
        .inactiveLinkedDeviceReminder,
        .inactivePrimaryDeviceReminder,
        .pinReminder,
        .contactPermissionReminder,
        .recoveryKeyReminder,
        .backupsUpsellReminder,
        .backupsEnabledRecentlyNotification,
    ]

    // MARK: - Unique IDs

    /// The "unique ID" of this upgrade. Stable, and may be used for persistence.
    var uniqueId: String {
        switch self {
        case .newLinkedDeviceNotification:
            return "newLinkedDeviceNotification"
        case .introducingPins:
            // For historical compatibility, this experience has a unique ID
            // that does not match the enum case.
            return "009"
        case .notificationPermissionReminder:
            return "notificationPermissionReminder"
        case .createUsernameReminder:
            return "createUsernameReminder"
        case .remoteMegaphone(let megaphone):
            return megaphone.id
        case .inactiveLinkedDeviceReminder:
            return "inactiveLinkedDeviceReminder"
        case .inactivePrimaryDeviceReminder:
            return "inactivePrimaryDeviceReminder"
        case .pinReminder:
            return "pinReminder"
        case .contactPermissionReminder:
            return "contactPermissionReminder"
        case .recoveryKeyReminder:
            return "backupKeyReminder"
        case .backupsUpsellReminder:
            return "enableBackupsReminder"
        case .backupsEnabledRecentlyNotification:
            return "haveEnabledBackupsNotification"
        case .unrecognized(let uniqueId):
            return uniqueId
        }
    }

    // MARK: - Equatable

    public static func ==(lhs: ExperienceUpgradeManifest, rhs: ExperienceUpgradeManifest) -> Bool {
        lhs.uniqueId == rhs.uniqueId
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        uniqueId.hash(into: &hasher)
    }

    // MARK: - Importance order

    /// The relative "importance" of this upgrade - i.e., whether this or
    /// another which of multiple upgrade should be preferred for presentation.
    ///
    /// Lower values indicate higher importance. When comparing, ties in the
    /// primary index are broken by the secondary index. Equal primary and
    /// secondary indicies indicates equal importance.
    ///
    /// These values are not expected to remain stable.
    var importanceIndex: (primary: Int, secondary: Int) {
        switch self {
        case .newLinkedDeviceNotification:
            return (0, 0)
        case .introducingPins:
            return (1, 0)
        case .notificationPermissionReminder:
            return (2, 0)
        case .createUsernameReminder:
            return (3, 0)
        case .remoteMegaphone(let megaphone):
            // Remote megaphone manifests use higher numbers to indicate higher
            // priority, so we should invert their priority here.
            return (4, -1 * megaphone.manifest.priority)
        case .inactiveLinkedDeviceReminder:
            return (5, 0)
        case .inactivePrimaryDeviceReminder:
            return (6, 0)
        case .recoveryKeyReminder:
            return (7, 0)
        case .backupsUpsellReminder:
            return (8, 0)
        case .backupsEnabledRecentlyNotification:
            return (9, 0)
        case .pinReminder:
            return (10, 0)
        case .contactPermissionReminder:
            return (11, 0)
        case .unrecognized:
            return (Int.max, Int.max)
        }
    }

    /// Returns the elements sorted by importance order - i.e., each
    /// element in the returned array should be preferred for presention over
    /// its subsequent elements.
    public static func sortedByImportance(_ upgrades: [ExperienceUpgrade]) -> [ExperienceUpgrade] {
        return upgrades.sorted { lhs, rhs in
            let lhs = lhs.manifest
            let rhs = rhs.manifest

            if lhs.importanceIndex.primary == rhs.importanceIndex.primary {
                return lhs.importanceIndex.secondary < rhs.importanceIndex.secondary
            }

            return lhs.importanceIndex.primary < rhs.importanceIndex.primary
        }
    }

    // MARK: - Metadata

    /// The interval after snoozing during which we should not show the upgrade.
    func snoozeDuration(forSnoozeCount snoozeCount: UInt) -> TimeInterval {
        guard snoozeCount > 0 else {
            owsFailDebug("Asking for snooze duration, but snooze count is zero!")
            return 0
        }

        switch self {
        case
            // These megaphones track state externally, and never snooze.
            .pinReminder,
            .newLinkedDeviceNotification,
            .backupsEnabledRecentlyNotification,
            // These megaphones complete (permanently), rather than snooze.
            .contactPermissionReminder,
            .createUsernameReminder:
            owsFailDebug("Attempting to snooze non-snoozable megaphone? \(self)")
            return 0
        case .introducingPins:
            return 2 * .day
        case .notificationPermissionReminder,
             .inactiveLinkedDeviceReminder:
            return 3 * .day
        case .inactivePrimaryDeviceReminder,
             .recoveryKeyReminder:
            return .week
        case .backupsUpsellReminder:
            return snoozeCount == 1 ? 60 * .day : 120 * .day
        case .remoteMegaphone(let megaphone):
            let daysToSnooze: UInt = {
                // If we have snooze duration days as action data, get the
                // appropriate number of days from there based on our snooze
                // count. Otherwise, return a default value.

                let snoozeDurationDays: [UInt]? = {
                    if
                        let primaryActionData = megaphone.manifest.primaryActionData,
                        case .snoozeDurationDays(let days) = primaryActionData
                    {
                        return days
                    } else if
                        let secondaryActionData = megaphone.manifest.secondaryActionData,
                        case .snoozeDurationDays(let days) = secondaryActionData
                    {
                        return days
                    }

                    return nil
                }()

                if
                    let snoozeDurationDays,
                    let lastDurationDays = snoozeDurationDays.last
                {
                    // Safe to subtract from `snoozeCount`, since we checked for 0 above.
                    let snoozeDurationDaysIndex = snoozeCount - 1
                    return snoozeDurationDays[safe: Int(snoozeDurationDaysIndex)] ?? lastDurationDays
                }

                return 3
            }()

            return Double(daysToSnooze) * .day
        case .unrecognized:
            return .infinity
        }
    }

    /// The number of days this upgrade should be shown, starting from the
    /// first time it is shown.
    var numberOfDaysToShowFor: Int {
        switch self {
        case
            .newLinkedDeviceNotification,
            .introducingPins,
            .notificationPermissionReminder,
            .createUsernameReminder,
            .inactiveLinkedDeviceReminder,
            .inactivePrimaryDeviceReminder,
            .pinReminder,
            .contactPermissionReminder,
            .recoveryKeyReminder,
            .backupsUpsellReminder,
            .backupsEnabledRecentlyNotification:
            return Int.max
        case .remoteMegaphone(let megaphone):
            return megaphone.manifest.showForNumberOfDays
        case .unrecognized:
            return 0
        }
    }

    /// The interval immediately after registration during which we should not
    /// show the upgrade.
    public var delayAfterRegistration: TimeInterval {
        switch self {
        case
            .newLinkedDeviceNotification,
            .backupsEnabledRecentlyNotification:
            return 0
        case
            .notificationPermissionReminder,
            .createUsernameReminder,
            .inactiveLinkedDeviceReminder,
            .inactivePrimaryDeviceReminder,
            .contactPermissionReminder:
            return .day
        case .introducingPins:
            return 2 * .hour
        case .remoteMegaphone(let megaphone):
            guard let conditionalCheck = megaphone.manifest.conditionalCheck else {
                return 0
            }

            switch conditionalCheck {
            case .standardDonate:
                return 7 * .day
            case .internalUser:
                return 0
            case .unrecognized:
                return .infinity
            }
        case .pinReminder:
            return 8 * .hour
        case .recoveryKeyReminder:
            return 8 * .hour
        case .backupsUpsellReminder:
            return 7 * .day
        case .unrecognized:
            return .infinity
        }
    }

    /// The date after which the upgrade should no longer be shown.
    public var expirationDate: Date {
        switch self {
        case
            .newLinkedDeviceNotification,
            .introducingPins,
            .notificationPermissionReminder,
            .createUsernameReminder,
            .inactiveLinkedDeviceReminder,
            .inactivePrimaryDeviceReminder,
            .pinReminder,
            .contactPermissionReminder,
            .recoveryKeyReminder,
            .backupsUpsellReminder,
            .backupsEnabledRecentlyNotification:
            return Date.distantFuture
        case .remoteMegaphone(let megaphone):
            return Date(timeIntervalSince1970: TimeInterval(megaphone.manifest.dontShowAfter))
        case .unrecognized:
            return Date.distantPast
        }
    }

    /// Whether we should show this upgrade on linked devices.
    public var showOnLinkedDevices: Bool {
        switch self {
        case
            .newLinkedDeviceNotification,
            .introducingPins,
            .pinReminder,
            .inactiveLinkedDeviceReminder,
            .contactPermissionReminder,
            .recoveryKeyReminder,
            .backupsUpsellReminder,
            .backupsEnabledRecentlyNotification,
            .unrecognized:
            return false
        case
            .notificationPermissionReminder,
            .createUsernameReminder,
            .inactivePrimaryDeviceReminder:
            return true
        case
            .remoteMegaphone:
            // Controlled by conditional check
            return true
        }
    }
}
