//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// User-configurable preferences for Screenshot Blocking.
enum ScreenshotBlockingPreference: Equatable, CaseIterable {
    /// Screenshot blocking is enabled.
    case blockScreenshots
    /// Screenshot blocking is disabled, permanently.
    case doNotBlockScreenshots
    /// Screenshot blocking is disabled, temporarily.
    /// - Note
    /// We present this case as "disabled for ten minutes"; if that constant
    /// changes, user-facing strings will also need changing.
    case doNotBlockScreenshotsForTenMinutes
}

/// Mirrors ``ScreenshotBlockingPreference``, with associated values.
private enum _ScreenshotBlockingPreference {
    case blockScreenshots
    case doNotBlockScreenshots
    case doNotBlockScreenshotsTemporarily(remainingInterval: TimeInterval)
}

// MARK: -

/// Responsible for app-wide Screenshot Blocking.
///
/// Individual views that must never be captured block screenshots
/// themselves.
@MainActor
class ScreenshotBlockingManager {

    /// Whether blocking screenshots of the app's windows is available at all.
    nonisolated static var isAvailable: Bool {
        guard BuildFlags.screenshotBlocking else {
            return false
        }

        if #available(iOS 27, *) {
            return true
        }
        return false
    }

    private enum StoreKeys {
        static let isScreenshotBlockingEnabled = "isScreenshotBlockingEnabled"
        static let doNotBlockScreenshotsTemporarilyDate = "doNotBlockScreenshotsTemporarilyDate"
    }

    private let dateProvider: DateProvider
    private let db: any DB
    private let disabledTemporarilyInterval: TimeInterval
    private let kvStore: NewKeyValueStore
    private let windowManager: WindowManager

    private var isBlockingScreenshots: Bool = ScreenshotBlockingManager.isAvailable
    private var notificationObservers: [NotificationCenter.Observer] = []

    init(
        dateProvider: @escaping DateProvider,
        db: any DB,
        disabledTemporarilyInterval: TimeInterval = 10 * .minute,
        windowManager: WindowManager,
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.disabledTemporarilyInterval = disabledTemporarilyInterval
        self.kvStore = NewKeyValueStore(collection: "ScreenshotBlockingManager")
        self.windowManager = windowManager
    }

    // MARK: -

    /// Applies the stored preference to the app's windows, and begins
    /// watching for screenshots.
    ///
    /// The windows can exist before the database is readable, so until this
    /// runs they block screenshots, matching the default.
    func start() {
        owsPrecondition(
            notificationObservers.isEmpty,
            "Calling start() twice!",
        )

        reconcileCurrentPreference()

        notificationObservers = [
            NotificationCenter.default.addObserver(
                name: .OWSApplicationDidBecomeActive,
                block: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.reconcileCurrentPreference()
                    }
                },
            ),
            NotificationCenter.default.addObserver(
                name: UIApplication.userDidTakeScreenshotNotification,
                block: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.didTakeScreenshot()
                    }
                },
            ),
        ]
    }

    // MARK: -

    /// Gets the user's current Screenshot Blocking preference. Defaults to `.blockScreenshots`.
    func getPreference(tx: DBReadTransaction) -> ScreenshotBlockingPreference {
        return switch _getPreference(tx: tx) {
        case .blockScreenshots: .blockScreenshots
        case .doNotBlockScreenshots: .doNotBlockScreenshots
        case .doNotBlockScreenshotsTemporarily: .doNotBlockScreenshotsForTenMinutes
        }
    }

    private func _getPreference(tx: DBReadTransaction) -> _ScreenshotBlockingPreference {
        if
            let doNotBlockScreenshotsTemporarilyDate = kvStore.fetchValue(
                Date.self,
                forKey: StoreKeys.doNotBlockScreenshotsTemporarilyDate,
                tx: tx,
            )
        {
            let remainingInterval = doNotBlockScreenshotsTemporarilyDate
                .addingTimeInterval(disabledTemporarilyInterval)
                .timeIntervalSince(dateProvider())

            if remainingInterval > 0 {
                return .doNotBlockScreenshotsTemporarily(
                    remainingInterval: remainingInterval,
                )
            }
        }

        let isScreenshotBlockingEnabled = kvStore.fetchValue(
            Bool.self,
            forKey: StoreKeys.isScreenshotBlockingEnabled,
            tx: tx,
        ) ?? true

        if isScreenshotBlockingEnabled {
            return .blockScreenshots
        } else {
            return .doNotBlockScreenshots
        }
    }

    /// Sets the user's current Screenshot Blocking preference, potentially
    /// after confirmations.
    ///
    /// - Important
    /// Actually blocking screenshots requires ``isAvailable`` in addition to an
    /// `.blockScreenshots` preference.
    func setPreferenceWithConfirmation(
        _ preference: ScreenshotBlockingPreference,
        fromViewController: UIViewController,
    ) async {
        switch preference {
        case .blockScreenshots, .doNotBlockScreenshotsForTenMinutes:
            db.write { tx in
                setPreference(preference, tx: tx)
            }
            return
        case .doNotBlockScreenshots:
            break
        }

        let deferredContinuation = DeferredContinuation<Void>()

        let confirmationActionSheet = makeDisableScreenshotBlockingSheet(
            onDisableTapped: { [self] in
                db.write { tx in
                    self.setPreference(.doNotBlockScreenshots, tx: tx)
                }
            },
        )
        confirmationActionSheet.onDismiss = {
            deferredContinuation.resume(with: .success(()))
        }

        fromViewController.presentActionSheet(confirmationActionSheet)
        try? await deferredContinuation.wait()
    }

    private func setPreference(_ preference: ScreenshotBlockingPreference, tx: DBWriteTransaction) {
        let isScreenshotBlockingEnabled: Bool
        let doNotBlockScreenshotsTemporarilyDate: Date?
        switch preference {
        case .blockScreenshots:
            isScreenshotBlockingEnabled = true
            doNotBlockScreenshotsTemporarilyDate = nil
        case .doNotBlockScreenshots:
            isScreenshotBlockingEnabled = false
            doNotBlockScreenshotsTemporarilyDate = nil
        case .doNotBlockScreenshotsForTenMinutes:
            isScreenshotBlockingEnabled = true
            doNotBlockScreenshotsTemporarilyDate = dateProvider()
        }

        kvStore.writeValue(
            isScreenshotBlockingEnabled,
            forKey: StoreKeys.isScreenshotBlockingEnabled,
            tx: tx,
        )
        kvStore.writeValue(
            doNotBlockScreenshotsTemporarilyDate,
            forKey: StoreKeys.doNotBlockScreenshotsTemporarilyDate,
            tx: tx,
        )

        tx.addSyncCompletion { [self] in
            reconcileCurrentPreference()
        }
    }

    // MARK: -

    private let disabledTemporarilyWaitingTask: AtomicValue<Task<Void, Never>?> = AtomicValue(nil, lock: .init())

    private func reconcileCurrentPreference() {
        let _preference: _ScreenshotBlockingPreference = db.read { tx in
            return _getPreference(tx: tx)
        }

        defer {
            applyToWindows(_preference: _preference)
        }

        var intervalUntilNoLongerDisabled: TimeInterval
        switch _preference {
        case .blockScreenshots, .doNotBlockScreenshots:
            disabledTemporarilyWaitingTask.get()?.cancel()
            return
        case .doNotBlockScreenshotsTemporarily(let remainingInterval):
            intervalUntilNoLongerDisabled = remainingInterval
        }

        // Add a little fudge to hedge against the task wakeup racing with date
        // comparisons.
        intervalUntilNoLongerDisabled += .second

        disabledTemporarilyWaitingTask.update {
            $0?.cancel()
            $0 = Task {
                do {
                    try await Task.sleep(nanoseconds: intervalUntilNoLongerDisabled.clampedNanoseconds)
                } catch {
                    return
                }

                // It should now be past the disabledTemporarilyUntil; call
                // recursively so we set the preference to enabled.
                reconcileCurrentPreference()
            }
        }
    }

    private func applyToWindows(_preference: _ScreenshotBlockingPreference) {
        let shouldBlockScreenshots = switch _preference {
        case .blockScreenshots: true
        case .doNotBlockScreenshots: false
        case .doNotBlockScreenshotsTemporarily: false
        }

        isBlockingScreenshots = Self.isAvailable && shouldBlockScreenshots
        windowManager.setBlocksScreenshots(isBlockingScreenshots)
    }

    // MARK: -

    private func didTakeScreenshot() {
        guard isBlockingScreenshots else { return }

        guard let frontmostViewController = CurrentAppContext().frontmostViewController() else {
            owsFailDebug("Missing frontmostViewController!")
            return
        }

        showScreenshotBlockedToast(fromViewController: frontmostViewController)
    }

    private func showScreenshotBlockedToast(fromViewController: UIViewController) {
        fromViewController.presentToast(
            text: "Screenshot blocked",
            image: .lock,
            button: ToastController.Button(
                title: "Options",
                onPrimaryAction: { [self] in
                    showDisableFromToastSheet(
                        fromViewController: fromViewController,
                    )
                },
            ),
            // Extra long duration, since it'll be hidden by the blank screenshot.
            duration: .seconds(8),
        )
    }

    private func showDisableFromToastSheet(fromViewController: UIViewController) {
        let actionSheet = ActionSheetController(
            title: "Screenshot Blocking is On",
            message: "This blocks screenshots and screen recordings of Signal, including in the App Switcher.",
        )
        actionSheet.addAction(ActionSheetAction(
            title: "Turn Off for 10 Minutes",
            handler: { [self] _ in
                db.write { tx in
                    self.setPreference(.doNotBlockScreenshotsForTenMinutes, tx: tx)
                }

                fromViewController.presentToast(
                    text: "Screenshot blocking turned off for 10 minutes",
                    image: .unlockedLock,
                )
            },
        ))
        actionSheet.addAction(ActionSheetAction(
            title: "Turn Off Screenshot Blocking",
            style: .destructive,
            handler: { [self] _ in
                let doubleConfirmActionSheet = makeDisableScreenshotBlockingSheet(
                    onDisableTapped: { [self] in
                        db.write { tx in
                            self.setPreference(.doNotBlockScreenshots, tx: tx)
                        }

                        fromViewController.presentToast(
                            text: "Screenshot blocking turned off",
                            image: .unlockedLock,
                        )
                    },
                )

                fromViewController.presentActionSheet(doubleConfirmActionSheet)
            },
        ))
        actionSheet.addAction(.cancel)

        fromViewController.presentActionSheet(actionSheet)
    }

    private func makeDisableScreenshotBlockingSheet(
        onDisableTapped: @escaping () -> Void,
    ) -> ActionSheetController {
        let actionSheet = ActionSheetController(
            title: "Turn Off Screenshot Blocking?",
            message: "Screenshots and screen recordings will be able to capture Signal content.",
        )
        actionSheet.addAction(ActionSheetAction(
            title: "Turn Off",
            style: .destructive,
            handler: { _ in
                onDisableTapped()
            },
        ))
        actionSheet.addAction(.cancel)

        return actionSheet
    }
}
