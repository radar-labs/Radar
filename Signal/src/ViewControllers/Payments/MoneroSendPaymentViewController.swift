//
// Copyright 2026 Radar contributors
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import SignalServiceKit

final class MoneroSendPaymentViewController: OWSViewController, QRCodeScanDelegate {
    private var request: MoneroPaymentRequest?
    private let chatRecipient: SignalServiceAddress?
    private weak var delegate: SendPaymentViewDelegate?
    private let amountField = UITextField()
    private let addressField = UITextField()
    private let statusLabel = UILabel()
    private let balanceLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let qrCodeScanner = QRCodeScanViewController(appearance: .framed)
    private var isReady = false
    private var isResolvingAddress = false
    private var addressExchangeID: UUID?
    private var availableBalance: UInt64 = 0
    private var hasLoadedBalance = false

    private init(request: MoneroPaymentRequest?, chatRecipient: SignalServiceAddress?, delegate: SendPaymentViewDelegate?) {
        self.request = request
        self.chatRecipient = chatRecipient
        self.delegate = delegate
        super.init()
    }

    static func present(
        from viewController: UIViewController,
        delegate: SendPaymentViewDelegate? = nil,
        request: MoneroPaymentRequest? = nil,
        chatRecipient: SignalServiceAddress? = nil
    ) {
        let view = MoneroSendPaymentViewController(request: request, chatRecipient: chatRecipient, delegate: delegate)
        viewController.presentFormSheet(
            OWSNavigationController(rootViewController: view),
            animated: true
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = MoneroLocalized("Send Monero")
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: presentingViewController != nil)

        let iconContainer = UIView()
        iconContainer.backgroundColor = UIColor.ows_accentBlue.withAlphaComponent(0.12)
        iconContainer.layer.cornerRadius = 30
        iconContainer.autoSetDimensions(to: .square(60))
        let iconView = UIImageView(image: UIImage(systemName: "arrow.up.right"))
        iconView.tintColor = .ows_accentBlue
        iconContainer.addSubview(iconView)
        iconView.autoSetDimensions(to: .square(25))
        iconView.autoCenterInSuperview()

        let heading = UILabel()
        heading.text = MoneroLocalized("Send XMR")
        heading.font = .dynamicTypeTitle2Clamped.semibold()
        heading.textColor = Theme.primaryTextColor
        heading.textAlignment = .center
        let subtitle = UILabel()
        subtitle.text = MoneroLocalized("Review the recipient, amount, and network before sending.")
        subtitle.font = .dynamicTypeBodyClamped
        subtitle.textColor = Theme.secondaryTextAndIconColor
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let hidesRecipientAddress = chatRecipient != nil || request != nil
        addressField.placeholder = MoneroLocalized("Monero address")
        addressField.borderStyle = .roundedRect
        addressField.backgroundColor = .secondarySystemGroupedBackground
        addressField.autocorrectionType = .no
        addressField.autocapitalizationType = .none
        addressField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        addressField.text = nil
        addressField.isHidden = hidesRecipientAddress
        addressField.isUserInteractionEnabled = !hidesRecipientAddress
        addressField.clearButtonMode = !hidesRecipientAddress ? .whileEditing : .never
        if !hidesRecipientAddress {
            let pasteButton = UIButton(type: .system)
            pasteButton.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
            pasteButton.tintColor = .ows_accentBlue
            pasteButton.addTarget(self, action: #selector(pasteAddress), for: .touchUpInside)
            pasteButton.accessibilityLabel = MoneroLocalized("Paste Monero address")
            let scanButton = UIButton(type: .system)
            scanButton.setImage(UIImage(systemName: "qrcode.viewfinder"), for: .normal)
            scanButton.tintColor = .ows_accentBlue
            scanButton.addTarget(self, action: #selector(scanAddress), for: .touchUpInside)
            scanButton.accessibilityLabel = MoneroLocalized("Scan Monero address QR code")
            let addressActions = UIStackView(arrangedSubviews: [pasteButton, scanButton])
            addressActions.axis = .horizontal
            addressActions.spacing = 6
            pasteButton.autoSetDimensions(to: .square(36))
            scanButton.autoSetDimensions(to: .square(36))
            addressField.rightView = addressActions
            addressField.rightViewMode = .always
        }

        amountField.placeholder = MoneroLocalized("Amount in XMR")
        amountField.keyboardType = .decimalPad
        amountField.borderStyle = .roundedRect
        amountField.backgroundColor = .secondarySystemGroupedBackground
        amountField.font = .systemFont(ofSize: 20, weight: .medium)
        amountField.textAlignment = .center
        if let amount = request?.amount {
            amountField.text = MoneroPaymentRequest.decimalString(amount)
            amountField.isUserInteractionEnabled = false
        }

        statusLabel.textColor = Theme.secondaryTextAndIconColor
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.text = MoneroLocalized("Opening wallet…")

        balanceLabel.font = .dynamicTypeFootnoteClamped
        balanceLabel.textColor = Theme.secondaryTextAndIconColor
        balanceLabel.numberOfLines = 0
        balanceLabel.textAlignment = .center
        balanceLabel.text = MoneroLocalized("Available balance: … XMR")

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.attributedTitle = AttributedString(MoneroLocalized("Review and send"), attributes: AttributeContainer([.font: UIFont.dynamicTypeHeadline.semibold()]))
        buttonConfiguration.baseBackgroundColor = .ows_accentBlue
        buttonConfiguration.baseForegroundColor = .white
        buttonConfiguration.cornerStyle = .large
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        sendButton.configuration = buttonConfiguration
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.isEnabled = false
        sendButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true

        let addressLabel = UILabel(text: MoneroLocalized("RECIPIENT ADDRESS"))
        addressLabel.font = .dynamicTypeCaption1Clamped.semibold()
        addressLabel.textColor = Theme.secondaryTextAndIconColor
        addressLabel.isHidden = hidesRecipientAddress
        let amountLabel = UILabel(text: MoneroLocalized("AMOUNT"))
        amountLabel.font = .dynamicTypeCaption1Clamped.semibold()
        amountLabel.textColor = Theme.secondaryTextAndIconColor
        let formStack = UIStackView(arrangedSubviews: [addressLabel, addressField, balanceLabel, amountLabel, amountField])
        formStack.axis = .vertical
        formStack.spacing = 10
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 18
        card.addSubview(formStack)
        formStack.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16))

        let stack = UIStackView(arrangedSubviews: [iconContainer, heading, subtitle, card, statusLabel, sendButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        let dismissKeyboardTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissKeyboardTap.cancelsTouchesInView = false
        view.addGestureRecognizer(dismissKeyboardTap)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
            iconContainer.centerXAnchor.constraint(equalTo: stack.centerXAnchor)
        ])

        openWallet()
    }

