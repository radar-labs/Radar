//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class RadarUsernameViewController: OWSViewController {

    private let oldUsername: String
    private let onConfirm: (String) async throws -> Void

    private lazy var usernameField = OWSTextField(
        placeholder: "username",
        returnKeyType: .done,
        autocorrectionType: .no,
        autocapitalizationType: .none,
        clearButtonMode: .whileEditing,
        delegate: self,
        editingChanged: { [unowned self] in self.usernameDidChange() },
        returnPressed: { [unowned self] in if self.canConfirm { self.didTapConfirm() } }
    )

    private let statusLabel = UILabel()
    private var confirmButton = OWSFlatButton()
    private var checkTask: Task<Void, Never>?
    private var canConfirm = false

    init(oldUsername: String, onConfirm: @escaping (String) async throws -> Void) {
        self.oldUsername = oldUsername
        self.onConfirm = onConfirm
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        let logoView = UIImageView(image: UIImage(named: "radar-logo"))
        logoView.contentMode = .scaleAspectFit

        let logoContainer = UIView()
        logoContainer.addSubview(logoView)
        logoView.autoSetDimensions(to: .square(82))
        logoView.autoCenterInSuperview()
        // Explicit height so the stack view measures this container correctly.
        logoContainer.autoSetDimension(.height, toSize: 82)

        let titleLabel = UILabel()
        titleLabel.text = "Your Radar Username"
        titleLabel.font = UIFont.dynamicTypeTitle2Clamped.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Set your custom identifier for receiving payments on Radar"
        subtitleLabel.font = .dynamicTypeSubheadlineClamped
        subtitleLabel.textColor = Theme.primaryTextColor
        subtitleLabel.alpha = 0.5
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        // Pill-shaped text field container
        let fieldContainer = UIView()
        fieldContainer.backgroundColor = UIColor(red: 120/255, green: 120/255, blue: 128/255, alpha: 0.16)
        fieldContainer.layer.cornerRadius = 26
        fieldContainer.autoSetDimension(.height, toSize: 52)

        usernameField.text = oldUsername
        usernameField.font = .dynamicTypeBodyClamped
        usernameField.textColor = Theme.primaryTextColor
        fieldContainer.addSubview(usernameField)
        usernameField.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)
        usernameField.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)
        usernameField.autoVCenterInSuperview()

        let domainLabel = UILabel()
        domainLabel.text = "@radar.cash"
        domainLabel.font = UIFont.dynamicTypeBodyClamped.semibold()
        domainLabel.textColor = Theme.accentBlueColor
        domainLabel.setContentHuggingHigh()

        let fieldRow = UIStackView(arrangedSubviews: [fieldContainer, domainLabel])
        fieldRow.axis = .horizontal
        fieldRow.alignment = .center
        fieldRow.spacing = 12

        statusLabel.font = .dynamicTypeFootnoteClamped
        statusLabel.textAlignment = .center
        statusLabel.isHidden = true

        let inputStack = UIStackView(arrangedSubviews: [fieldRow, statusLabel])
        inputStack.axis = .vertical
        inputStack.spacing = 8
        inputStack.alignment = .fill

        confirmButton = OWSFlatButton.button(
            title: "Confirm",
            font: UIFont.dynamicTypeHeadline.semibold(),
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(didTapConfirm),
            cornerRadius: 14
        )
        confirmButton.autoSetDimension(.height, toSize: 52)
        confirmButton.setEnabled(false)

        let skipButton = OWSFlatButton.button(
            title: "Cancel",
            font: .dynamicTypeSubheadlineClamped.semibold(),
            titleColor: .ows_accentBlue,
            backgroundColor: .clear,
            target: self,
            selector: #selector(didTapSkip)
        )
        skipButton.autoSetHeightUsingFont()

        // Header + input are grouped together directly below one another.
        let topContentStack = UIStackView(arrangedSubviews: [
            logoContainer,
            UIView.spacer(withHeight: 24),
            titleLabel,
            UIView.spacer(withHeight: 8),
            subtitleLabel,
            UIView.spacer(withHeight: 32),
            inputStack,
        ])
        topContentStack.axis = .vertical
        topContentStack.alignment = .fill

        // Small fixed top inset + large flexible bottom spacer = content sits in the upper third.
        let bottomSpacer = UIView.vStretchingSpacer()

        let rootView = UIStackView(arrangedSubviews: [
            topContentStack,
            bottomSpacer,
            confirmButton,
            UIView.spacer(withHeight: 16),
            skipButton,
        ])
        rootView.axis = .vertical
        rootView.alignment = .fill
        rootView.isLayoutMarginsRelativeArrangement = true
        rootView.layoutMargins = UIEdgeInsets(top: 48, left: 36, bottom: 16, right: 36)

        // A UIScrollView root prevents UIKit's automatic keyboard avoidance from
        // resizing the view. The keyboard slides over the content instead of pushing it.
        // keyboardDismissMode provides swipe-to-dismiss; the tap gesture below handles tap-to-dismiss.
        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false

        view.addSubview(scrollView)
        scrollView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        scrollView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        scrollView.autoPinWidthToSuperview()

        // Content view sized to exactly match the scroll view frame — no actual scrolling.
        let contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        contentView.addSubview(rootView)
        rootView.autoPinEdgesToSuperviewEdges()

        let dismissKeyboardGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissKeyboardGesture.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(dismissKeyboardGesture)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        usernameField.becomeFirstResponder()
        fetchAndPrintBitcoinAddress()
    }

    private func fetchAndPrintBitcoinAddress() {
        Task {
            do {
                print("[RadarUsername] Calling receivePayment with .bitcoinAddress...")
                let response = try await SUIEnvironment.shared.paymentsImplRef.fetchBitcoinAddress()
                print("[RadarUsername] ---- receivePayment response ----")
                print("[RadarUsername] response: \(response)")
                print("[RadarUsername] response.paymentRequest: \(response.paymentRequest)")
                print("[RadarUsername] response.fee: \(response.fee)")
                print("[RadarUsername] ----------------------------------")
            } catch {
                print("[RadarUsername] receivePayment failed with error: \(error)")
            }
        }
    }

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - Username availability

    private func usernameDidChange() {
        statusLabel.isHidden = true
        canConfirm = false
        confirmButton.setEnabled(false)

        checkTask?.cancel()

        guard let username = usernameField.text, !username.isEmpty else { return }

        checkTask = Task { [weak self, username] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let available = try await SUIEnvironment.shared.paymentsImplRef.isUsernameAvailable(username)
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled, let self else { return }
                    self.showAvailabilityStatus(available)
                }
            } catch {
                // Silently ignore; user can still try confirming
            }
        }
    }

    private func showAvailabilityStatus(_ available: Bool) {
        statusLabel.isHidden = false
        if available {
            statusLabel.text = "✓ Username Available"
            statusLabel.textColor = UIColor(red: 70/255, green: 184/255, blue: 39/255, alpha: 1)
            canConfirm = true
            confirmButton.setEnabled(true)
        } else {
            statusLabel.text = "✗ Username Unavailable"
            statusLabel.textColor = .ows_accentRed
            canConfirm = false
            confirmButton.setEnabled(false)
        }
    }

    // MARK: - Actions

    @objc
    private func didTapConfirm() {
        guard canConfirm, let username = usernameField.text, !username.isEmpty else { return }

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            presentationDelay: 0.25,
            asyncBlock: { [weak self] modal in
                guard let self else { return }
                let result = await Result { try await self.onConfirm(username) }
                modal.dismissIfNotCanceled { [weak self] in
                    guard let self else { return }
                    do {
                        _ = try result.get()
                        self.navigationController?.popViewController(animated: true)
                    } catch {
                        self.showErrorAlert(error)
                    }
                }
            }
        )
    }

    @objc
    private func didTapSkip() {
        navigationController?.popViewController(animated: true)
    }

    private func showErrorAlert(_ error: Error) {
        let alert = ActionSheetController(
            title: CommonStrings.errorAlertTitle,
            message: error.localizedDescription
        )
        alert.addAction(ActionSheetAction(title: CommonStrings.okButton))
        presentActionSheet(alert)
    }
}

extension RadarUsernameViewController: UITextFieldDelegate {
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        return TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxGlyphCount: WalletAddressEditViewController.addressGlyphLimit
        )
    }
}
