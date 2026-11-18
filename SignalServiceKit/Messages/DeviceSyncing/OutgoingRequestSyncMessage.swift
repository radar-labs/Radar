//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@objc(OWSSyncRequestMessage)
final class OutgoingRequestSyncMessage: OutgoingSyncMessage {
    let requestType: SSKProtoSyncMessageRequestType

    init(
        localThread: TSContactThread,
        requestType: SSKProtoSyncMessageRequestType,
        tx: DBReadTransaction,
    ) {
        self.requestType = requestType
        super.init(localThread: localThread, tx: tx)
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.requestType.rawValue), forKey: "requestType")
    }

    required init?(coder: NSCoder) {
        guard
            let rawRequestType = coder.decodeObject(of: NSNumber.self, forKey: "requestType"),
            let requestType = SSKProtoSyncMessageRequestType(rawValue: rawRequestType.int32Value)
        else {
            return nil
        }
        self.requestType = requestType
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.requestType)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.requestType == object.requestType else { return false }
        return true
    }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let requestBuilder = SSKProtoSyncMessageRequest.builder()

        switch self.requestType {
        case .unknown:
            Logger.warn("Found unexpectedly unknown request type \(requestType) - bailing.")
            return nil
        default:
            requestBuilder.setType(self.requestType)
        }

        let builder = SSKProtoSyncMessage.builder()
        builder.setRequest(requestBuilder.buildInfallibly())
        return builder
    }

    override var contentHint: SealedSenderContentHint { .implicit }
}
