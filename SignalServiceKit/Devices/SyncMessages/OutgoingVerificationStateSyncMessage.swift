//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSVerificationStateSyncMessage)
final class OutgoingVerificationStateSyncMessage: OutgoingSyncMessage {

    // This is a clunky name, but we want to differentiate it from
    // `recipientIdentifier` inherited from `TSOutgoingMessage`
    let verificationForRecipientAddress: SignalServiceAddress

    let paddingBytesLength: UInt

    let verificationState: OWSVerificationState
    let identityKey: Data

    init(
        localThread: TSContactThread,
        verificationState: OWSVerificationState,
        identityKey: Data,
        verificationForRecipientAddress: SignalServiceAddress,
        tx: DBReadTransaction,
    ) {
        owsAssertDebug(identityKey.count == OWSIdentityManagerImpl.Constants.identityKeyLength)
        owsAssertDebug(verificationForRecipientAddress.isValid)

        // we only sync users marking as un/verified. Never sync the conflicted
        // state, the sibling device will figure that out on its own.
        owsAssertDebug(verificationState != .noLongerVerified)

        self.verificationState = verificationState
        self.identityKey = identityKey
        self.verificationForRecipientAddress = verificationForRecipientAddress

        // This sync message should be 1-512 bytes longer than the corresponding
        // NullMessage. We store this values so the corresponding NullMessage can
        // subtract it from the total length.
        self.paddingBytesLength = UInt.random(in: 1...512)

        super.init(localThread: localThread, tx: tx)
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        owsFail("Doesn't support serialization.")
    }

    required init?(coder: NSCoder) {
        // Doesn't support serialization.
        return nil
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(self.identityKey)
        hasher.combine(self.paddingBytesLength)
        hasher.combine(self.verificationForRecipientAddress)
        hasher.combine(self.verificationState)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard super.isEqual(object) else { return false }
        guard self.identityKey == object.identityKey else { return false }
        guard self.paddingBytesLength == object.paddingBytesLength else { return false }
        guard self.verificationForRecipientAddress == object.verificationForRecipientAddress else { return false }
        guard self.verificationState == object.verificationState else { return false }
        return true
    }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        // We add the same amount of padding in the VerificationStateSync message and it's corresponding NullMessage so that
        // the sync message is indistinguishable from an outgoing Sent transcript corresponding to the NullMessage. We pad
        // the NullMessage so as to obscure it's content. The sync message (like all sync messages) will be *additionally*
        // padded by the superclass while being sent. The end result is we send a NullMessage of a non-distinct size, and a
        // verification sync which is ~1-512 bytes larger then that.
        owsAssertDebug(self.paddingBytesLength != 0)

        guard let verificationForRecipientAci = self.verificationForRecipientAddress.aci else {
            return nil
        }

        let verifiedProto = OWSRecipientIdentity.buildVerifiedProto(
            destinationAci: verificationForRecipientAci,
            identityKey: self.identityKey,
            verificationState: self.verificationState,
            paddingBytesLength: self.paddingBytesLength,
        )

        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        syncMessageBuilder.setVerified(verifiedProto)
        return syncMessageBuilder
    }

    override var isUrgent: Bool { false }
}
