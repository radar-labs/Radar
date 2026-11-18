//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Outgoing message we send to the contact we want to activate payments.
/// NOT rendered in chat; a separate TSInfoMessage is created for that purpose.
@objc(OWSPaymentActivationRequestMessage)
public final class OutgoingPaymentActivationRequestMessage: TransientOutgoingMessage {

    override public class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public init(thread: TSThread, tx: DBReadTransaction) {
        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread)
        super.init(outgoingMessageWith: messageBuilder, additionalRecipients: [], explicitRecipients: [], skippedRecipients: [], transaction: tx)
    }

    override public func dataMessageBuilder(with thread: TSThread, transaction tx: DBReadTransaction) -> SSKProtoDataMessageBuilder? {
        let builder = super.dataMessageBuilder(with: thread, transaction: tx)

        let activationBuilder = SSKProtoDataMessagePaymentActivation.builder()
        activationBuilder.setType(.request)
        let activation = activationBuilder.buildInfallibly()

        let paymentBuilder = SSKProtoDataMessagePayment.builder()
        paymentBuilder.setActivation(activation)
        do {
            builder?.setPayment(try paymentBuilder.build())
            builder?.setRequiredProtocolVersion(UInt32(SSKProtoDataMessageProtocolVersion.payments.rawValue))
            return builder
        } catch {
            owsFailDebug("could not build protobuf: \(error)")
            return nil
        }
    }

    override public var contentHint: SealedSenderContentHint { .implicit }
}
