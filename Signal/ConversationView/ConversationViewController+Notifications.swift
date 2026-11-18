//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import SignalServiceKit

extension ConversationViewController {

    func addNotificationListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(blockListDidChange),
            name: BlockingManager.blockListDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(identityStateDidChange),
            name: .identityStateDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: .OWSApplicationWillEnterForeground,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: .OWSApplicationWillResignActive,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(otherUsersProfileDidChange),
            name: UserProfileNotifications.otherUsersProfileDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(profileWhitelistDidChange),
            name: UserProfileNotifications.profileWhitelistDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appExpiryDidChange),
            name: AppExpiry.AppExpiryDidChange,
            object: nil,
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioSessionInterrupted),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(smsVerificationCodeRequested),
            name: .smsVerificationCodeRequested,
            object: nil,
        )
        SafetyTipsManager.startObservingDarwinNotifications()

        AppEnvironment.shared.callService.callServiceState.addObserver(self, syncStateImmediately: false)
    }

    @objc
    private func otherUsersProfileDidChange(_ notification: Notification) {
        guard
            let address = notification.userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress,
            address.isValid,
            thread.recipientAddressesWithSneakyTransaction.contains(address)
        else {
            return
        }

        if thread is TSContactThread {
            // update title with profile name
            enqueueReload()
        }

        // Reload all cells if this is a group conversation,
        // since we may need to update the sender names on the messages.
        // Use a DebounceEvent to de-bounce.
        if isGroupConversation {
            otherUsersProfileDidChangeEvent?.requestNotify()
        }
    }

    @objc
    private func profileWhitelistDidChange(_ notification: Notification) {
        // If profile whitelist just changed, we may want to hide a profile whitelist offer.
        if
            let address = notification.userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress,
            address.isValid,
            thread.recipientAddressesWithSneakyTransaction.contains(address)
        {
            ensureBannerState()
            showMessageRequestDialogIfRequired()
        } else if
            let groupId = notification.userInfo?[UserProfileNotifications.profileGroupIdKey] as? Data,
            !groupId.isEmpty,
            let groupThread = thread as? TSGroupThread,
            groupThread.groupModel.groupId == groupId
        {
            ensureBannerState()
            showMessageRequestDialogIfRequired()
        }
    }

    @objc
    private func blockListDidChange(_ notification: Notification) {
        ensureBannerState()
    }

    @objc
    private func identityStateDidChange(_ notification: Notification) {
        enqueueReload()
        ensureBannerState()
    }

    @objc
    private func applicationWillEnterForeground(_ notification: Notification) {
        startReadTimer()
        updateCellsVisible()
    }

    @objc
    private func applicationDidEnterBackground(_ notification: Notification) {
        updateCellsVisible()
        mediaCache.removeAllObjects()
        cancelReadTimer()
    }

    @objc
    private func applicationWillResignActive(_ notification: Notification) {
        finishRecordingVoiceMessage(sendImmediately: false)
        isUserScrolling = false
        isWaitingForDeceleration = false
        saveDraft()
        markVisibleMessagesAsRead()
        mediaCache.removeAllObjects()
        cancelReadTimer()
        dismissPresentedViewControllerIfNecessary()
        saveLastVisibleSortIdAndOnScreenPercentage()
        dismissKeyboard()
    }

    @objc
    private func applicationDidBecomeActive(_ notification: Notification) {
        startReadTimer()
    }

    @objc
    private func audioSessionInterrupted(_ notification: Notification) {
        finishRecordingVoiceMessage(sendImmediately: false)
    }

    @objc
    private func registrationStateDidChange(_ notification: Notification) {
        ensureBottomViewType()
    }

    @objc
    private func appExpiryDidChange(_ notification: Notification) {
        ensureBottomViewType()
    }

    @objc
    private func smsVerificationCodeRequested(_ notification: NSNotification) {
        let db = DependenciesBridge.shared.db
        let safetyTipsManager = SafetyTipsManager()
        let timestamp: UInt64? = db.read { tx in
            safetyTipsManager.lastVerificationCodeTimestampMsWithinExpiryTime(transaction: tx)
        }

        guard let timestamp else { return }
        let actionSheetController = SafetyTipsSheet.makeSmsCodeRequestedSheet(
            timestampMs: timestamp,
            fromViewController: self,
        )
        present(actionSheetController, animated: true, completion: {
            db.write { tx in
                safetyTipsManager.removeVerificationCodeRequestedTimestampMs(transaction: tx)
            }
        })
    }

    // MARK: - CallServiceStateObserver

    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        updateBarButtonItems()
    }
}
