//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol DeliveryReceiptContext {
    func addUpdate(
        message: TSOutgoingMessage,
        transaction: DBWriteTransaction,
        update: @escaping (TSOutgoingMessage) -> Void,
    )
}

private struct Update {
    let message: TSOutgoingMessage
    let update: (TSOutgoingMessage) -> Void
}

public class PassthroughDeliveryReceiptContext: DeliveryReceiptContext {
    public init() {}

    public func addUpdate(
        message: TSOutgoingMessage,
        transaction: DBWriteTransaction,
        update: @escaping (TSOutgoingMessage) -> Void,
    ) {
        message.anyUpdateOutgoingMessage(transaction: transaction, block: update)
    }
}

public class BatchingDeliveryReceiptContext: DeliveryReceiptContext {
    private var deferredUpdates: [Update] = []

    static func withDeferredUpdates(transaction: DBWriteTransaction, _ closure: (DeliveryReceiptContext) -> Void) {
        let instance = BatchingDeliveryReceiptContext()
        closure(instance)
        instance.runDeferredUpdates(transaction: transaction)
    }

    // Adds a closure to run that mutates a message. Note that it will be run twice - once for the
    // in-memory instance and a second time for the most up-to-date copy in the database.
    public func addUpdate(
        message: TSOutgoingMessage,
        transaction: DBWriteTransaction,
        update: @escaping (TSOutgoingMessage) -> Void,
    ) {
        deferredUpdates.append(Update(message: message, update: update))
    }

    private struct UpdateCollection {
        private var message: TSOutgoingMessage?
        private var closures = [(TSOutgoingMessage) -> Void]()

        mutating func addOrExecute(
            update: Update,
            transaction: DBWriteTransaction,
        ) {
            if message?.grdbId != update.message.grdbId {
                execute(transaction: transaction)
                message = update.message
            }
            owsAssertDebug(message != nil)
            closures.append(update.update)
        }

        mutating func execute(transaction: DBWriteTransaction) {
            guard let message else {
                owsAssertDebug(closures.isEmpty)
                return
            }
            message.anyUpdateOutgoingMessage(transaction: transaction) { messageToUpdate in
                for closure in closures {
                    closure(messageToUpdate)
                }
            }
            self.message = nil
            closures = []
        }
    }

    private func runDeferredUpdates(transaction: DBWriteTransaction) {
        let deferredUpdates = self.deferredUpdates
        self.deferredUpdates = []
        var updateCollection = UpdateCollection()
        for update in deferredUpdates {
            updateCollection.addOrExecute(update: update, transaction: transaction)
        }
        updateCollection.execute(transaction: transaction)
    }
}
