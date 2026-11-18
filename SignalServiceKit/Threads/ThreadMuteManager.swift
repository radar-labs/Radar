//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct ThreadMuteManager {
    private let unreadReminderManager: UnreadReminderManager

    public init(unreadReminderManager: UnreadReminderManager) {
        self.unreadReminderManager = unreadReminderManager
    }

    public func setMutedUntilTimestamp(
        _ timestamp: UInt64,
        for thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        thread.anyUpdate(transaction: tx) { thread in
            thread.mutedUntilTimestamp = timestamp
        }

        if updateStorageService {
            thread.recordPendingUpdates(storageServiceManager: SSKEnvironment.shared.storageServiceManagerRef)
        }

        unreadReminderManager.didChangeMuteState(thread: thread, tx: tx)
    }
}
