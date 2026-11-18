//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@MainActor
class BackupSaveAndConfirmKeyCoordinator {
    enum Option {
        /// The "save and confirm your key via password manager" flow uses iOS
        /// 26.2 APIs to try and automatically save the key to the user's
        /// preferred password manager, and then automatically confirm it.
        ///
        /// - Warning
        /// This option is silently dropped if iOS 26.2 is not available.
        /// Unfortunately, Swift doesn't allow enum cases with associated values
        /// to be gated with `@available`.
        case showSaveKeyToPasswordManager(onConfirmed: () -> Void)

        /// The "save and confirm your key manually" flow asks the user to save
        /// their key somewhere, then confirm it using a text box.
        case showSaveKeyManually(onConfirmed: () -> Void)

        /// Show a "create new key" button, handling presses with the given block.
        case showCreateNewKey(onPressed: (BackupSaveKeyViewController) -> Void)
    }

    private var passwordManagerManager: PasswordManagerManager {
        AppEnvironment.shared.passwordManagerManager
    }

    private weak var navigationController: UINavigationController?

    init(
        navigationController: UINavigationController,
    ) {
        self.navigationController = navigationController
    }

    deinit {
        Logger.verbose("")
    }

    func present(
        aepMode: BackupSaveKeyViewController.AEPMode,
        options: [Option],
    ) {
        let preconditionFilteredOptions = options.filter {
            switch $0 {
            case .showSaveKeyToPasswordManager:
                // Radar: see BuildFlags.Backups.saveRecoveryKeyToPasswordManager.
                guard BuildFlags.Backups.saveRecoveryKeyToPasswordManager else {
                    return false
                }
                if #available(iOS 26.2, *) {
                    return true
                }
                return false
            case .showSaveKeyManually, .showCreateNewKey:
                return true
            }
        }

        // If the only option we'll present is "Save Key Manually" – for example
        // on an iOS 18 device – skip straight to that flow.
        if
            preconditionFilteredOptions.count == 1,
            let onlyOption = preconditionFilteredOptions.first
        {
            switch onlyOption {
            case .showSaveKeyManually(let onConfirmed):
                showSaveKeyManually(
                    aepMode: aepMode,
                    onConfirmed: onConfirmed,
                )
                return
            case .showSaveKeyToPasswordManager, .showCreateNewKey:
                break
            }
        }

