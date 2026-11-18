//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class TypingIndicatorInteraction: TSInteraction {
    static let TypingIndicatorId = "TypingIndicator"

    override var isDynamicInteraction: Bool {
        true
    }

    override var interactionType: OWSInteractionType {
        .typingIndicator
    }

    let address: SignalServiceAddress

    init(threadUniqueId: String, timestamp: UInt64, address: SignalServiceAddress) {
        self.address = address

        super.init(
            customUniqueId: TypingIndicatorInteraction.TypingIndicatorId,
            timestamp: timestamp,
            receivedAtTimestamp: 0,
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
