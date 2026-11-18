//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSSyncConfigurationMessage)
final class OutgoingConfigurationSyncMessage: OutgoingSyncMessage {

    private let areReadReceiptsEnabled: Bool
    private let showUnidentifiedDeliveryIndicators: Bool
    private let showTypingIndicators: Bool
    private let sendLinkPreviews: Bool
    private let provisioningVersion: UInt32

    init(
        localThread: TSContactThread,
        areReadReceiptsEnabled: Bool,
        showUnidentifiedDeliveryIndicators: Bool,
        showTypingIndicators: Bool,
        sendLinkPreviews: Bool,
        provisioningVersion: UInt32,
        tx: DBReadTransaction,
    ) {
        self.areReadReceiptsEnabled = areReadReceiptsEnabled
        self.showUnidentifiedDeliveryIndicators = showUnidentifiedDeliveryIndicators
        self.showTypingIndicators = showTypingIndicators
        self.sendLinkPreviews = sendLinkPreviews
        self.provisioningVersion = provisioningVersion
        super.init(localThread: localThread, tx: tx)
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: self.areReadReceiptsEnabled), forKey: "areReadReceiptsEnabled")
        coder.encode(NSNumber(value: self.provisioningVersion), forKey: "provisioningVersion")
        coder.encode(NSNumber(value: self.sendLinkPreviews), forKey: "sendLinkPreviews")
        coder.encode(NSNumber(value: self.showTypingIndicators), forKey: "showTypingIndicators")
        coder.encode(NSNumber(value: self.showUnidentifiedDeliveryIndicators), forKey: "showUnidentifiedDeliveryIndicators")
    }

    required init?(coder: NSCoder) {
        self.areReadReceiptsEnabled = coder.decodeObject(of: NSNumber.self, forKey: "areReadReceiptsEnabled")?.boolValue ?? false
        self.provisioningVersion = coder.decodeObject(of: NSNumber.self, forKey: "provisioningVersion")?.uint32Value ?? 0
        self.sendLinkPreviews = coder.decodeObject(of: NSNumber.self, forKey: "sendLinkPreviews")?.boolValue ?? false
        self.showTypingIndicators = coder.decodeObject(of: NSNumber.self, forKey: "showTypingIndicators")?.boolValue ?? false
        self.showUnidentifiedDeliveryIndicators = coder.decodeObject(of: NSNumber.self, forKey: "showUnidentifiedDeliveryIndicators")?.boolValue ?? false
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.areReadReceiptsEnabled)
        hasher.combine(self.provisioningVersion)
        hasher.combine(self.sendLinkPreviews)
        hasher.combine(self.showTypingIndicators)
        hasher.combine(self.showUnidentifiedDeliveryIndicators)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.areReadReceiptsEnabled == object.areReadReceiptsEnabled else { return false }
        guard self.provisioningVersion == object.provisioningVersion else { return false }
        guard self.sendLinkPreviews == object.sendLinkPreviews else { return false }
        guard self.showTypingIndicators == object.showTypingIndicators else { return false }
        guard self.showUnidentifiedDeliveryIndicators == object.showUnidentifiedDeliveryIndicators else { return false }
        return true
    }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let configurationBuilder = SSKProtoSyncMessageConfiguration.builder()
        configurationBuilder.setReadReceipts(self.areReadReceiptsEnabled)
        configurationBuilder.setUnidentifiedDeliveryIndicators(self.showUnidentifiedDeliveryIndicators)
        configurationBuilder.setTypingIndicators(self.showTypingIndicators)
        configurationBuilder.setLinkPreviews(self.sendLinkPreviews)
        configurationBuilder.setProvisioningVersion(self.provisioningVersion)

        let builder = SSKProtoSyncMessage.builder()
        builder.setConfiguration(configurationBuilder.buildInfallibly())
        return builder
    }

    override var isUrgent: Bool { false }
}
