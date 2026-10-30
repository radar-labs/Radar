//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

public class PinnedMessageManager {
    private let interactionStore: InteractionStore
    private let accountManager: TSAccountManager
    private let disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore

    init(
        interactionStore: InteractionStore,
        accountManager: TSAccountManager,
        disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore
    ) {
        self.interactionStore = interactionStore
        self.accountManager = accountManager
        self.disappearingMessagesConfigurationStore = disappearingMessagesConfigurationStore
    }

    public func fetchPinnedMessagesForThread(
        threadId: Int64,
        tx: DBReadTransaction
    ) -> [Int64] {
        return failIfThrows {
            try PinnedMessageRecord
                .filter(PinnedMessageRecord.Columns.threadId == threadId)
                .order(PinnedMessageRecord.Columns.id.desc)
                .select(PinnedMessageRecord.Columns.interactionId)
                .asRequest(of: Row.self)
                .fetchAll(tx.database)
                .compactMap { $0[PinnedMessageRecord.Columns.interactionId] }
        }
    }

    public func pinMessage(
        pinMessageProto: SSKProtoDataMessagePinMessage,
        threadId: Int64,
        timestamp: Int64,
        transaction: DBWriteTransaction
    ) throws -> TSInteraction {
        guard let localAci = accountManager.localIdentifiers(tx: transaction)?.aci,
              let authorData = pinMessageProto.targetAuthorAciBinary,
              let authorAci = try? Aci.parseFrom(serviceIdBinary: authorData),
              let targetMessage = try interactionStore.fetchMessage(
                timestamp: pinMessageProto.targetSentTimestamp,
                incomingMessageAuthor: authorAci == localAci ? nil : authorAci,
                transaction: transaction
              ),
              let interactionId = targetMessage.grdbId?.int64Value else {
            throw OWSAssertionError("Can't find target pinned message")
        }

        let expiresAt: Int64?
        if pinMessageProto.hasPinDurationSeconds {
            expiresAt = timestamp + Int64(pinMessageProto.pinDurationSeconds)
        } else if pinMessageProto.hasPinDurationForever {
            expiresAt = nil
        } else {
            throw OWSAssertionError("Pin message has no duration")
        }

        _ = try PinnedMessageRecord
            .filter(PinnedMessageRecord.Columns.threadId == threadId)
            .filter(PinnedMessageRecord.Columns.interactionId == interactionId)
            .deleteAll(transaction.database)
        pruneOldestPinnedMessagesIfNecessary(threadId: threadId, transaction: transaction)
        _ = try PinnedMessageRecord.insertRecord(
            interactionId: interactionId,
            threadId: threadId,
            expiresAt: expiresAt,
            tx: transaction
        )
        return targetMessage
    }

    public func unpinMessage(
        unpinMessageProto: SSKProtoDataMessageUnpinMessage,
        transaction: DBWriteTransaction
    ) throws -> TSInteraction {
        guard let localAci = accountManager.localIdentifiers(tx: transaction)?.aci,
              let authorData = unpinMessageProto.targetAuthorAciBinary,
              let authorAci = try? Aci.parseFrom(serviceIdBinary: authorData),
              let targetMessage = try interactionStore.fetchMessage(
                timestamp: unpinMessageProto.targetSentTimestamp,
                incomingMessageAuthor: authorAci == localAci ? nil : authorAci,
                transaction: transaction
              ),
              let interactionId = targetMessage.grdbId?.int64Value else {
            throw OWSAssertionError("Can't find target pinned message")
        }

        _ = try PinnedMessageRecord
            .filter(PinnedMessageRecord.Columns.interactionId == interactionId)
            .deleteAll(transaction.database)
        return targetMessage
    }

    public func getOutgoingPinMessage(
        interaction: TSMessage,
        thread: TSThread,
        tx: DBReadTransaction
    ) -> OutgoingPinMessage? {
        guard let authorAci = messageAuthorAci(interaction: interaction, tx: tx) else {
            return nil
        }
        return OutgoingPinMessage(
            thread: thread,
            targetMessageTimestamp: interaction.timestamp,
            targetMessageAuthorAciBinary: authorAci,
            pinDurationSeconds: 0,
            pinDurationForever: true,
            messageExpiresInSeconds: disappearingMessagesConfigurationStore.durationSeconds(for: thread, tx: tx),
            tx: tx
        )
    }

