//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsTransferInViewController: OWSViewController {

    private static let accentBlue = UIColor(red: 0, green: 105/255, blue: 254/255, alpha: 1)
    private static let grayFill   = UIColor(red: 120/255, green: 120/255, blue: 128/255, alpha: 0.16)

    private let isOnboarding: Bool
    private let onContinue: (() -> Void)?

    private var qrContainerView: UIView?
    private var qrSpinner: UIActivityIndicatorView?
    private var addressLabel: UILabel?
    private var walletObserver: NSObjectProtocol?

    init(isOnboarding: Bool = false, onContinue: (() -> Void)? = nil) {
        self.isOnboarding = isOnboarding
        self.onContinue = onContinue
        super.init()
    }

    deinit {
        if let walletObserver {
            NotificationCenter.default.removeObserver(walletObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_ADD_MONEY",
            comment: "Label for 'add money' view in the payment settings."
        )
        if !isOnboarding {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done, target: self, action: #selector(didTapDone)
            )
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: Theme.iconImage(.buttonShare), style: .plain,
            target: self, action: #selector(didTapShare)
        )

        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
        buildLayout()

        walletObserver = NotificationCenter.default.addObserver(
            forName: PaymentsImpl.walletAddressDidLoad,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshWalletAddressUI()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
    }

    // MARK: - Layout

    private func buildLayout() {
        let instructionLabel = UILabel()
        instructionLabel.text = "Send Bitcoin over the Lightning Network to the following address:"
        instructionLabel.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        instructionLabel.textColor = Theme.primaryTextColor
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0

        // QR code centred in a full-width wrapper (16pt top/bottom gives it breathing room)
        let qrView = buildQRView()
        let qrWrapper = UIView()
        qrWrapper.addSubview(qrView)
        qrView.autoHCenterInSuperview()
        qrView.autoPinEdge(toSuperviewEdge: .top, withInset: 16)
        qrView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 16)

        let addressLbl = buildAddressRow()

        // Buttons centred in a full-width wrapper
        let buttons = buildButtonsRow()
        let buttonsWrapper = UIView()
        buttonsWrapper.addSubview(buttons)
        buttons.autoHCenterInSuperview()
        buttons.autoPinEdge(toSuperviewEdge: .top)
        buttons.autoPinEdge(toSuperviewEdge: .bottom)

        let mainStack = UIStackView(arrangedSubviews: [
            instructionLabel,
            qrWrapper,
            addressLbl,
            buttonsWrapper,
            UIView.vStretchingSpacer(),
        ])
        mainStack.axis = .vertical
        mainStack.alignment = .fill
        mainStack.setCustomSpacing(24, after: instructionLabel)
        mainStack.setCustomSpacing(24, after: qrWrapper)
        mainStack.setCustomSpacing(24, after: addressLbl)
        mainStack.setCustomSpacing(16, after: buttonsWrapper)
        mainStack.isLayoutMarginsRelativeArrangement = true
        mainStack.layoutMargins = UIEdgeInsets(top: 18, left: 24, bottom: 32, right: 24)

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false

        view.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()

        let contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        contentView.addSubview(mainStack)
        mainStack.autoPinEdgesToSuperviewEdges()

        if isOnboarding, let onContinue {
            let continueContainer = makeContinueButton(action: onContinue)
            view.addSubview(continueContainer)
            continueContainer.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                continueContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                continueContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                continueContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
            // Reserve space so scroll content is never hidden under the pinned button.
            // Button height (≥52) + top inset (16) + bottom inset (16) = 84pt minimum.
            scrollView.contentInset.bottom = 84
        }
    }

    // MARK: - QR view

    private func buildQRView() -> UIView {
        let size: CGFloat = min(UIScreen.main.bounds.width - 80, 300)

        let container = UIView()
        container.backgroundColor = .white
        container.autoSetDimensions(to: .square(size))
        container.layer.cornerRadius = 16
        container.layer.borderWidth = 2.5
        container.layer.borderColor = Self.accentBlue.cgColor
        container.clipsToBounds = true

        // White square with radar logo centred on the QR
        let iconBox = UIView()
        iconBox.backgroundColor = .white
        iconBox.layer.cornerRadius = 6
        iconBox.autoSetDimensions(to: .square(52))

        let logo = UIImageView(image: UIImage(named: "radar-logo"))
        logo.contentMode = .scaleAspectFit
        iconBox.addSubview(logo)
        logo.autoSetDimensions(to: .square(42))
        logo.autoCenterInSuperview()

        container.addSubview(iconBox)
        iconBox.autoCenterInSuperview()

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Self.accentBlue
        container.addSubview(spinner)
        spinner.autoCenterInSuperview()
        qrSpinner = spinner

        qrContainerView = container

        if SUIEnvironment.shared.paymentsRef.walletAddressLNURL != nil {
            populateQRImage(in: container)
        } else {
            spinner.startAnimating()
        }

        return container
    }

    private func populateQRImage(in container: UIView) {
        guard !container.subviews.contains(where: { $0 is UIImageView }) else { return }
        guard let lnurl = SUIEnvironment.shared.paymentsRef.walletAddressLNURL,
              let qrImage = QRCodeGenerator().generateUnstyledQRCode(data: Data(lnurl.utf8)) else { return }
        let qrImageView = UIImageView(image: qrImage)
        qrImageView.layer.magnificationFilter = .nearest
        qrImageView.layer.minificationFilter = .nearest
        container.insertSubview(qrImageView, at: 0)
        qrImageView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        qrSpinner?.stopAnimating()
    }

    // MARK: - Address label

    private func buildAddressRow() -> UIView {
        let label = UILabel()
        label.numberOfLines = 1
        addressLabel = label
        applyAddress(to: label)

        let pencilBtn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        pencilBtn.setImage(UIImage(systemName: "pencil", withConfiguration: config), for: .normal)
        pencilBtn.tintColor = Theme.primaryTextColor.withAlphaComponent(0.4)
        pencilBtn.addTarget(self, action: #selector(didTapEdit), for: .touchUpInside)

        let hStack = UIStackView(arrangedSubviews: [label, pencilBtn])
        hStack.axis = .horizontal
        hStack.spacing = 8
        hStack.alignment = .center

        let wrapper = UIView()
        wrapper.addSubview(hStack)
        hStack.autoHCenterInSuperview()
        hStack.autoPinEdge(toSuperviewEdge: .top)
        hStack.autoPinEdge(toSuperviewEdge: .bottom)

        return wrapper
    }

    private func applyAddress(to label: UILabel) {
        guard let address = SUIEnvironment.shared.paymentsRef.walletLightningAddress else {
            label.text = OWSLocalizedString(
                "PAYMENTS_WALLET_ADDRESS_LOADING",
                comment: "Placeholder shown in the wallet address field while the Lightning address is being loaded."
            )
            label.font = UIFont.systemFont(ofSize: 17)
            label.textColor = Theme.primaryTextColor.withAlphaComponent(0.4)
            return
        }
        let atRange = (address as NSString).range(of: "@")
        if atRange.location != NSNotFound {
            let username = (address as NSString).substring(to: atRange.location)
            let domain   = (address as NSString).substring(from: atRange.location)
            let font = UIFont.systemFont(ofSize: 20, weight: .medium)
            let baseAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.primaryTextColor]
            let blueAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Self.accentBlue]
            let str = NSMutableAttributedString(string: username, attributes: baseAttrs)
            str.append(NSAttributedString(string: domain, attributes: blueAttrs))
            label.attributedText = str
        } else {
            label.text = address
            label.font = UIFont.systemFont(ofSize: 20, weight: .medium)
            label.textColor = Theme.primaryTextColor
        }
    }

    private func refreshWalletAddressUI() {
        if let container = qrContainerView {
            populateQRImage(in: container)
        }
        if let label = addressLabel {
            applyAddress(to: label)
        }
    }

    // MARK: - Buttons

    private func buildButtonsRow() -> UIStackView {
        let copyBtn = makePillButton(
            title: "Copy",
            systemIcon: "square.on.square",
            background: Self.grayFill,
            foreground: Theme.primaryTextColor
        )
        copyBtn.addTarget(self, action: #selector(didTapCopy), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [copyBtn])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        return row
    }

    private func makeContinueButton(action: @escaping () -> Void) -> UIView {
        var cfg = UIButton.Configuration.filled()
        cfg.attributedTitle = AttributedString(
            CommonStrings.continueButton,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .bold)])
        )
        cfg.baseBackgroundColor = Self.accentBlue
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .large
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)

        let btn = UIButton(configuration: cfg, primaryAction: UIAction { _ in action() })
        btn.autoSetDimension(.height, toSize: 52, relation: .greaterThanOrEqual)

        let wrapper = UIView()
        wrapper.addSubview(btn)
        btn.autoPinEdge(toSuperviewEdge: .top, withInset: 16)
        btn.autoPinEdge(toSuperviewEdge: .bottom, withInset: 16)
        btn.autoPinEdge(toSuperviewEdge: .leading, withInset: 24)
        btn.autoPinEdge(toSuperviewEdge: .trailing, withInset: 24)
        return wrapper
    }

    private func makePillButton(
        title: String,
        systemIcon: String,
        background: UIColor,
        foreground: UIColor
    ) -> UIButton {
        var cfg = UIButton.Configuration.filled()
        cfg.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .medium)])
        )
        cfg.image = UIImage(systemName: systemIcon)
        cfg.imagePlacement = .trailing
        cfg.imagePadding = 8
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        cfg.baseBackgroundColor = background
        cfg.baseForegroundColor = foreground
        cfg.cornerStyle = .capsule

        let btn = UIButton(configuration: cfg)
        btn.autoSetDimension(.height, toSize: 48)
        return btn
    }

    // MARK: - Actions

    @objc private func didTapCopy() {
        guard let address = SUIEnvironment.shared.paymentsRef.walletLightningAddress else { return }
        UIPasteboard.general.string = address
        presentToast(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_ADD_MONEY_WALLET_ADDRESS_COPIED",
            comment: "Indicator that the payments wallet address has been copied to the pasteboard."
        ))
    }

    @objc private func didTapEdit() {
        guard let username = SUIEnvironment.shared.paymentsImplRef.walletLightningAddressUsername else { return }
        let vc = RadarUsernameViewController(oldUsername: username) { newUsername in
            try await SUIEnvironment.shared.paymentsImplRef.registerUsername(newUsername)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func didTapDone() {
        dismiss(animated: true)
    }

    @objc private func didTapShare() {
        guard let address = SUIEnvironment.shared.paymentsRef.walletLightningAddress else { return }
        AttachmentSharing.showShareUI(for: address, sender: self)
    }
}
