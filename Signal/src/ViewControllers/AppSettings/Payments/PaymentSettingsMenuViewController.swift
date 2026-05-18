//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentSettingsMenuViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_TITLE",
            comment: "Title for the 'payments settings' view in the app settings."
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: PaymentsImpl.walletAddressDidLoad,
            object: nil
        )
        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTableContents()
    }

    @objc
    private func updateTableContents() {
        let contents = OWSTableContents()

        let mainSection = OWSTableSection()

        let currencyCode = SSKEnvironment.shared.paymentsCurrenciesRef.currentCurrencyCode
        mainSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_PAYMENTS_SET_CURRENCY",
                comment: "Title for the 'set currency' view in the app settings."
            ),
            accessoryText: currencyCode,
            actionBlock: { [weak self] in
                self?.showCurrencyPicker()
            }
        ))

        let bitcoinUnitText = PaymentsDisplayPreferences.shared.isSatoshiEnabled ? "sats" : "BTC"
        mainSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_PAYMENTS_BITCOIN_UNIT",
                comment: "Title for the 'bitcoin unit' setting in the payment settings."
            ),
            accessoryText: bitcoinUnitText,
            actionBlock: { [weak self] in
                let picker = BitcoinUnitPickerViewController()
                self?.navigationController?.pushViewController(picker, animated: true)
            }
        ))

        mainSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "PAYMENTS_USERNAME_SETTINGS_TITLE",
                comment: "Label for the Payments Username row in payment settings."
            ),
            actionBlock: { [weak self] in
                self?.didTapPaymentsUsername()
            }
        ))

        mainSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_RECOVERY_PASSPHRASE",
                comment: "Label for 'view payments recovery passphrase' button in the app settings."
            ),
            actionBlock: { [weak self] in
                self?.showRecoveryPhrase()
            }
        ))

        mainSection.add(.disclosureItem(
            withText: CommonStrings.help,
            actionBlock: { [weak self] in
                self?.showHelp()
            }
        ))

        mainSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_PAYMENTS_LIGHTNING_LOGS",
                comment: "Label for the 'lightning logs' row in payment settings."
            ),
            actionBlock: { [weak self] in
                self?.showLightningLogs()
            }
        ))

        contents.add(mainSection)

        let deactivateSection = OWSTableSection()
        deactivateSection.add(.item(
            name: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS",
                comment: "Label for 'deactivate payments' button in the app settings."
            ),
            textColor: .ows_accentRed,
            actionBlock: { [weak self] in
                self?.confirmDeactivatePayments()
            }
        ))
        deactivateSection.add(.item(
            name: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DELETE_WALLET",
                comment: "Label for 'delete payment wallet' button in the app settings."
            ),
            textColor: .ows_accentRed,
            actionBlock: { [weak self] in
                self?.confirmDeletePaymentWallet()
            }
        ))
        contents.add(deactivateSection)

        self.contents = contents
    }

    private func didTapPaymentsUsername() {
        guard let username = SUIEnvironment.shared.paymentsImplRef.walletLightningAddressUsername else { return }
        let vc = RadarUsernameViewController(oldUsername: username) { newUsername in
            try await SUIEnvironment.shared.paymentsImplRef.registerUsername(newUsername)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showCurrencyPicker() {
        let vc = CurrencyPickerViewController(
            dataSource: PaymentsCurrencyPickerDataSource()
        ) { currencyCode in
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                SSKEnvironment.shared.paymentsCurrenciesRef.setCurrentCurrencyCode(currencyCode, transaction: transaction)
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showRecoveryPhrase() {
        let style: PaymentsViewPassphraseSplashViewController.Style =
            PaymentsSettingsViewController.hasReviewedPassphraseWithSneakyTransaction() ? .reviewed : .view
        guard let passphrase = SUIEnvironment.shared.paymentsSwiftRef.passphrase else {
            owsFailDebug("Missing passphrase.")
            return
        }
        let vc = PaymentsViewPassphraseSplashViewController(
            passphrase: passphrase,
            style: style,
            viewPassphraseDelegate: self
        )
        present(OWSNavigationController(rootViewController: vc), animated: true)
    }

    private func showHelp() {
        let vc = ContactSupportViewController()
        vc.selectedFilter = .payments
        present(OWSNavigationController(rootViewController: vc), animated: true)
    }

    private func showLightningLogs() {
        let vc = LightningLogsViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    private func confirmDeactivatePayments() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS_CONFIRM_TITLE",
                comment: "Title for the 'deactivate payments confirmation' UI in the payment settings."
            ),
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_PAYMENTS_CONFIRM_DESCRIPTION",
                comment: "Description for the 'deactivate payments confirmation' UI in the payment settings."
            )
        )
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.continueButton,
            style: .default
        ) { [weak self] _ in
            self?.deactivatePayments()
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func deactivatePayments() {
        guard let paymentBalance = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance else {
            OWSActionSheets.showErrorAlert(
                message: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_CANNOT_DEACTIVATE_PAYMENTS_NO_BALANCE",
                    comment: "Error message indicating that payments could not be deactivated because the current balance is unavailable."
                )
            )
            return
        }
        guard paymentBalance.amount.picoMob > 0 else {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                SSKEnvironment.shared.paymentsHelperRef.disablePayments(transaction: transaction)
            }
            return
        }
        present(OWSNavigationController(rootViewController: PaymentsDeactivateViewController(paymentBalance: paymentBalance)), animated: true)
    }

    private func confirmDeletePaymentWallet() {
        guard let paymentBalance = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance else {
            OWSActionSheets.showErrorAlert(
                message: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_DELETE_WALLET_BALANCE_UNAVAILABLE",
                    comment: "Error message indicating that the payment wallet could not be deleted because the current balance is unavailable."
                )
            )
            return
        }
        guard paymentBalance.amount.picoMob == 0 else {
            OWSActionSheets.showErrorAlert(
                message: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_DELETE_WALLET_REQUIRES_ZERO_BALANCE",
                    comment: "Error message indicating that the payment wallet cannot be deleted until the balance is zero."
                )
            )
            return
        }

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DELETE_WALLET_CONFIRM_TITLE",
                comment: "Title for the 'delete payment wallet confirmation' UI in the payment settings."
            ),
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DELETE_WALLET_CONFIRM_DESCRIPTION",
                comment: "Description for the 'delete payment wallet confirmation' UI in the payment settings."
            )
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DELETE_WALLET",
                comment: "Label for 'delete payment wallet' button in the app settings."
            ),
            style: .destructive
        ) { [weak self] _ in
            self?.deletePaymentWallet()
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func deletePaymentWallet() {
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            presentationDelay: 0.25,
            asyncBlock: { modal in
                let result = await Result {
                    try await SUIEnvironment.shared.paymentsImplRef.deletePaymentWallet()
                }
                modal.dismissIfNotCanceled { [weak self] in
                    guard let self else { return }
                    do {
                        _ = try result.get()
                        self.navigationController?.popViewController(animated: true)
                    } catch {
                        OWSActionSheets.showErrorAlert(
                            message: OWSLocalizedString(
                                "SETTINGS_PAYMENTS_DELETE_WALLET_FAILED",
                                comment: "Error message shown when deleting the payment wallet fails."
                            )
                        )
                    }
                }
            }
        )
    }
}