    public func getOutgoingUnpinMessage(
        interaction: TSMessage,
        thread: TSThread,
        tx: DBReadTransaction
    ) -> OutgoingUnpinMessage? {
        guard let authorAci = messageAuthorAci(interaction: interaction, tx: tx) else {
            return nil
        }
        return OutgoingUnpinMessage(
            thread: thread,
            targetMessageTimestamp: interaction.timestamp,
            targetMessageAuthorAciBinary: authorAci,
            messageExpiresInSeconds: disappearingMessagesConfigurationStore.durationSeconds(for: thread, tx: tx),
            tx: tx
        )
    }

    public func applyPinMessageChangeToLocalState(
        targetTimestamp: UInt64,
        targetAuthorAci: Aci,
        isPin: Bool,
        tx: DBWriteTransaction
    ) {
        guard let localAci = accountManager.localIdentifiers(tx: tx)?.aci,
              let targetMessage = try? interactionStore.fetchMessage(
                timestamp: targetTimestamp,
                incomingMessageAuthor: targetAuthorAci == localAci ? nil : targetAuthorAci,
                transaction: tx
              ),
              let interactionId = targetMessage.grdbId?.int64Value,
              let thread = DependenciesBridge.shared.threadStore.fetchThread(
                uniqueId: targetMessage.uniqueThreadId,
                tx: tx
              ),
              let threadId = thread.grdbId?.int64Value else {
            return
        }

        do {
            if isPin {
                _ = try PinnedMessageRecord
                    .filter(PinnedMessageRecord.Columns.threadId == threadId)
                    .filter(PinnedMessageRecord.Columns.interactionId == interactionId)
                    .deleteAll(tx.database)
                pruneOldestPinnedMessagesIfNecessary(threadId: threadId, transaction: tx)
                _ = try PinnedMessageRecord.insertRecord(
                    interactionId: interactionId,
                    threadId: threadId,
                    tx: tx
                )
            } else {
                _ = try PinnedMessageRecord
                    .filter(PinnedMessageRecord.Columns.interactionId == interactionId)
                    .deleteAll(tx.database)
            }
        } catch {
            owsFailDebug("Could not update pinned message state: \(error)")
        }

        SSKEnvironment.shared.databaseStorageRef.touch(
            interaction: targetMessage,
            shouldReindex: false,
            tx: tx
        )
    }

    private func messageAuthorAci(interaction: TSMessage, tx: DBReadTransaction) -> Aci? {
        guard let localAci = accountManager.localIdentifiers(tx: tx)?.aci else {
            return nil
        }
        if interaction is TSOutgoingMessage {
            return localAci
        }
        guard let incomingMessage = interaction as? TSIncomingMessage,
              let authorUUID = incomingMessage.authorUUID else {
            return nil
        }
        return try? Aci.parseFrom(serviceIdString: authorUUID)
    }

    private func pruneOldestPinnedMessagesIfNecessary(
        threadId: Int64,
        transaction: DBWriteTransaction
    ) {
        let newestIds: [Int64] = (try? PinnedMessageRecord
            .filter(PinnedMessageRecord.Columns.threadId == threadId)
            .order(PinnedMessageRecord.Columns.id.desc)
            .limit(2)
            .select(PinnedMessageRecord.Columns.id)
            .fetchAll(transaction.database)) ?? []

        _ = try? PinnedMessageRecord
            .filter(PinnedMessageRecord.Columns.threadId == threadId)
            .filter(!newestIds.contains(PinnedMessageRecord.Columns.id))
            .deleteAll(transaction.database)
    }
}

public final class OutgoingPinMessage: TSOutgoingMessage {
    private var targetMessageTimestamp: UInt64 = 0
    private var targetMessageAuthorAciBinary = Data()
    private var pinDurationSeconds: UInt32 = 0
    private var pinDurationForever = false

