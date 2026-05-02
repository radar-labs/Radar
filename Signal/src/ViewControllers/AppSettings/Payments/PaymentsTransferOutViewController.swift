//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import MobileCoin
import BreezSdkSpark
public import SignalServiceKit
public import SignalUI

public class PaymentsTransferOutViewController: OWSTableViewController2 {

    private let transferAmount: TSPaymentAmount?

    // TODO: Should this be a text area?
    private let addressTextfield = UITextField()

    private let paymentsHistoryDataSource = PaymentsHistoryDataSource()

    private var addressValue: String? {
        addressTextfield.text?.ows_stripped()
    }

    private var hasValidAddress: Bool {
        guard let addressValue = addressValue else {
            return false
        }
        return !addressValue.isEmpty
    }

    public init(transferAmount: TSPaymentAmount?) {
        self.transferAmount = transferAmount
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_SEND_TO_TITLE",
                                  comment: "Title for the unified 'send to' payment view.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                           target: self,
                                                           action: #selector(didTapDismiss),
                                                           accessibilityIdentifier: "dismiss")

        createViews()

        paymentsHistoryDataSource.delegate = self

        updateTableContents()

        updateNavbar()
    }

    private func updateNavbar() {
        let rightBarButtonItem = UIBarButtonItem(title: CommonStrings.nextButton,
            style: .plain,
            target: self,
            action: #selector(didTapNext)
        )
        rightBarButtonItem.isEnabled = hasValidAddress
        navigationItem.rightBarButtonItem = rightBarButtonItem
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
        updateNavbar()

        addressTextfield.becomeFirstResponder()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
        SSKEnvironment.shared.paymentsCurrenciesRef.updateConversionRates()

        addressTextfield.becomeFirstResponder()
    }

    private func createViews() {
        addressTextfield.delegate = self
        addressTextfield.font = .dynamicTypeBodyClamped
        addressTextfield.keyboardAppearance = Theme.keyboardAppearance
        addressTextfield.accessibilityIdentifier = "payments.transfer.out.addressTextfield"
        addressTextfield.addTarget(self, action: #selector(addressDidChange), for: .editingChanged)
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateTableContents()
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        addressTextfield.textColor = Theme.primaryTextColor
        let placeholder = NSAttributedString(
            string: OWSLocalizedString(
                "SETTINGS_PAYMENTS_SEND_TO_PLACEHOLDER",
                comment: "Placeholder text for the address/search field in the 'send to' payment view."
            ),
            attributes: [.foregroundColor: Theme.secondaryTextAndIconColor]
        )
        addressTextfield.attributedPlaceholder = placeholder

        let contents = OWSTableContents()

        let inputSection = OWSTableSection()
        let addressTextfield = self.addressTextfield

        let pasteIconView = UIImageView(image: UIImage(systemName: "doc.on.clipboard"))
        pasteIconView.tintColor = Theme.primaryIconColor
        pasteIconView.contentMode = .scaleAspectFit
        pasteIconView.autoSetDimensions(to: .square(24))
        pasteIconView.setCompressionResistanceHigh()
        pasteIconView.setContentHuggingHigh()
        pasteIconView.isUserInteractionEnabled = true
        pasteIconView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapPaste)))

        let scanIconView = UIImageView(image: UIImage(systemName: "qrcode.viewfinder"))
        scanIconView.tintColor = Theme.primaryIconColor
        scanIconView.contentMode = .scaleAspectFit
        scanIconView.autoSetDimensions(to: .square(24))
        scanIconView.setCompressionResistanceHigh()
        scanIconView.setContentHuggingHigh()
        scanIconView.isUserInteractionEnabled = true
        scanIconView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapScanQR)))

        let contactsIconView = UIImageView(image: UIImage(systemName: "person.circle"))
        contactsIconView.tintColor = Theme.primaryIconColor
        contactsIconView.contentMode = .scaleAspectFit
        contactsIconView.autoSetDimensions(to: .square(24))
        contactsIconView.setCompressionResistanceHigh()
        contactsIconView.setContentHuggingHigh()
        contactsIconView.isUserInteractionEnabled = true
        contactsIconView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapContacts)))

        inputSection.shouldDisableCellSelection = true
        inputSection.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()

            let iconStack = UIStackView(arrangedSubviews: [pasteIconView, scanIconView, contactsIconView])
            iconStack.axis = .horizontal
            iconStack.alignment = .center
            iconStack.spacing = 12

            let stackView = UIStackView(arrangedSubviews: [addressTextfield, iconStack])
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = 8
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            return cell
        }, actionBlock: nil))
        contents.add(inputSection)

        let recentItems = recentContactPayments()
        if !recentItems.isEmpty {
            let recentSection = OWSTableSection()
            recentSection.headerTitle = OWSLocalizedString(
                "SETTINGS_PAYMENTS_RECENT_RECIPIENTS",
                comment: "Header for the 'recent' section in the payment send-to view."
            )
            recentSection.separatorInsetLeading = OWSTableViewController2.cellHInnerMargin + 36 + 12

            for (item, address) in recentItems {
                let displayName = item.displayName
                let recipientAddress = address

                recentSection.add(OWSTableItem(customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.accessoryType = .disclosureIndicator

                    let avatarView = ConversationAvatarView(
                        sizeClass: .thirtySix,
                        localUserDisplayMode: .asUser
                    )
                    avatarView.updateWithSneakyTransactionIfNecessary { config in
                        config.dataSource = .address(recipientAddress)
                    }

                    let nameLabel = UILabel()
                    nameLabel.text = displayName
                    nameLabel.font = .dynamicTypeBodyClamped
                    nameLabel.textColor = Theme.primaryTextColor

                    let hStack = UIStackView(arrangedSubviews: [avatarView, nameLabel])
                    hStack.axis = .horizontal
                    hStack.alignment = .center
                    hStack.spacing = 12

                    cell.contentView.addSubview(hStack)
                    hStack.autoPinEdgesToSuperviewMargins()

                    return cell
                }, actionBlock: { [weak self] in
                    self?.didSelectRecentContact(address: recipientAddress)
                }))
            }
            contents.add(recentSection)
        }

        self.contents = contents
    }

    private func recentContactPayments() -> [(item: PaymentsHistoryItem, address: SignalServiceAddress)] {
        var seenAddresses = Set<SignalServiceAddress>()
        return paymentsHistoryDataSource.items.compactMap { item in
            guard let address = item.address else { return nil }
            guard seenAddresses.insert(address).inserted else { return nil }
            return (item, address)
        }.prefix(5).map { $0 }
    }

    private func didSelectRecentContact(address: SignalServiceAddress) {
        guard let navController = navigationController else { return }
        SendPaymentViewController.present(
            inNavigationController: navController,
            delegate: self,
            recipientAddress: address,
            isOutgoingTransfer: false,
            mode: .fromPaymentSettings
        )
    }

    // MARK: - Events

    @objc
    private func didTapPaste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        addressTextfield.text = text
        updateNavbar()
    }

    @objc
    private func didTapContacts() {
        guard !SUIEnvironment.shared.paymentsRef.isKillSwitchActive else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_CANNOT_SEND_PAYMENTS_KILL_SWITCH",
                comment: "Error message indicating that payments cannot be sent because the feature is not currently available."))
            return
        }
        PaymentsSendRecipientViewController.presentAsFormSheet(fromViewController: self, isOutgoingTransfer: false)
    }

    @objc
    private func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    @objc
    private func didTapNext() {
        guard let inputType = tryToParseAddress() else {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_INVALID_PUBLIC_ADDRESS_TITLE",
                                                                     comment: "Title for error alert indicating that Bitcoin over Lightning public address is not valid."),
                                            message: OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_INVALID_PUBLIC_ADDRESS",
                                                                       comment: "Error indicating that MobileCoin public address is not valid."))
            return
        }
        let recipientAddress = PaymentsImpl.format(inputType: inputType)
        guard let localWalletLightningAddress = SUIEnvironment.shared.paymentsRef.walletLightningAddress,
              localWalletLightningAddress != recipientAddress else {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_INVALID_PUBLIC_ADDRESS_TITLE",
                                                                     comment: "Title for error alert indicating that Bitcoin over Lightning public address is not valid."),
                                            message: OWSLocalizedString("SETTINGS_PAYMENTS_TRANSFER_OUT_CANNOT_SEND_TO_SELF",
                                                                       comment: "Error indicating that it is not valid to send yourself a payment."))
            return
        }

        let recipient: SendPaymentRecipientImpl = .publicAddress(inputType: inputType)
        let view = SendPaymentViewController(recipient: recipient,
                                             initialPaymentAmount: transferAmount,
                                             isOutgoingTransfer: true,
                                             mode: .fromTransferOutFlow)
        view.delegate = self
        navigationController?.pushViewController(view, animated: true)
    }

    private func tryToParseAddress() -> InputType? {
        guard let text = addressTextfield.text?.ows_stripped() else {
            return nil
        }
        if let publicAddress = PaymentsImpl.parse(input: text) {
            return publicAddress
        }
        owsFailDebug("Could not parse value.")
        return nil
    }

    @objc
    private func addressDidChange() {
        updateNavbar()
    }

    @objc
    private func didTapScanQR() {
        let view = PaymentsQRScanViewController(delegate: self)
        navigationController?.pushViewController(view, animated: true)
    }
}

// MARK: -

extension PaymentsTransferOutViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }
}

// MARK: -

extension PaymentsTransferOutViewController: SendPaymentViewDelegate {
    public func didSendPayment(success: Bool) {
        dismiss(animated: true) {
            guard success else {
                // only prompt users to enable payments lock when successful.
                return
            }
            PaymentOnboarding.presentBiometricLockPromptIfNeeded {
                Logger.debug("Payments Lock Request Complete")
            }
        }
    }
}

// MARK: -

extension PaymentsTransferOutViewController: PaymentsQRScanDelegate {
    public func didScanPaymentAddressQRCode(publicAddressBase58: String) {
        addressTextfield.text = publicAddressBase58
        updateNavbar()
    }
}

// MARK: -

extension PaymentsTransferOutViewController: PaymentsHistoryDataSourceDelegate {
    var recordType: PaymentsHistoryDataSource.RecordType { .outgoing }
    var maxRecordCount: Int? { nil }

    func didUpdateContent() {
        updateTableContents()
    }
}
