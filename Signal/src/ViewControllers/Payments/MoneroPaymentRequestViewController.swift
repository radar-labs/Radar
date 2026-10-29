//
// Copyright 2026 Radar contributors
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI
import SignalServiceKit

final class MoneroPaymentRequestViewController: OWSViewController {
    private let recipientAddress: SignalServiceAddress
    private weak var delegate: SendPaymentViewDelegate?
    private let amountField = UITextField()
    private let statusLabel = UILabel()
    private let shareButton = UIButton(type: .system)

    static func presentChatOptions(
        from viewController: UIViewController,
        recipientAddress: SignalServiceAddress,
        delegate: SendPaymentViewDelegate
    ) {
        let alert = UIAlertController(
            title: MoneroLocalized("Monero in this chat"),
            message: MoneroLocalized("Choose whether to send XMR or ask this contact to pay you."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: MoneroLocalized("Send XMR"), style: .default) { _ in
            MoneroSendPaymentViewController.present(from: viewController, delegate: delegate)
        })
        alert.addAction(UIAlertAction(title: MoneroLocalized("Request XMR"), style: .default) { _ in
            present(from: viewController, recipientAddress: recipientAddress, delegate: delegate)
        })
        alert.addAction(UIAlertAction(title: MoneroLocalized("Done"), style: .cancel))
        viewController.present(alert, animated: true)
    }

    private init(recipientAddress: SignalServiceAddress, delegate: SendPaymentViewDelegate) {
        self.recipientAddress = recipientAddress
        self.delegate = delegate
        super.init()
    }

    static func present(
        from viewController: UIViewController,
        recipientAddress: SignalServiceAddress,
        delegate: SendPaymentViewDelegate
    ) {
        let view = MoneroPaymentRequestViewController(
            recipientAddress: recipientAddress,
            delegate: delegate
        )
        viewController.presentFormSheet(
            OWSNavigationController(rootViewController: view),
            animated: true
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = MoneroLocalized("Request Monero")
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: presentingViewController != nil)

        let iconContainer = UIView()
        iconContainer.backgroundColor = UIColor.ows_accentBlue.withAlphaComponent(0.12)
        iconContainer.layer.cornerRadius = 30
        iconContainer.autoSetDimensions(to: .square(60))
        let icon = UIImageView(image: UIImage(systemName: "arrow.down.left"))
        icon.tintColor = .ows_accentBlue
        iconContainer.addSubview(icon)
        icon.autoSetDimensions(to: .square(25))
        icon.autoCenterInSuperview()

        let heading = UILabel()
        heading.text = MoneroLocalized("Request XMR")
        heading.font = .dynamicTypeTitle2Clamped.semibold()
        heading.textColor = Theme.primaryTextColor
        heading.textAlignment = .center
        let description = UILabel()
        description.text = MoneroLocalized("Create a private payment request to share in this conversation.")
        description.font = .dynamicTypeBodyClamped
        description.textColor = Theme.secondaryTextAndIconColor
        description.textAlignment = .center
        description.numberOfLines = 0

        amountField.placeholder = MoneroLocalized("Amount in XMR")
        amountField.keyboardType = .decimalPad
        amountField.borderStyle = .roundedRect
        amountField.font = .systemFont(ofSize: 22, weight: .medium)
        amountField.backgroundColor = .secondarySystemGroupedBackground

        let amountLabel = UILabel(text: MoneroLocalized("AMOUNT"))
        amountLabel.font = .dynamicTypeCaption1Clamped.semibold()
        amountLabel.textColor = Theme.secondaryTextAndIconColor
        let amountCard = UIView()
        amountCard.backgroundColor = .secondarySystemGroupedBackground
        amountCard.layer.cornerRadius = 18
        let amountStack = UIStackView(arrangedSubviews: [amountLabel, amountField])
        amountStack.axis = .vertical
        amountStack.spacing = 10
        amountCard.addSubview(amountStack)
        amountStack.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(top: 18, left: 16, bottom: 18, right: 16))

        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.text = MoneroLocalized("The request will be sent as an encrypted Signal message.")

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.attributedTitle = AttributedString(MoneroLocalized("Share request"), attributes: AttributeContainer([.font: UIFont.dynamicTypeHeadline.semibold()]))
        buttonConfiguration.baseBackgroundColor = .ows_accentBlue
        buttonConfiguration.baseForegroundColor = .white
        buttonConfiguration.cornerStyle = .large
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        shareButton.configuration = buttonConfiguration
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        shareButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true