    init(
        thread: TSThread,
        targetMessageTimestamp: UInt64,
        targetMessageAuthorAciBinary: Aci,
        pinDurationSeconds: UInt32,
        pinDurationForever: Bool,
        messageExpiresInSeconds: UInt32,
        tx: DBReadTransaction
    ) {
        self.targetMessageTimestamp = targetMessageTimestamp
        self.targetMessageAuthorAciBinary = targetMessageAuthorAciBinary.serviceIdBinary
        self.pinDurationSeconds = pinDurationSeconds
        self.pinDurationForever = pinDurationForever
        super.init(
            outgoingMessageWith: .withDefaultValues(thread: thread, expiresInSeconds: messageExpiresInSeconds),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    override public var shouldBeSaved: Bool { false }
    override var contentHint: SealedSenderContentHint { .implicit }

    override public func dataMessageBuilder(
        with thread: TSThread,
        transaction: DBReadTransaction
    ) -> SSKProtoDataMessageBuilder? {
        guard let builder = super.dataMessageBuilder(with: thread, transaction: transaction) else {
            return nil
        }
        let pin = SSKProtoDataMessagePinMessage.builder()
        pin.setTargetSentTimestamp(targetMessageTimestamp)
        pin.setTargetAuthorAciBinary(targetMessageAuthorAciBinary)
        if pinDurationSeconds > 0 {
            pin.setPinDurationSeconds(pinDurationSeconds)
        } else if pinDurationForever {
            pin.setPinDurationForever(true)
        }
        builder.setPinMessage(pin.buildInfallibly())
        return builder
    }

    override public func updateWithSendSuccess(tx: DBWriteTransaction) {
        guard let authorAci = try? Aci.parseFrom(serviceIdBinary: targetMessageAuthorAciBinary) else {
            return
        }
        DependenciesBridge.shared.pinnedMessageManager.applyPinMessageChangeToLocalState(
            targetTimestamp: targetMessageTimestamp,
            targetAuthorAci: authorAci,
            isPin: true,
            tx: tx
        )
    }
}

public final class OutgoingUnpinMessage: TSOutgoingMessage {
    private var targetMessageTimestamp: UInt64 = 0
    private var targetMessageAuthorAciBinary = Data()

    init(
        thread: TSThread,
        targetMessageTimestamp: UInt64,
        targetMessageAuthorAciBinary: Aci,
        messageExpiresInSeconds: UInt32,
        tx: DBReadTransaction
    ) {
        self.targetMessageTimestamp = targetMessageTimestamp
        self.targetMessageAuthorAciBinary = targetMessageAuthorAciBinary.serviceIdBinary
        super.init(
            outgoingMessageWith: .withDefaultValues(thread: thread, expiresInSeconds: messageExpiresInSeconds),
            additionalRecipients: [],
            explicitRecipients: [],
            skippedRecipients: [],
            transaction: tx
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    override public var shouldBeSaved: Bool { false }
    override var contentHint: SealedSenderContentHint { .implicit }

    override public func dataMessageBuilder(
        with thread: TSThread,
        transaction: DBReadTransaction
    ) -> SSKProtoDataMessageBuilder? {
        guard let builder = super.dataMessageBuilder(with: thread, transaction: transaction) else {
            return nil
        }
        let unpin = SSKProtoDataMessageUnpinMessage.builder()
        unpin.setTargetSentTimestamp(targetMessageTimestamp)
        unpin.setTargetAuthorAciBinary(targetMessageAuthorAciBinary)
        builder.setUnpinMessage(unpin.buildInfallibly())
        return builder
    }

    override public func updateWithSendSuccess(tx: DBWriteTransaction) {
        guard let authorAci = try? Aci.parseFrom(serviceIdBinary: targetMessageAuthorAciBinary) else {
            return
        }
        DependenciesBridge.shared.pinnedMessageManager.applyPinMessageChangeToLocalState(
            targetTimestamp: targetMessageTimestamp,
            targetAuthorAci: authorAci,
            isPin: false,
            tx: tx
        )
    }
}
