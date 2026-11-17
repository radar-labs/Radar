//
// Copyright 2026 Radar contributors
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalUI

final class MoneroWalletViewController: OWSViewController {
    private let nodeField = UITextField()
    private let nodePickerButton = UIButton(type: .system)
    private let recoveryField = UITextView()
    private let statusLabel = UILabel()
    private let balanceLabel = UILabel()
    private let addressLabel = UILabel()
    private let qrImageView = UIImageView()
    private let createButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)
    private let newAddressButton = UIButton(type: .system)
    private var balanceRefreshTimer: Timer?

    private var selectedNetwork: MoneroNetwork { .mainnet }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = MoneroLocalized("Monero")
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: presentingViewController != nil)
        buildView()
        openExistingWallet()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if nodeField.isHidden {
            refreshWallet()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        balanceRefreshTimer?.invalidate()
        balanceRefreshTimer = nil
    }

    private func buildView() {
        nodeField.placeholder = MoneroLocalized("Monero node URL (HTTPS)")
        nodeField.borderStyle = .roundedRect
        nodeField.autocapitalizationType = .none
        nodeField.autocorrectionType = .no
        nodeField.keyboardType = .URL
        nodeField.returnKeyType = .done
        nodeField.inputAccessoryView = makeKeyboardToolbar()
        nodeField.addTarget(self, action: #selector(dismissNodeKeyboard), for: .editingDidEndOnExit)
        nodePickerButton.setTitle(MoneroLocalized("Choose node"), for: .normal)
        nodePickerButton.addTarget(self, action: #selector(chooseNode), for: .touchUpInside)

        recoveryField.font = .preferredFont(forTextStyle: .body)
        recoveryField.layer.cornerRadius = 8
        recoveryField.layer.borderWidth = 1
        recoveryField.layer.borderColor = UIColor.separator.cgColor
        recoveryField.heightAnchor.constraint(equalToConstant: 100).isActive = true
        recoveryField.isHidden = true
        recoveryField.text = ""

        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        balanceLabel.font = .preferredFont(forTextStyle: .title2)
        balanceLabel.text = MoneroLocalized("Balance unavailable")
        addressLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        addressLabel.numberOfLines = 0
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.heightAnchor.constraint(equalToConstant: 180).isActive = true

        configure(createButton, title: MoneroLocalized("Create wallet"), action: #selector(createWallet))
        configure(restoreButton, title: MoneroLocalized("Restore wallet"), action: #selector(restoreWallet))
        configure(refreshButton, title: MoneroLocalized("Refresh"), action: #selector(refreshWallet))
        configure(newAddressButton, title: MoneroLocalized("New receive address"), action: #selector(newAddress))
        refreshButton.isHidden = true
        newAddressButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [
            nodePickerButton,
            nodeField,
            statusLabel,
            balanceLabel,
            addressLabel,
            qrImageView,
            refreshButton,
            newAddressButton,
            createButton,
            restoreButton,
            recoveryField
        ])
        stack.axis = .vertical
        stack.spacing = 12
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }

    private func configure(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func makeKeyboardToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissNodeKeyboard))
        ]
        return toolbar
    }

    @objc private func dismissNodeKeyboard() {
        nodeField.resignFirstResponder()
    }

    private func node() -> MoneroNode? {
        guard let endpoint = nodeField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !endpoint.isEmpty else {
            statusLabel.text = MoneroLocalized("Enter a Monero node URL.")
            statusLabel.textColor = .systemRed
            return nil
        }
        let isManaged = MoneroNodeDirectory.availableNodes.contains { $0.endpoint.caseInsensitiveCompare(endpoint) == .orderedSame }
        guard isManaged || MoneroNodeDirectory.addCustomNode(endpoint) else {
            statusLabel.text = MoneroLocalized("Use a valid HTTPS node URL for Mainnet.")
            statusLabel.textColor = .systemRed
            return nil
        }
        return MoneroNode(endpoint: endpoint)
    }

    private func openExistingWallet() {
        let service = MoneroWalletService.shared
        service.snapshot { [weak self] result in
            switch result {
            case .success(let snapshot):
                self?.apply(snapshot)
            case .failure:
                service.openWallet { [weak self] result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self?.refreshWallet()
                        case .failure:
                            self?.showSetupForSelectedNetwork()
                        }
                    }
                }
            }
        }
    }

    @objc private func chooseNode() {
        let alert = UIAlertController(title: MoneroLocalized("Monero node"), message: nil, preferredStyle: .actionSheet)
        for node in MoneroNodeDirectory.availableNodes {
            alert.addAction(UIAlertAction(title: node.name, style: .default) { [weak self] _ in
                self?.nodeField.text = node.endpoint
            })
        }
        alert.addAction(UIAlertAction(title: MoneroLocalized("Add custom node"), style: .default) { [weak self] _ in
            self?.promptForCustomNode()
        })
        alert.addAction(UIAlertAction(title: MoneroLocalized("Cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = nodePickerButton
            popover.sourceRect = nodePickerButton.bounds
        }
        present(alert, animated: true)
    }

    private func promptForCustomNode() {
        let alert = UIAlertController(title: MoneroLocalized("Add custom node"), message: MoneroLocalized("Use an HTTPS node you trust. The node can observe wallet network activity."), preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://host:port"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: MoneroLocalized("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: MoneroLocalized("Save"), style: .default) { [weak self, weak alert] _ in
            guard let endpoint = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  MoneroNodeDirectory.addCustomNode(endpoint) else {
                self?.statusLabel.text = MoneroLocalized("Enter a valid HTTPS node URL.")
                self?.statusLabel.textColor = .systemRed
                return
            }
            self?.nodeField.text = endpoint
        })
        present(alert, animated: true)
    }

    private func showSetupForSelectedNetwork() {
        nodeField.isHidden = false
        nodePickerButton.isHidden = false
        if nodeField.text?.isEmpty != false, let first = MoneroNodeDirectory.availableNodes.first {
            nodeField.text = first.endpoint
        }
        statusLabel.text = MoneroLocalized("No Monero wallet configured.")
        statusLabel.textColor = .secondaryLabel
        balanceLabel.text = MoneroLocalized("Balance unavailable")
        addressLabel.text = nil
        qrImageView.image = nil
        refreshButton.isHidden = true
        newAddressButton.isHidden = true
        createButton.isHidden = false
        restoreButton.isHidden = false
        recoveryField.isHidden = true
    }

    @objc private func createWallet() {
        guard let node = node() else { return }
        setBusy(MoneroLocalized("Creating wallet…"))
        MoneroWalletService.shared.createWallet(network: selectedNetwork, node: node) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let seed):
                    MoneroChatPayments.shared.announceAddresses()
                    self?.setReady(MoneroLocalized("Wallet created. Write down the recovery phrase."))
                    self?.showSeed(seed)
                    self?.refreshWallet()
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func restoreWallet() {
        guard let node = node() else { return }
        let seed = recoveryField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !seed.isEmpty else {
            recoveryField.isHidden = false
            statusLabel.text = MoneroLocalized("Enter the Monero recovery phrase.")
            return
        }

        setBusy(MoneroLocalized("Restoring wallet…"))
        MoneroWalletService.shared.restoreWallet(
            mnemonic: seed,
            network: selectedNetwork,
            node: node
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    MoneroChatPayments.shared.announceAddresses()
                    self?.recoveryField.isHidden = true
                    self?.setReady(MoneroLocalized("Wallet restored. Synchronization will continue in the background."))
                    self?.refreshWallet()
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func refreshWallet() {
        MoneroWalletService.shared.refresh { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let snapshot):
                    self?.apply(snapshot)
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func newAddress() {
        MoneroWalletService.shared.createSubaddress { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let address):
                    self?.showAddress(address)
                    self?.statusLabel.text = MoneroLocalized("New receive subaddress created.")
                case .failure(let error):
                    self?.showError(error)
                }
            }
        }
    }

    private func apply(_ snapshot: MoneroWalletSnapshot) {
        DispatchQueue.main.async {
            self.nodeField.isHidden = true
            self.nodePickerButton.isHidden = true
            self.refreshButton.isHidden = false
            self.newAddressButton.isHidden = false
            self.createButton.isHidden = true
            self.restoreButton.isHidden = true
            self.recoveryField.isHidden = true
            self.balanceLabel.text = PaymentsDisplayPreferences.shared.isMoneroBalanceHidden
                ? MoneroLocalized("•••••• XMR available · •••••• XMR total")
                : String(format: MoneroLocalized("%@ XMR available · %@ XMR total"), MoneroPaymentRequest.decimalString(snapshot.unlockedBalance), MoneroPaymentRequest.decimalString(snapshot.balance))
            let sync = snapshot.isSynchronized
                ? MoneroLocalized("Synchronized")
                : String(format: MoneroLocalized("Synchronizing %@/%@"), String(snapshot.blockchainHeight), String(snapshot.daemonHeight))
            self.statusLabel.text = String(format: MoneroLocalized("%@ · %@ · %@"), sync, MoneroLocalized(snapshot.isConnected ? "Connected" : "Disconnected"), snapshot.nodeHost)
            self.statusLabel.textColor = snapshot.isConnected ? .secondaryLabel : .systemRed
            self.showAddress(snapshot.address)
            guard self.balanceRefreshTimer == nil else { return }
            self.balanceRefreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                self?.refreshWallet()
            }
        }
    }

    private func showAddress(_ address: String) {
        addressLabel.text = address
        qrImageView.image = URL(string: "monero:\(address)").flatMap { QRCodeGenerator().generateQRCode(url: $0) }
    }

    private func setBusy(_ text: String) {
        statusLabel.text = text
        statusLabel.textColor = .secondaryLabel
        createButton.isEnabled = false
        restoreButton.isEnabled = false
    }

    private func setReady(_ text: String) {
        statusLabel.text = text
        statusLabel.textColor = .secondaryLabel
        createButton.isEnabled = true
        restoreButton.isEnabled = true
    }

    private func showError(_ error: Error) {
        statusLabel.text = error.localizedDescription
        statusLabel.textColor = .systemRed
        createButton.isEnabled = true
        restoreButton.isEnabled = true
    }

    private func showSeed(_ seed: String) {
        let alert = UIAlertController(
            title: MoneroLocalized("Monero recovery phrase"),
            message: seed,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: MoneroLocalized("I wrote it down"), style: .default))
        present(alert, animated: true)
    }
}
