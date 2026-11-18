//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class CVComponentStateWrapper: CVItemViewModel {
    var interaction: TSInteraction

    var componentState: CVComponentState

    init(interaction: TSInteraction, componentState: CVComponentState) {
        self.interaction = interaction
        self.componentState = componentState
    }

    var contactShare: ContactShareViewModel? {
        AssertIsOnMainThread()

        return componentState.contactShareModel
    }

    var isGiftBadge: Bool {
        AssertIsOnMainThread()

        return componentState.giftBadge != nil
    }

    var stickerMetadata: (any StickerMetadata)? {
        AssertIsOnMainThread()

        return componentState.stickerMetadata
    }

    var stickerAttachment: AttachmentStream? {
        AssertIsOnMainThread()

        return componentState.stickerAttachment
    }

    var linkPreview: OWSLinkPreview? {
        AssertIsOnMainThread()

        return componentState.linkPreviewModel
    }

    var hasRenderableContent: Bool {
        return componentState.hasRenderableContent
    }
}

// This class should only be accessed on the main thread.
class CVItemViewModelImpl: CVComponentStateWrapper {
    let renderItem: CVRenderItem

    init(renderItem: CVRenderItem) {
        AssertIsOnMainThread()

        self.renderItem = renderItem

        super.init(interaction: renderItem.interaction, componentState: renderItem.componentState)
    }

    // MARK: -

    var thread: TSThread {
        AssertIsOnMainThread()

        return renderItem.itemModel.thread
    }

    var messageCellType: CVMessageCellType {
        AssertIsOnMainThread()

        return componentState.messageCellType
    }

    var paymentAttachment: CVComponentState.PaymentAttachment? {
        AssertIsOnMainThread()

        return componentState.paymentAttachment
    }

    var archivedPaymentAttachment: CVComponentState.ArchivedPaymentAttachment? {
        AssertIsOnMainThread()

        return componentState.archivedPaymentAttachment
    }

    var reactionState: InteractionReactionState? {
        AssertIsOnMainThread()

        return componentState.reactions?.reactionState
    }

    var displayableBodyText: DisplayableText? {
        AssertIsOnMainThread()

        return componentState.displayableBodyText
    }

    var isViewOnce: Bool {
        AssertIsOnMainThread()

        guard let message = interaction as? TSMessage else {
            return false
        }
        return message.isViewOnceMessage
    }

    var isSmsMessageRestoredFromBackup: Bool {
        AssertIsOnMainThread()

        guard let message = interaction as? TSMessage else {
            return false
        }

        return message.isSmsMessageRestoredFromBackup
    }

    var wasRemotelyDeleted: Bool {
        AssertIsOnMainThread()

        return (interaction as? TSMessage)?.wasRemotelyDeleted == true
    }

    var audioAttachmentStream: AttachmentStream? {
        AssertIsOnMainThread()

        return componentState.audioAttachmentStream?.attachmentStream
    }

    var genericAttachmentStream: AttachmentStream? {
        AssertIsOnMainThread()

        return componentState.genericAttachmentStream?.attachmentStream
    }

    var bodyMediaAttachmentStreams: [AttachmentStream] {
        AssertIsOnMainThread()

        return componentState.bodyMediaAttachmentStreams.map(\.attachmentStream)
    }

    private var hasUnloadedAttachments: Bool {
        switch componentState.bodyText {
        case .oversizeTextDownloading, .oversizeTextSkipped:
            return true
        case .oversizeTextUndownloadable:
            break
        case nil, .bodyText, .remotelyDeleted:
            break
        }
        if
            let audioAttachment = componentState.audioAttachment?.attachment,
            audioAttachment.asStream() == nil
        {
            return true
        }
        if
            let genericAttachment = componentState.genericAttachment?.attachment.attachment,
            genericAttachment.attachment.asStream() == nil
        {
            return true
        }
        if
            let sticker = componentState.sticker,
            sticker.attachmentStream == nil
        {
            return true
        }
        guard let bodyMedia = componentState.bodyMedia else {
            return false
        }
        return bodyMedia.items.contains(where: { $0.attachment.attachment.attachment.asStream() == nil })
    }

