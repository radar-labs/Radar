//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Informs other platforms that a linked device's name has changed, and they
/// should refresh their list of linked devices.
@objc(OutgoingDeviceNameChangeSyncMessage)
public class OutgoingDeviceNameChangeSyncMessage: OutgoingSyncMessage {
    override public class var supportsSecureCoding: Bool { true }

    public required init?(coder: NSCoder) {
        guard let deviceId = coder.decodeObject(of: NSNumber.self, forKey: "deviceId") else {
            return nil
        }
        self.deviceId = deviceId.uint32Value
        super.init(coder: coder)
    }

    override public func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(NSNumber(value: deviceId), forKey: "deviceId")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(deviceId)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.deviceId == object.deviceId else { return false }
        return true
    }

    private let deviceId: UInt32

    init(
        deviceId: UInt32,
        localThread: TSContactThread,
        tx: DBReadTransaction,
    ) {
        self.deviceId = deviceId
        super.init(localThread: localThread, tx: tx)
    }

    override public var isUrgent: Bool { false }

    override public func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let deviceNameChangeBuilder = SSKProtoSyncMessageDeviceNameChange.builder()
        deviceNameChangeBuilder.setDeviceID(deviceId)

        let builder = SSKProtoSyncMessage.builder()
        builder.setDeviceNameChange(deviceNameChangeBuilder.buildInfallibly())
        return builder
    }
}