    private func openWallet() {
        let service = MoneroWalletService.shared
        service.snapshot { [weak self] result in
            switch result {
            case .success(let snapshot):
                guard let self else { return }
                if let requestedNetwork = self.request?.network,
                   snapshot.network != requestedNetwork {
                    self.openWallet(on: requestedNetwork)
                } else {
                    self.setReady(snapshot: snapshot)
                }
            case .failure:
                guard let self else { return }
                self.openWallet(on: self.request?.network)
            }
        }
    }

    private func openWallet(on network: MoneroNetwork?) {
        let service = MoneroWalletService.shared
        let completion: (Result<Void, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    MoneroWalletService.shared.snapshot { [weak self] snapshotResult in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            switch snapshotResult {
                            case .success(let snapshot): self.setReady(snapshot: snapshot)
                            case .failure(let error):
                                self.statusLabel.text = error.localizedDescription
                                self.statusLabel.textColor = .systemRed
                            }
                        }
                    }
                case .failure(let error):
                    if let network,
                       let walletError = error as? MoneroWalletError,
                       case .walletNotFound = walletError {
                        self.statusLabel.text = String(format: MoneroLocalized("This request is for %@, but this device has no %@ Monero wallet. Set up or restore a wallet on that network first."), network.displayName, network.displayName)
                    } else {
                        self.statusLabel.text = error.localizedDescription
                    }
                    self.statusLabel.textColor = .systemRed
                }
            }
        }

        if let network {
            service.openWallet(network: network, completion: completion)
        } else {
            service.openWallet(completion: completion)
        }
    }

    private func setReady(snapshot: MoneroWalletSnapshot) {
        DispatchQueue.main.async {
            self.isReady = true
            self.updateBalance(from: snapshot)
            if let chatRecipient = self.chatRecipient, self.request == nil {
                self.sendButton.isEnabled = false
                self.beginAddressExchange(for: chatRecipient)
            } else {
                self.sendButton.isEnabled = true
                self.statusLabel.text = MoneroLocalized("Verify the amount and network before sending.")
            }
        }
    }

    private func beginAddressExchange(for recipient: SignalServiceAddress) {
        guard !isResolvingAddress else { return }
        isResolvingAddress = true
        sendButton.isEnabled = false
        sendButton.configuration?.title = MoneroLocalized("Connecting…")
        statusLabel.text = MoneroLocalized("Securely requesting a receiving address from this chat…")
        MoneroWalletService.shared.snapshot { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finishAddressExchange(.failure(error))
            case .success(let snapshot):
                DispatchQueue.main.async { self.updateBalance(from: snapshot) }
                let id = MoneroChatPayments.shared.resolveAddress(for: recipient, network: snapshot.network) { [weak self] result in
                    self?.finishAddressExchange(result)
                }
                self.addressExchangeID = id
            }
        }
    }

    private func finishAddressExchange(_ result: Result<MoneroPaymentRequest, Error>) {
        DispatchQueue.main.async {
            self.isResolvingAddress = false
            switch result {
            case .success(let request):
                self.request = request
                self.sendButton.configuration?.title = MoneroLocalized("Review and send")
                self.sendButton.isEnabled = true
                self.statusLabel.text = MoneroLocalized("Recipient connected. Check the amount and network before sending.")
                self.statusLabel.textColor = Theme.secondaryTextAndIconColor
            case .failure(let error):
                self.sendButton.configuration?.title = MoneroLocalized("Retry connection")
                self.sendButton.isEnabled = true
                self.statusLabel.text = error.localizedDescription
                self.statusLabel.textColor = .systemRed
            }
        }
    }

    private func updateBalance(from snapshot: MoneroWalletSnapshot) {
        availableBalance = snapshot.unlockedBalance
        hasLoadedBalance = true
        balanceLabel.text = String(format: MoneroLocalized("Balance: %@ XMR · Available: %@ XMR"), MoneroPaymentRequest.decimalString(snapshot.balance), MoneroPaymentRequest.decimalString(snapshot.unlockedBalance))
    }

    @objc private func sendTapped() {
        if let chatRecipient, request == nil {
            beginAddressExchange(for: chatRecipient)
            return
        }
        guard isReady,
              let address = (request?.address ?? addressField.text)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty,
              let value = amountField.text,
              let amount = MoneroPaymentRequest.atomicUnits(value),
              amount > 0 else {
            statusLabel.text = MoneroLocalized("Enter a valid address and amount.")
            return
        }

        sendButton.isEnabled = false
        statusLabel.text = MoneroLocalized(hasLoadedBalance ? "Checking available balance…" : "Loading wallet balance…")
        MoneroWalletService.shared.snapshot { [weak self] snapshotResult in
            DispatchQueue.main.async {
                guard let self else { return }
                let snapshot: MoneroWalletSnapshot
                switch snapshotResult {
                case .failure(let error):
                    self.statusLabel.text = error.localizedDescription
                    self.statusLabel.textColor = .systemRed
                    self.sendButton.isEnabled = true
                    return
                case .success(let value):
                    snapshot = value
                    self.updateBalance(from: value)
                }
                guard amount <= snapshot.unlockedBalance else {
                    if snapshot.balance > snapshot.unlockedBalance {
                        let locked = snapshot.balance - snapshot.unlockedBalance
                        self.statusLabel.text = snapshot.isSynchronized
                            ? String(format: MoneroLocalized("You have %@ XMR total, but %@ XMR is locked until it has 10 confirmations. Available to send: %@ XMR."), MoneroPaymentRequest.decimalString(snapshot.balance), MoneroPaymentRequest.decimalString(locked), MoneroPaymentRequest.decimalString(snapshot.unlockedBalance))
                            : String(format: MoneroLocalized("Your wallet is still syncing. Balance: %@ XMR; currently available: %@ XMR."), MoneroPaymentRequest.decimalString(snapshot.balance), MoneroPaymentRequest.decimalString(snapshot.unlockedBalance))
                    } else {
                        self.statusLabel.text = String(format: MoneroLocalized("Amount exceeds available balance of %@ XMR."), MoneroPaymentRequest.decimalString(snapshot.unlockedBalance))
                    }
                    self.statusLabel.textColor = .systemRed
                    self.sendButton.isEnabled = true
                    return
                }

                self.statusLabel.text = MoneroLocalized("Preparing transaction…")
                do {
                    try MoneroWalletService.shared.validate(address: address, network: self.request?.network)
                } catch {
                    self.statusLabel.text = error.localizedDescription
                    self.statusLabel.textColor = .systemRed
                    self.sendButton.isEnabled = true
                    return
                }
                MoneroWalletService.shared.prepareSend(to: address, amount: amount) { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        switch result {
                case .failure(let error):
                    self.statusLabel.text = error.localizedDescription
                    self.statusLabel.textColor = .systemRed
                    self.sendButton.isEnabled = true
                case .success(let prepared):
                    let fee = MoneroPaymentRequest.decimalString(prepared.fee)
                    let (totalRequired, overflow) = amount.addingReportingOverflow(prepared.fee)
                    guard !overflow, totalRequired <= snapshot.unlockedBalance else {
                        self.statusLabel.text = String(format: MoneroLocalized("The amount plus network fee exceeds your available balance of %@ XMR."), MoneroPaymentRequest.decimalString(snapshot.unlockedBalance))
                        self.statusLabel.textColor = .systemRed
                        self.sendButton.isEnabled = true
                        return
                    }
                    let recipientDescription = MoneroLocalized(self.chatRecipient != nil ? "This chat" : (self.request != nil ? "Payment request" : "Manually entered address"))
                    let alert = UIAlertController(
                        title: MoneroLocalized("Confirm Monero payment"),
                        message: String(format: MoneroLocalized("Recipient: %@\nNetwork: %@\nAmount: %@ XMR\nFee: %@ XMR"), recipientDescription, self.request?.network.displayName ?? MoneroLocalized("Monero"), MoneroPaymentRequest.decimalString(amount), fee),
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: MoneroLocalized("Cancel"), style: .cancel) { [weak self] _ in
                        self?.sendButton.isEnabled = true
                    })
                    alert.addAction(UIAlertAction(title: MoneroLocalized("Confirm"), style: .default) { [weak self] _ in
                        prepared.commit { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success:
                                    guard let self else { return }
                                    let finishSending: () -> Void = { [weak self] in
                                        guard let self else { return }
                                        self.dismiss(animated: true) {
                                            self.delegate?.didSendPayment(success: true)
                                        }
                                    }
                                    if let recipient = self.chatRecipient,
                                       let network = self.request?.network {
                                        Task { @MainActor in
                                            do {
                                                try await MoneroChatPayments.shared.sendPaymentNotification(
                                                    to: recipient,
                                                    amount: amount,
                                                    network: network
                                                )
                                            } catch {
                                                Logger.warn("Monero was sent, but the chat notification could not be queued.")
                                                let notice = UIAlertController(
                                                    title: MoneroLocalized("Payment sent"),
                                                    message: MoneroLocalized("Your XMR was sent, but Radar could not queue the chat message. Do not send the payment again. Check your connection and notify the recipient in chat."),
                                                    preferredStyle: .alert
                                                )
                                                notice.addAction(UIAlertAction(title: MoneroLocalized("OK"), style: .default) { _ in
                                                    finishSending()
                                                })
                                                self.present(notice, animated: true)
                                                return
                                            }
                                            finishSending()
                                        }
                                    } else {
                                        finishSending()
                                    }
                                case .failure(let error):
                                    self?.statusLabel.text = error.localizedDescription
                                    self?.statusLabel.textColor = .systemRed
                                    self?.sendButton.isEnabled = true
                                }
                            }
                        }
                    })
                    self.present(alert, animated: true)
                        }
                    }
                }
            }
        }
    }

    @objc private func pasteAddress() {
        guard let pastedAddress = UIPasteboard.general.string else { return }
        addressField.text = pastedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func scanAddress() {
        qrCodeScanner.delegate = self
        qrCodeScanner.title = MoneroLocalized("Scan Monero QR")
        navigationController?.pushViewController(qrCodeScanner, animated: true)
    }

    func qrCodeScanViewScanned(qrCodeData: Data?, qrCodeString: String?) -> QRCodeScanOutcome {
        guard let value = qrCodeString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            OWSActionSheets.showErrorAlert(message: MoneroLocalized("This QR code does not contain a Monero address."))
            return .continueScanning
        }

        let scannedRequest = MoneroPaymentRequest.parse(value)
            ?? [MoneroNetwork.mainnet, .testnet, .stagenet]
                .compactMap { MoneroPaymentRequest.parse(value, fallbackNetwork: $0) }
                .first
        guard let scannedRequest else {
            OWSActionSheets.showErrorAlert(message: MoneroLocalized("This QR code does not contain a valid Monero address."))
            return .continueScanning
        }

        applyScannedRequest(scannedRequest)
        navigationController?.popViewController(animated: true)
        return .stopScanning
    }

    func qrCodeScanViewDismiss(_ qrCodeScanViewController: QRCodeScanViewController) {
        navigationController?.popViewController(animated: true)
    }

    private func applyScannedRequest(_ request: MoneroPaymentRequest) {
        self.request = request
        addressField.text = request.address
        amountField.text = request.amount.map(MoneroPaymentRequest.decimalString)
        amountField.isUserInteractionEnabled = request.amount == nil
        statusLabel.text = MoneroLocalized("Address scanned. Verify the amount and network before sending.")
        statusLabel.textColor = Theme.secondaryTextAndIconColor
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    deinit {
        if let addressExchangeID {
            let exchangeID = addressExchangeID
            Task { @MainActor in MoneroChatPayments.shared.cancel(exchangeID) }
        }
    }
}

private extension MoneroNetwork {
    var displayName: String {
        switch self {
        case .mainnet: return MoneroLocalized("Mainnet")
        case .testnet: return MoneroLocalized("Testnet")
        case .stagenet: return MoneroLocalized("Stagenet")
        }
    }
}

private extension UILabel {
    convenience init(text: String) {
        self.init()
        self.text = text
        self.font = .preferredFont(forTextStyle: .subheadline)
    }
}
