//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// A generic, serializable message that can be used to
// send fixed plaintextData payloads.
@objc(OWSStaticOutgoingMessage)
final class OutgoingStaticMessage: TransientOutgoingMessage {

    let plaintextData: Data

    init(
        thread: TSContactThread,
        timestamp: UInt64,
        plaintextData: Data,
        tx: DBReadTransaction,
    ) {
        self.plaintextData = plaintextData
        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread)
        messageBuilder.timestamp = timestamp
        super.init(
            outgoingMessageWith: messageBuilder,
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx,
        )
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(self.plaintextData, forKey: "plaintextData")
    }

    required init?(coder: NSCoder) {
        guard let plaintextData = coder.decodeObject(of: NSData.self, forKey: "plaintextData") as Data? else {
            return nil
        }
        self.plaintextData = plaintextData
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.plaintextData)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.plaintextData == object.plaintextData else { return false }
        return true
    }

    override func shouldSyncTranscript() -> Bool { false }

    override func buildPlaintextData(inThread thread: TSThread, tx: DBWriteTransaction) throws -> Data {
        return self.plaintextData
    }
}
