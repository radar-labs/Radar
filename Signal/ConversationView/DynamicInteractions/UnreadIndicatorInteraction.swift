//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class UnreadIndicatorInteraction: TSInteraction {

    override var isDynamicInteraction: Bool {
        true
    }

    override var interactionType: OWSInteractionType {
        .unreadIndicator
    }

    init(threadUniqueId: String, timestamp: UInt64, receivedAtTimestamp: UInt64) {
        // Include timestamp in uniqueId to ensure invariant that
        // interactions don't move in the chat history ordering.
        super.init(
            customUniqueId: "UnreadIndicator_\(timestamp)",
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            threadUniqueId: threadUniqueId,
        )
    }

    override var shouldBeSaved: Bool {
        return false
    }

    override func anyWillInsert(with transaction: DBWriteTransaction) {
        owsFailDebug("The transient interaction should not be saved in the database.")
    }
}
