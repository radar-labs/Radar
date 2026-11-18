//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSSyncFetchLatestMessage)
final class OutgoingFetchLatestSyncMessage: OutgoingSyncMessage {

    enum FetchType: UInt {
        case localProfile = 1
        case storageManifest = 2
        case subscriptionStatus = 3
    }

    private let fetchType: FetchType

    init(
        localThread: TSContactThread,
        fetchType: FetchType,
        tx: DBReadTransaction,
    ) {
        self.fetchType = fetchType
        super.init(localThread: localThread, tx: tx)
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.fetchType.rawValue), forKey: "fetchType")
    }

    required init?(coder: NSCoder) {
        guard
            let rawFetchType = coder.decodeObject(of: NSNumber.self, forKey: "fetchType")?.uintValue,
            let fetchType = FetchType(rawValue: rawFetchType)
        else {
            return nil
        }
        self.fetchType = fetchType
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.fetchType)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.fetchType == object.fetchType else { return false }
        return true
    }

    private var fetchTypeAsProtoFetchType: SSKProtoSyncMessageFetchLatestType {
        switch self.fetchType {
        case .localProfile: .localProfile
        case .storageManifest: .storageManifest
        case .subscriptionStatus: .subscriptionStatus
        }
    }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let fetchLatestBuilder = SSKProtoSyncMessageFetchLatest.builder()
        fetchLatestBuilder.setType(self.fetchTypeAsProtoFetchType)

        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        syncMessageBuilder.setFetchLatest(fetchLatestBuilder.buildInfallibly())
        return syncMessageBuilder
    }

    override var contentHint: SealedSenderContentHint { .implicit }
}
