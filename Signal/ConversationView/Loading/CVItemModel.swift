//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// Represents a single item in the conversation history.
// Could be a date header or a unread indicator.
//
// All of the state in this class should be immutable.
class CVItemModel {
    let interaction: TSInteraction
    let thread: TSThread

    // The item state loaded from the database.
    let componentState: CVComponentState

    // The item state determined by context, view state.
    let itemViewState: CVItemViewState

    var messageCellType: CVMessageCellType { componentState.messageCellType }

    // We can only measure (configure) with a given ConversationStyle.
    // So we need to capture the ConversationStyle at the time the
    // update is initiated. If the ConversationStyle has changed by
    // the time the update is delivered, we should reject the update
    // and request a new one.
    private let coreState: CVCoreState
    var conversationStyle: ConversationStyle { coreState.conversationStyle }
    var mediaCache: CVMediaCache { coreState.mediaCache }

    init(
        interaction: TSInteraction,
        thread: TSThread,
        componentState: CVComponentState,
        itemViewState: CVItemViewState,
        coreState: CVCoreState,
    ) {

        self.interaction = interaction
        self.thread = thread
        self.componentState = componentState
        self.itemViewState = itemViewState
        self.coreState = coreState
    }
}