        let saveKeyViewController = BackupSaveKeyViewController(
            aepMode: aepMode,
            aepStartsCollapsed: true,
            bottomButtonConfigs: preconditionFilteredOptions.compactMap { option in
                switch option {
                case .showSaveKeyToPasswordManager(let onConfirmed):
                    guard #available(iOS 26.2, *) else {
                        owsFailBeta("Should've filtered this out above!")
                        return nil
                    }

                    return BackupSaveKeyViewController.BottomButtonConfig(
                        titleText: OWSLocalizedString(
                            "BACKUP_SAVE_KEY_SAVE_TO_PW_MGR_BUTTON_TITLE",
                            comment: "Title for a button that begins saving the user's Recovery Key to their password manager.",
                        ),
                        style: .primary,
                        action: { [self] _ in
                            trySaveAndConfirmKeyViaPasswordManager(
                                aepMode: aepMode,
                                onConfirmed: onConfirmed,
                            )
                        },
                    )
                case .showSaveKeyManually(let onConfirmed):
                    return BackupSaveKeyViewController.BottomButtonConfig(
                        titleText: OWSLocalizedString(
                            "BACKUP_SAVE_KEY_SAVE_MANUALLY_BUTTON_TITLE",
                            comment: "Title for a button that begins saving the user's Recovery Key manually.",
                        ),
                        style: .secondary,
                        action: { [self] _ in
                            showSaveKeyManually(
                                aepMode: aepMode,
                                onConfirmed: onConfirmed,
                            )
                        },
                    )
                case .showCreateNewKey(let onPressed):
                    return BackupSaveKeyViewController.BottomButtonConfig(
                        titleText: OWSLocalizedString(
                            "BACKUP_RECORD_KEY_CREATE_NEW_KEY_BUTTON_TITLE",
                            comment: "Title for a button allowing users to create a new 'Recovery Key'.",
                        ),
                        style: .secondary,
                        action: { saveKeyViewController in
                            onPressed(saveKeyViewController)
                        },
                    )
                }
            },
        )

        navigationController?.pushViewController(saveKeyViewController, animated: true)
    }

    // MARK: - Password Manager

    @available(iOS 26.2, *)
    private func trySaveAndConfirmKeyViaPasswordManager(
        aepMode: BackupSaveKeyViewController.AEPMode,
        onConfirmed: @escaping () -> Void,
    ) {
        let saveKeyConfirmationSheet = ActionSheetController(
            title: OWSLocalizedString(
                "BACKUP_SAVE_KEY_PW_MGR_CONFIRM_SHEET_TITLE",
                comment: "Title for a confirmation sheet shown before saving the user's Recovery Key to their password manager.",
            ),
            message: OWSLocalizedString(
                "BACKUP_SAVE_KEY_PW_MGR_CONFIRM_SHEET_MESSAGE",
                comment: "Message for a confirmation sheet shown before saving the user's Recovery Key to their password manager.",
            ),
        )
        saveKeyConfirmationSheet.addAction(ActionSheetAction(
            title: CommonStrings.continueButton,
            handler: { [self] _ in
                Task {
                    guard let navigationController else {
                        return
                    }

                    do {
                        // This step may silently no-op if the password is
                        // already saved, so show some UI.
                        try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                            from: navigationController,
                            minimumPresentationDuration: 2,
                        ) { [self] in
                            try await passwordManagerManager.saveDisplayableAEP(aepMode.displayableAEP)
                        }

                        tryConfirmKeyViaPasswordManager(
                            aepMode: aepMode,
                            onConfirmed: onConfirmed,
                        )
                    } catch {
                        let actionSheet = ActionSheetController(
                            title: OWSLocalizedString(
                                "BACKUP_SAVE_KEY_PW_MGR_ERROR_SHEET_TITLE",
                                comment: "Title for an error sheet shown when saving the user's Recovery Key to their password manager fails.",
                            ),
                            message: OWSLocalizedString(
                                "BACKUP_SAVE_KEY_PW_MGR_ERROR_SHEET_MESSAGE",
                                comment: "Message for an error sheet shown when saving the user's Recovery Key to their password manager fails.",
                            ),
                        )
                        actionSheet.addAction(.ok)

                        navigationController.presentActionSheet(actionSheet)
                    }
                }
            },
        ))
        saveKeyConfirmationSheet.addAction(.cancel)

        navigationController?.presentActionSheet(saveKeyConfirmationSheet)
    }

    @available(iOS 26.2, *)
    private func tryConfirmKeyViaPasswordManager(
        aepMode: BackupSaveKeyViewController.AEPMode,
        onConfirmed: @escaping () -> Void,
    ) {
        let confirmKeyConfirmationSheet = HeroSheetViewController(
            hero: .image(.backupsConfirmKeyPasswordManager),
            title: OWSLocalizedString(
                "BACKUP_CONFIRM_KEY_PW_MGR_SHEET_TITLE",
                comment: "Title for a sheet shown to confirm the user's Recovery Key after it was saved to their password manager.",
            ),
            body: OWSLocalizedString(
                "BACKUP_CONFIRM_KEY_PW_MGR_SHEET_MESSAGE",
                comment: "Message for a sheet shown to confirm the user's Recovery Key after it was saved to their password manager.",
            ),
            primaryButton: HeroSheetViewController.Button(
                title: OWSLocalizedString(
                    "BACKUP_CONFIRM_KEY_PW_MGR_SHEET_CONFIRM_BUTTON_TITLE",
                    comment: "Title for a button that begins confirming the user's Recovery Key, in a sheet shown after it was saved to their password manager.",
                ),
                action: { sheet in
                    sheet.dismiss(animated: true) { [self] in
                        Task {
                            await _tryConfirmKeyViaPasswordManager(
                                aepMode: aepMode,
                                onConfirmed: onConfirmed,
                            )
                        }
                    }
                },
            ),
            secondaryButton: .dismissing(
                title: OWSLocalizedString(
                    "BACKUP_CONFIRM_KEY_PW_MGR_SHEET_SEE_KEY_AGAIN_BUTTON_TITLE",
                    comment: "Title for a button that returns the user to view their Recovery Key, in a sheet shown after it was saved to their password manager.",
                ),
                style: .secondary,
            ),
        )

        navigationController?.present(confirmKeyConfirmationSheet, animated: true)
    }

    @available(iOS 26.2, *)
    @MainActor
    private func _tryConfirmKeyViaPasswordManager(
        aepMode: BackupSaveKeyViewController.AEPMode,
        onConfirmed: @escaping () -> Void,
    ) async {
        do {
            let fetchedDisplayableAEP = try await passwordManagerManager.requestDisplayableAEP()

            guard fetchedDisplayableAEP.rawValue == aepMode.aep else {
                throw OWSGenericError("Fetched AEP did not match expected!")
            }

            onConfirmed()
        } catch {
            let failedToConfirmActionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "BACKUP_CONFIRM_KEY_PW_MGR_ERROR_SHEET_TITLE",
                    comment: "Title for an error sheet shown when confirming the user's Recovery Key via their password manager fails.",
                ),
                message: OWSLocalizedString(
                    "BACKUP_CONFIRM_KEY_PW_MGR_ERROR_SHEET_MESSAGE",
                    comment: "Message for an error sheet shown when confirming the user's Recovery Key via their password manager fails.",
                ),
            )
            failedToConfirmActionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "BACKUP_CONFIRM_KEY_PW_MGR_ERROR_SHEET_SAVE_TO_PW_MGR_BUTTON_TITLE",
                    comment: "Title for a button that retries saving the user's Recovery Key to their password manager, in an error sheet shown when confirming it fails.",
                ),
                handler: { [self] _ in
                    trySaveAndConfirmKeyViaPasswordManager(
                        aepMode: aepMode,
                        onConfirmed: onConfirmed,
                    )
                },
            ))
            failedToConfirmActionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "BACKUP_CONFIRM_KEY_PW_MGR_ERROR_SHEET_SAVE_MANUALLY_BUTTON_TITLE",
                    comment: "Title for a button that begins saving the user's Recovery Key manually, in an error sheet shown when confirming it via their password manager fails.",
                ),
                handler: { [self] _ in
                    showSaveKeyManually(
                        aepMode: aepMode,
                        onConfirmed: onConfirmed,
                    )
                },
            ))
            failedToConfirmActionSheet.addAction(.cancel)

            navigationController?.presentActionSheet(failedToConfirmActionSheet)
        }
    }

    // MARK: - Manual

    private func showSaveKeyManually(
        aepMode: BackupSaveKeyViewController.AEPMode,
        onConfirmed: @escaping () -> Void,
    ) {
        let saveKeyManuallyViewController = BackupSaveKeyViewController(
            aepMode: aepMode,
            aepStartsCollapsed: false,
            bottomButtonConfigs: [
                BackupSaveKeyViewController.BottomButtonConfig(
                    titleText: CommonStrings.continueButton,
                    style: .primary,
                ) { [self] _ in
                    showConfirmKeyManually(
                        aep: aepMode.aep,
                        onConfirmed: onConfirmed,
                    )
                },
            ],
        )

        navigationController?.pushViewController(
            saveKeyManuallyViewController,
            animated: true,
        )
    }

    private func showConfirmKeyManually(
        aep: AccountEntropyPool,
        onConfirmed: @escaping () -> Void,
    ) {
        // Relevant to make sure onSeeKeyAgain (below) correctly pops back to a
        // view showing the key.
        owsAssertDebug(
            navigationController?.topViewController is BackupSaveKeyViewController,
            "Unexpected topViewController! \(type(of: navigationController?.topViewController))",
        )

        let confirmKeyViewController = BackupConfirmKeyViewController(
            aep: aep,
            onConfirmed: { _ in
                onConfirmed()
            },
            onSeeKeyAgain: { [self] in
                navigationController?.popViewController(animated: true)
            },
        )

        navigationController?.pushViewController(confirmKeyViewController, animated: true)
    }
}