// MARK: - PaymentsViewPassphraseDelegate

extension PaymentSettingsMenuViewController: PaymentsViewPassphraseDelegate {
    func viewPassphraseDidComplete() {
        PaymentsSettingsViewController.setHasReviewedPassphraseWithSneakyTransaction()
        presentToast(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_COMPLETE_TOAST",
            comment: "Message indicating that 'payments passphrase review' is complete."
        ))
    }

    func viewPassphraseDidCancel(viewController: PaymentsViewPassphraseSplashViewController) {
        viewController.dismiss(animated: true)
    }
}

// MARK: -

class BitcoinUnitPickerViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_BITCOIN_UNIT",
            comment: "Title for the 'bitcoin unit' setting in the payment settings."
        )
        updateTableContents()
    }

    @objc
    private func updateTableContents() {
        let contents = OWSTableContents()
        let section = OWSTableSection()
        let isSatoshi = PaymentsDisplayPreferences.shared.isSatoshiEnabled

        section.add(.item(
            name: "Bitcoin",
            subtitle: "BTC",
            accessoryType: !isSatoshi ? .checkmark : .none,
            actionBlock: { [weak self] in
                PaymentsDisplayPreferences.shared.isSatoshiEnabled = false
                self?.navigationController?.popViewController(animated: true)
            }
        ))

        section.add(.item(
            name: "Satoshi",
            subtitle: "1 sat = 0.00 000 001 BTC",
            accessoryType: isSatoshi ? .checkmark : .none,
            actionBlock: { [weak self] in
                PaymentsDisplayPreferences.shared.isSatoshiEnabled = true
                self?.navigationController?.popViewController(animated: true)
            }
        ))

        contents.add(section)
        self.contents = contents
    }
}