        let stack = UIStackView(arrangedSubviews: [iconContainer, heading, description, amountCard, statusLabel, shareButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
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
    }

    @objc private func shareTapped() {
        guard let amountText = amountField.text,
              let amount = MoneroPaymentRequest.atomicUnits(amountText),
              amount > 0 else {
            statusLabel.text = MoneroLocalized("Enter a valid amount.")
            statusLabel.textColor = .systemRed
            return
        }

        shareButton.isEnabled = false
        MoneroWalletService.shared.currentNetwork { [weak self] networkResult in
            switch networkResult {
            case .failure(let error):
                self?.finish(error: error)
            case .success(let network):
                MoneroWalletService.shared.createSubaddress { [weak self] result in
                    switch result {
                    case .failure(let error):
                        self?.finish(error: error)
                    case .success(let address):
                        do {
                            let request = try MoneroPaymentRequest(
                                address: address,
                                amount: amount,
                                network: network,
                                requestID: UUID().uuidString
                            )
                            self?.send(request: request)
                        } catch {
                            self?.finish(error: error)
                        }
                    }
                }
            }
        }
    }

    private func send(request: MoneroPaymentRequest) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            SSKEnvironment.shared.databaseStorageRef.read { transaction in
                guard let thread = TSContactThread.getWithContactAddress(self.recipientAddress, transaction: transaction) else {
                    self.finish(error: MoneroWalletError.native(MoneroLocalized("The recipient is unavailable.")))
                    return
                }
                let messageText = request.amount.map {
                    String(format: MoneroLocalized("Monero payment request for %@ XMR"), MoneroPaymentRequest.decimalString($0))
                } ?? MoneroLocalized("Monero payment request")
                let body = MessageBody(
                    text: "\(messageText)\n\(request.uri)",
                    ranges: .empty
                )
                ThreadUtil.enqueueMessage(body: body, thread: thread)
                self.delegate?.didSendPayment(success: true)
                self.dismiss(animated: true)
            }
        }
    }

    private func finish(error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.shareButton.isEnabled = true
            self?.statusLabel.text = error.localizedDescription
            self?.statusLabel.textColor = .systemRed
        }
    }
}

