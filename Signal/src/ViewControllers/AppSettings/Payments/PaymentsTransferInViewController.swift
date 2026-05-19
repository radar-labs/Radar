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

    private enum Network {
        case lightning
        case onchain
    }

    private var selectedNetwork: Network = .lightning
    private var onchainAddress: String?

    private var qrContainerView: UIView?
    private var qrSpinner: UIActivityIndicatorView?
    private var qrImageView: UIImageView?
    private var addressLabel: UILabel?
    private var pencilButton: UIButton?
    private var lightningTabButton: UIButton?
    private var onchainTabButton: UIButton?
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

        if isOnboarding {
            buildOnboardingLayout()
        } else {
            buildLayout()
        }

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

    // MARK: - Onboarding layout (main-branch UI)

    private func buildOnboardingLayout() {
        let instructionLabel = UILabel()
        instructionLabel.text = "Send Bitcoin over the Lightning Network to the following address:"
        instructionLabel.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        instructionLabel.textColor = Theme.primaryTextColor
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0

        let qrView = buildQRView()
        let qrWrapper = UIView()
        qrWrapper.addSubview(qrView)
        qrView.autoHCenterInSuperview()
        qrView.autoPinEdge(toSuperviewEdge: .top, withInset: 16)
        qrView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 16)

        let addressLbl = buildAddressRow()

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

        embedInScrollView(mainStack)

        if let onContinue {
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
            if let scrollView = view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                scrollView.contentInset.bottom = 84
            }
        }
    }

    // MARK: - Non-onboarding layout (Figma-aligned spacing)

    private func buildLayout() {
        let instructionLabel = UILabel()
        instructionLabel.text = OWSLocalizedString(
            "PAYMENTS_ADD_FUNDS_INSTRUCTION",
            comment: "Instruction shown on the Add Funds screen telling the user which address and network to use."
        )
        instructionLabel.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        instructionLabel.textColor = Theme.primaryTextColor
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0

        let qrView = buildQRView()
        let qrWrapper = UIView()
        qrWrapper.addSubview(qrView)
        qrView.autoHCenterInSuperview()
        qrView.autoPinEdge(toSuperviewEdge: .top, withInset: 16)
        qrView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 16)

        let addressLbl = buildAddressRow()
        let networkToggle = buildNetworkToggle()
        let buttons = buildButtonsRow()

        let mainStack = UIStackView(arrangedSubviews: [
            instructionLabel,
            networkToggle,
            qrWrapper,
            addressLbl,
            buttons,
            UIView.vStretchingSpacer(),
        ])
        mainStack.axis = .vertical
        mainStack.alignment = .fill
        mainStack.setCustomSpacing(48, after: instructionLabel)
        mainStack.setCustomSpacing(32, after: networkToggle)
        mainStack.setCustomSpacing(32, after: qrWrapper)
        mainStack.setCustomSpacing(56, after: addressLbl)
        mainStack.setCustomSpacing(16, after: buttons)
        mainStack.isLayoutMarginsRelativeArrangement = true
        mainStack.layoutMargins = UIEdgeInsets(top: 18, left: 24, bottom: 32, right: 24)

        embedInScrollView(mainStack)

        prefetchOnchainAddress()
    }

    // MARK: - Onchain prefetch

    private func prefetchOnchainAddress() {
        guard onchainAddress == nil else { return }
        Task { [weak self] in
            do {
                let response = try await SUIEnvironment.shared.paymentsImplRef.fetchBitcoinTaprootAddress()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.onchainAddress = response.paymentRequest
                    if self.selectedNetwork == .onchain {
                        if let label = self.addressLabel { self.applyAddress(to: label) }
                        self.generateQR(force: true)
                    }
                }
            } catch {
                Logger.warn("Failed to prefetch onchain address: \(error)")
            }
        }
    }

    // MARK: - Scroll view helper

    private func embedInScrollView(_ mainStack: UIStackView) {
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
    }

    // MARK: - QR view

    private static func qrSize() -> CGFloat {
        return min(UIScreen.main.bounds.width - 80, 300)
    }

    private func buildQRView() -> UIView {
        let size = Self.qrSize()

        let container = UIView()
        container.backgroundColor = .white
        container.autoSetDimensions(to: .square(size))
        container.layer.cornerRadius = 16
        container.layer.borderWidth = 2.5
        container.layer.borderColor = Self.accentBlue.cgColor
        container.clipsToBounds = true

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
        spinner.startAnimating()
        generateQR(force: false)

        return container
    }

    private func currentQRString() -> String? {
        switch selectedNetwork {
        case .lightning:
            return SUIEnvironment.shared.paymentsRef.walletAddressLNURL
                ?? SUIEnvironment.shared.paymentsRef.walletLightningAddress
        case .onchain:
            return onchainAddress
        }
    }

    // Generates the QR on a background thread so it never blocks navigation animations.
    // With force=false, bails out if a QR is already rendered (used by passive refresh paths).
    // With force=true, clears the existing image and regenerates (used when toggling networks).
    private func generateQR(force: Bool) {
        guard qrContainerView != nil else { return }
        if !force, qrImageView != nil { return }

        qrImageView?.removeFromSuperview()
        qrImageView = nil
        qrSpinner?.startAnimating()

        guard let target = currentQRString() else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            let qrImage = QRCodeGenerator().generateUnstyledQRCode(data: Data(target.utf8))
            await MainActor.run { [weak self] in
                guard let self, let container = self.qrContainerView, let qrImage else { return }
                // Drop result if the user toggled networks while we were generating.
                guard self.currentQRString() == target else { return }
                let iv = UIImageView(image: qrImage)
                iv.layer.magnificationFilter = .nearest
                iv.layer.minificationFilter = .nearest
                container.insertSubview(iv, at: 0)
                iv.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
                self.qrImageView = iv
                self.qrSpinner?.stopAnimating()
            }
        }
    }

    // MARK: - Address row

    private func buildAddressRow() -> UIView {
        let label = UILabel()
        label.numberOfLines = 1
        label.autoSetDimension(.width, toSize: Self.qrSize(), relation: .lessThanOrEqual)
        addressLabel = label
        applyAddress(to: label)

        let pencilBtn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        pencilBtn.setImage(UIImage(systemName: "pencil", withConfiguration: config), for: .normal)
        pencilBtn.tintColor = Theme.primaryTextColor.withAlphaComponent(0.4)
        pencilBtn.addTarget(self, action: #selector(didTapEdit), for: .touchUpInside)
        pencilButton = pencilBtn

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
        switch selectedNetwork {
        case .lightning:
            applyLightningAddress(to: label)
        case .onchain:
            applyOnchainAddress(to: label)
        }
    }

    private func applyLightningAddress(to label: UILabel) {
        label.attributedText = nil
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .natural
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

    private func applyOnchainAddress(to label: UILabel) {
        label.attributedText = nil
        guard let address = onchainAddress else {
            label.text = OWSLocalizedString(
                "PAYMENTS_WALLET_ADDRESS_LOADING",
                comment: "Placeholder shown in the wallet address field while the Lightning address is being loaded."
            )
            label.font = UIFont.systemFont(ofSize: 17)
            label.textColor = Theme.primaryTextColor.withAlphaComponent(0.4)
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.textAlignment = .center
            return
        }
        let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        let groupSize = 4
        var groups: [String] = []
        var cursor = address.startIndex
        while cursor < address.endIndex {
            let end = address.index(cursor, offsetBy: groupSize, limitedBy: address.endIndex) ?? address.endIndex
            groups.append(String(address[cursor..<end]))
            cursor = end
        }
        let attributed = NSMutableAttributedString()
        for (index, group) in groups.enumerated() {
            let color = index.isMultiple(of: 2) ? Theme.primaryTextColor : Theme.ternaryTextColor
            if index > 0 {
                attributed.append(NSAttributedString(string: " ", attributes: [.font: font]))
            }
            attributed.append(NSAttributedString(string: group, attributes: [
                .font: font,
                .foregroundColor: color,
            ]))
        }
        label.attributedText = attributed
        label.numberOfLines = 3
        label.lineBreakMode = .byCharWrapping
        label.textAlignment = .center
    }

    private func refreshWalletAddressUI() {
        if let label = addressLabel {
            applyAddress(to: label)
        }
        generateQR(force: selectedNetwork == .lightning)
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

    private func buildNetworkToggle() -> UIView {
        let lightningBtn = makeNetworkTabButton(title: "Lightning", systemIcon: "bolt.fill")
        lightningBtn.addTarget(self, action: #selector(didTapLightningTab), for: .touchUpInside)
        let onchainBtn = makeNetworkTabButton(title: "Onchain", systemIcon: "bitcoinsign.circle")
        onchainBtn.addTarget(self, action: #selector(didTapOnchainTab), for: .touchUpInside)

        lightningTabButton = lightningBtn
        onchainTabButton = onchainBtn
        applyTabStyling()

        let tabStack = UIStackView(arrangedSubviews: [lightningBtn, onchainBtn])
        tabStack.axis = .horizontal
        tabStack.spacing = 0
        tabStack.alignment = .center
        tabStack.distribution = .fillEqually

        let container = UIView()
        container.backgroundColor = UIColor(red: 233/255, green: 233/255, blue: 234/255, alpha: 1)
        container.layer.cornerRadius = 24
        container.layer.masksToBounds = true
        container.addSubview(tabStack)
        tabStack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4))
        container.autoSetDimension(.height, toSize: 48)

        let wrapper = UIView()
        wrapper.addSubview(container)
        container.autoHCenterInSuperview()
        container.autoPinEdge(toSuperviewEdge: .top)
        container.autoPinEdge(toSuperviewEdge: .bottom)
        return wrapper
    }

    private func makeNetworkTabButton(title: String, systemIcon: String) -> UIButton {
        var cfg = UIButton.Configuration.plain()
        cfg.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 13, weight: .medium)])
        )
        cfg.image = UIImage(systemName: systemIcon)
        cfg.imagePlacement = .leading
        cfg.imagePadding = 6
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 14)
        cfg.background.cornerRadius = 20
        cfg.background.backgroundColor = .clear
        return UIButton(configuration: cfg)
    }

    private func applyTabStyling() {
        let isLightning = (selectedNetwork == .lightning)
        if let lBtn = lightningTabButton, var lCfg = lBtn.configuration {
            lCfg.background.backgroundColor = isLightning ? .white : .clear
            lCfg.baseForegroundColor = isLightning ? Self.accentBlue : UIColor.black.withAlphaComponent(0.5)
            lBtn.configuration = lCfg
        }
        if let oBtn = onchainTabButton, var oCfg = oBtn.configuration {
            oCfg.background.backgroundColor = isLightning ? .clear : .white
            oCfg.baseForegroundColor = isLightning ? UIColor.black.withAlphaComponent(0.5) : Self.accentBlue
            oBtn.configuration = oCfg
        }
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

    // MARK: - Actions

    private func currentDisplayedAddress() -> String? {
        switch selectedNetwork {
        case .lightning:
            return SUIEnvironment.shared.paymentsRef.walletLightningAddress
        case .onchain:
            return onchainAddress
        }
    }

    @objc private func didTapLightningTab() {
        guard selectedNetwork != .lightning else { return }
        selectedNetwork = .lightning
        applyTabStyling()
        pencilButton?.isHidden = false
        if let label = addressLabel { applyAddress(to: label) }
        generateQR(force: true)
    }

    @objc private func didTapOnchainTab() {
        guard selectedNetwork != .onchain else { return }
        selectedNetwork = .onchain
        applyTabStyling()
        pencilButton?.isHidden = true
        if let label = addressLabel { applyAddress(to: label) }

        if onchainAddress != nil {
            generateQR(force: true)
            return
        }

        // No cached address yet — show spinner while fetching.
        qrImageView?.removeFromSuperview()
        qrImageView = nil
        qrSpinner?.startAnimating()
        Task { [weak self] in
            do {
                let response = try await SUIEnvironment.shared.paymentsImplRef.fetchBitcoinTaprootAddress()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.onchainAddress = response.paymentRequest
                    guard self.selectedNetwork == .onchain else { return }
                    if let label = self.addressLabel { self.applyAddress(to: label) }
                    self.generateQR(force: true)
                }
            } catch {
                Logger.warn("Failed to fetch onchain address: \(error)")
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.selectedNetwork == .onchain else { return }
                    self.presentToast(text: OWSLocalizedString(
                        "PAYMENTS_ADD_FUNDS_ONCHAIN_FETCH_FAILED",
                        comment: "Toast shown when fetching the on-chain Bitcoin receive address fails on the Add Funds screen."
                    ))
                    self.selectedNetwork = .lightning
                    self.applyTabStyling()
                    self.pencilButton?.isHidden = false
                    if let label = self.addressLabel { self.applyAddress(to: label) }
                    self.generateQR(force: true)
                }
            }
        }
    }

    @objc private func didTapCopy() {
        guard let address = currentDisplayedAddress() else { return }
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
        guard let address = currentDisplayedAddress() else { return }
        AttachmentSharing.showShareUI(for: address, sender: self)
    }
}