    // MARK: - Actions

    var canEditMessage: Bool {
        return DependenciesBridge.shared.editManager.canShowEditMenu(interaction: interaction, thread: thread)
    }

    var canCopyOrShareOrSpeakText: Bool {
        guard !isViewOnce else {
            return false
        }
        // TODO: We could hypothetically support copying other
        // items like contact shares.
        return displayableBodyText != nil
    }

    func copyTextAction() {
        guard !isViewOnce else {
            return
        }
        // TODO: We could hypothetically support copying other
        // items like contact shares.
        guard let displayableBodyText = self.displayableBodyText else {
            return
        }
        BodyRangesTextView.copyToPasteboard(displayableBodyText.fullTextValue)
    }

    var canShareMedia: Bool {
        !shareableAttachments.isEmpty
    }

    func shareMediaAction(sender: Any?) {
        let attachments = shareableAttachments
        guard !attachments.isEmpty else {
            return
        }

        AttachmentSharing.showShareUI(for: attachments, sender: sender)
    }

    private var shareableAttachments: [ShareableAttachment] {
        guard !isViewOnce else {
            return []
        }

        guard !wasRemotelyDeleted else {
            return []
        }

        if let attachment = self.componentState.audioAttachmentStream {
            return (try? [attachment].asShareableAttachments()) ?? []
        }

        if let attachment = self.componentState.genericAttachmentStream {
            return (try? [attachment].asShareableAttachments()) ?? []
        }

        return []
    }

    var canSaveMedia: Bool {
        !saveableAttachments.isEmpty
    }

    func saveMediaAction() {
        AttachmentSaving.saveToPhotoLibrary(
            referencedAttachmentStreams: saveableAttachments,
        )
    }

    private var saveableAttachments: [ReferencedAttachmentStream] {
        return self.componentState.bodyMediaAttachmentStreams
    }

    var canForwardMessage: Bool {
        guard !isViewOnce else {
            return false
        }

        guard !isSmsMessageRestoredFromBackup else {
            return false
        }

        guard !wasRemotelyDeleted else {
            return false
        }

        switch messageCellType {
        case .unknown, .dateHeader, .typingIndicator, .unreadIndicator, .threadDetails, .systemMessage, .unknownThreadWarning, .defaultDisappearingMessageTimer, .collapseSet:
            return false
        case .giftBadge:
            return false
        case .textOnlyMessage, .audio, .genericAttachment, .contactShare, .bodyMedia, .viewOnce, .stickerMessage, .quoteOnlyMessage:
            return !hasUnloadedAttachments
        case .paymentAttachment, .archivedPaymentAttachment, .undownloadableAttachment:
            return false
        case .poll:
            return false
        case .releaseNotesMessage:
            return true
        }
    }
}

// MARK: -

extension CVComponentState {

    var displayableBodyText: DisplayableText? {
        bodyText?.displayableText
    }

    var audioAttachmentStream: ReferencedAttachmentStream? {
        audioAttachment?.attachmentStream
    }

    var genericAttachmentStream: ReferencedAttachmentStream? {
        guard
            let reference = genericAttachment?.attachment.attachment.reference,
            let stream = genericAttachment?.attachmentStream
        else {
            return nil
        }
        return .init(reference: reference, attachmentStream: stream)
    }

    var bodyMediaAttachmentStreams: [ReferencedAttachmentStream] {
        guard let bodyMedia = self.bodyMedia else {
            return []
        }
        return bodyMedia.items.compactMap { item -> ReferencedAttachmentStream? in
            guard let stream = item.attachmentStream else {
                return nil
            }
            return .init(reference: item.attachment.attachment.reference, attachmentStream: stream)
        }
    }

    var contactShareModel: ContactShareViewModel? {
        guard let contactShare = self.contactShare else {
            return nil
        }
        return contactShare.state.contactShare
    }

    var stickerMetadata: (any StickerMetadata)? {
        sticker?.stickerMetadata
    }

    var stickerAttachment: AttachmentStream? {
        sticker?.attachmentStream?.attachmentStream
    }

    var linkPreviewModel: OWSLinkPreview? {
        linkPreview?.linkPreview
    }
}
