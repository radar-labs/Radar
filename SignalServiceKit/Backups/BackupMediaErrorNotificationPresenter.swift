//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

struct BackupMediaErrorNotificationPresenter {
    private enum Keys {
        static let lastNotified = "lastNotified"
    }

    private let dateProvider: DateProvider
    private let db: DB
    private let kvStore: NewKeyValueStore
    private let logger: PrefixedLogger
    private let notificationPresenter: NotificationPresenter

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
        notificationPresenter: NotificationPresenter,
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = NewKeyValueStore(collection: "BackupErrorNotificationPresenter")
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.notificationPresenter = notificationPresenter
    }

    func notifyIfNecessary() async {
        guard BuildFlags.Backups.mediaErrorDisplay else {
            return
        }

        let now = dateProvider()

        let lastNotified = db.read { tx in
            return kvStore.fetchValue(Date.self, forKey: Keys.lastNotified, tx: tx) ?? .distantPast
        }

        if lastNotified.addingTimeInterval(.day) > now {
            // We notified in the last day, so skip this one.
            return
        }

        await db.awaitableWrite { tx in
            kvStore.writeValue(now, forKey: Keys.lastNotified, tx: tx)
        }

        owsFailDebug(
            "Presenting BackupsMediaError notification.",
            logger: logger,
        )
        notificationPresenter.notifyUserOfBackupsMediaError()
    }
}