final class MoneroReceiveViewController: OWSViewController {
    private let qrImageView = UIImageView()
    private let addressLabel = UILabel()
    private let statusLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let newAddressButton = UIButton(type: .system)
    private var currentAddress: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = MoneroLocalized("Receive XMR")
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: false)

        let icon = UIImageView(image: UIImage(systemName: "arrow.down.left.circle.fill"))
        icon.tintColor = .ows_accentBlue
        icon.contentMode = .scaleAspectFit
        icon.autoSetDimensions(to: .square(42))

        let titleLabel = UILabel()
        titleLabel.text = MoneroLocalized("Receive Monero")
        titleLabel.font = .dynamicTypeTitle2Clamped.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center
        let detailLabel = UILabel()
        detailLabel.text = MoneroLocalized("Share this address or QR code to receive XMR.")
        detailLabel.font = .dynamicTypeBodyClamped
        detailLabel.textColor = Theme.secondaryTextAndIconColor
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        qrImageView.backgroundColor = .white
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.layer.cornerRadius = 18
        qrImageView.clipsToBounds = true

        addressLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        addressLabel.textColor = Theme.primaryTextColor
        addressLabel.numberOfLines = 0
        addressLabel.textAlignment = .center
        let addressCard = UIView()
        addressCard.backgroundColor = .secondarySystemGroupedBackground
        addressCard.layer.cornerRadius = 16
        addressCard.addSubview(addressLabel)
        addressLabel.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))

        statusLabel.font = .dynamicTypeFootnoteClamped
        statusLabel.textColor = Theme.secondaryTextAndIconColor
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = MoneroLocalized("Loading wallet address…")

        configureButton(copyButton, title: MoneroLocalized("Copy address"), icon: "doc.on.doc", primary: true, action: #selector(copyAddress))
        configureButton(shareButton, title: MoneroLocalized("Share"), icon: "square.and.arrow.up", primary: false, action: #selector(shareAddress))
        configureButton(newAddressButton, title: MoneroLocalized("New address"), icon: "plus", primary: false, action: #selector(createNewAddress))

        let shareRow = UIStackView(arrangedSubviews: [copyButton, shareButton])
        shareRow.axis = .horizontal
        shareRow.spacing = 12
        shareRow.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, detailLabel, qrImageView, addressCard, statusLabel, shareRow, newAddressButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16

        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            addressCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shareRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            newAddressButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            icon.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            qrImageView.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            qrImageView.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.78),
            qrImageView.heightAnchor.constraint(equalTo: qrImageView.widthAnchor),
            copyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            shareButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            newAddressButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])

        loadAddress()
    }

    private func configureButton(_ button: UIButton, title: String, icon: String, primary: Bool, action: Selector) {
        var configuration = primary ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
        configuration.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.dynamicTypeSubheadline.semibold()]))
        configuration.image = UIImage(systemName: icon)
        configuration.imagePadding = 8
        configuration.cornerStyle = .large
        if primary {
            configuration.baseBackgroundColor = .ows_accentBlue
            configuration.baseForegroundColor = .white
        } else {
            configuration.baseForegroundColor = Theme.primaryTextColor
        }
        button.configuration = configuration
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func loadAddress() {
        MoneroWalletService.shared.snapshot { [weak self] result in
            switch result {
            case .success(let snapshot):
                DispatchQueue.main.async { self?.apply(snapshot) }
            case .failure:
                MoneroWalletService.shared.openWallet { [weak self] openResult in
                    switch openResult {
                    case .success:
                        MoneroWalletService.shared.snapshot { [weak self] result in
                            DispatchQueue.main.async {
                                if case .success(let snapshot) = result {
                                    self?.apply(snapshot)
                                } else if case .failure(let error) = result {
                                    self?.showError(error)
                                }
                            }
                        }
                    case .failure(let error):
                        DispatchQueue.main.async { self?.showError(error) }
                    }
                }
            }
        }
    }

    private func apply(_ snapshot: MoneroWalletSnapshot) {
        currentAddress = snapshot.address
        addressLabel.text = snapshot.address
        qrImageView.image = URL(string: "monero:\(snapshot.address)").flatMap { QRCodeGenerator().generateQRCode(url: $0) }
        statusLabel.text = snapshot.isConnected
            ? String(format: MoneroLocalized("%@ · %@"), snapshot.network.displayName, MoneroLocalized(snapshot.isSynchronized ? "Synchronized" : "Synchronizing…"))
            : MoneroLocalized("Node disconnected")
        statusLabel.textColor = snapshot.isConnected ? Theme.secondaryTextAndIconColor : .systemRed
        copyButton.isEnabled = true
        shareButton.isEnabled = true
        newAddressButton.isEnabled = true
    }

    private func showError(_ error: Error) {
        statusLabel.text = error.localizedDescription
        statusLabel.textColor = .systemRed
        copyButton.isEnabled = false
        shareButton.isEnabled = false
        newAddressButton.isEnabled = false
    }

    @objc private func copyAddress() {
        guard let currentAddress else { return }
        UIPasteboard.general.string = currentAddress
        presentToast(text: MoneroLocalized("Monero address copied"))
    }

    @objc private func shareAddress() {
        guard let currentAddress else { return }
        let activity = UIActivityViewController(activityItems: [currentAddress], applicationActivities: nil)
        present(activity, animated: true)
    }

    @objc private func createNewAddress() {
        newAddressButton.isEnabled = false
        statusLabel.text = MoneroLocalized("Creating a new receive address…")
        MoneroWalletService.shared.createSubaddress { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let address):
                    self.currentAddress = address
                    self.addressLabel.text = address
                    self.qrImageView.image = URL(string: "monero:\(address)").flatMap { QRCodeGenerator().generateQRCode(url: $0) }
                    self.statusLabel.text = MoneroLocalized("New address ready to receive XMR.")
                    self.statusLabel.textColor = Theme.secondaryTextAndIconColor
                    self.newAddressButton.isEnabled = true
                case .failure(let error):
                    self.showError(error)
                }
            }
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

private extension MoneroNetwork {
    var displayName: String {
        switch self {
        case .mainnet: return MoneroLocalized("Mainnet")
        case .testnet: return MoneroLocalized("Testnet")
        case .stagenet: return MoneroLocalized("Stagenet")
        }
    }
}
