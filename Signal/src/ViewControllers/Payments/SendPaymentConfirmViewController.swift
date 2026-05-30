// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only

import SignalServiceKit
public import SignalUI

public class SendPaymentConfirmViewController: OWSViewController {

    private let paymentInfo: SendPaymentInfo
    private weak var completionDelegate: SendPaymentCompletionDelegate?

    private let balanceLabel = SendPaymentHelper.buildBottomLabel()
    private var helper: SendPaymentHelper?

    private let preparedPaymentTask = AtomicOptional<Task<PreparedPayment, any Error>>(nil, lock: .init())

    public init(paymentInfo: SendPaymentInfo, completionDelegate: SendPaymentCompletionDelegate) {
        self.paymentInfo = paymentInfo
        self.completionDelegate = completionDelegate
        super.init()
        helper = SendPaymentHelper(delegate: self)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = nil
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        buildContents()
        startOptimisticPreparation()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        helper?.refreshObservedValues()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !UIDevice.current.isIPad && view.window?.windowScene?.interfaceOrientation != .portrait {
            UIDevice.current.ows_setOrientation(.portrait)
        }
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.isIPad ? .all : .portrait
    }

    // MARK: - UI

    private func buildContents() {
        let totalAmount = paymentInfo.paymentAmount.plus(paymentInfo.estimatedFeeAmount)

        let amountValueLabel = UILabel()
        amountValueLabel.text = formatAmountNumber(totalAmount)
        amountValueLabel.font = UIFont.systemFont(ofSize: 48, weight: .medium)
        amountValueLabel.textColor = Theme.primaryTextColor
        amountValueLabel.setCompressionResistanceHigh()

        let amountUnitLabel = UILabel()
        amountUnitLabel.text = unitString(for: totalAmount)
        amountUnitLabel.font = UIFont.systemFont(ofSize: 48, weight: .regular)
        amountUnitLabel.textColor = Theme.primaryTextColor.withAlphaComponent(0.5)

        let amountRow = UIStackView(arrangedSubviews: [amountValueLabel, amountUnitLabel])
        amountRow.axis = .horizontal
        amountRow.alignment = .center
        amountRow.spacing = 8

        updateBalanceLabel()
        balanceLabel.textAlignment = .center

        let headerStack = UIStackView(arrangedSubviews: [amountRow, balanceLabel])
        headerStack.axis = .vertical
        headerStack.alignment = .center
        headerStack.spacing = 4

        let recipientName = recipientDisplayName()
        let recipientRowView = buildDetailRow(
            title: String(
                format: OWSLocalizedString(
                    "PAYMENTS_NEW_PAYMENT_RECIPIENT_AMOUNT_FORMAT",
                    comment: "Format for the 'payment recipient amount' indicator. Embeds {{ the name of the recipient of the payment }}."
                ),
                recipientName
            ),
            subtitle: formatMobileCoinAmount(paymentInfo.paymentAmount),
            trailing: fiatString(for: paymentInfo.paymentAmount)
        )

        let feeRowView = buildDetailRow(
            title: OWSLocalizedString(
                "PAYMENTS_NEW_PAYMENT_ESTIMATED_FEE",
                comment: "Label for the 'payment estimated fee' indicator."
            ),
            subtitle: formatMobileCoinAmount(paymentInfo.estimatedFeeAmount),
            trailing: fiatString(for: paymentInfo.estimatedFeeAmount),
            showInfoIcon: true
        )
        feeRowView.isUserInteractionEnabled = true
        feeRowView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapFeeInfo)))

        let card1 = buildCard(rows: [recipientRowView, feeRowView])

        let totalRowView = buildDetailRow(
            title: OWSLocalizedString(
                "PAYMENTS_NEW_PAYMENT_PAYMENT_TOTAL",
                comment: "Label for the 'total payment amount' indicator."
            ),
            subtitle: formatMobileCoinAmount(totalAmount),
            trailing: fiatString(for: totalAmount)
        )
        let card2 = buildCard(rows: [totalRowView])

        let payButton = buildPayButton()

        let rootStack = UIStackView(arrangedSubviews: [
            UIView.spacer(withHeight: SendPaymentHelper.minTopVSpacing),
            headerStack,
            UIView.spacer(withHeight: 24),
            card1,
            UIView.spacer(withHeight: 24),
            card2,
            UIView.vStretchingSpacer(),
            payButton,
            UIView.spacer(withHeight: SendPaymentHelper.vSpacingAboveBalance)
        ])
        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func buildDetailRow(
        title: String,
        subtitle: String,
        trailing: String?,
        showInfoIcon: Bool = false
    ) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17)
        titleLabel.textColor = Theme.primaryTextColor

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = Theme.secondaryTextAndIconColor

        let titleRowView: UIView
        if showInfoIcon {
            let infoIcon = UIImageView.withTemplateImageName("info-compact", tintColor: Theme.secondaryTextAndIconColor)
            infoIcon.autoSetDimensions(to: .square(16))
            infoIcon.setCompressionResistanceHigh()
            let titleRow = UIStackView(arrangedSubviews: [titleLabel, infoIcon])
            titleRow.axis = .horizontal
            titleRow.alignment = .center
            titleRow.spacing = 6
            titleRowView = titleRow
        } else {
            titleRowView = titleLabel
        }

        let leftStack = UIStackView(arrangedSubviews: [titleRowView, subtitleLabel])
        leftStack.axis = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 2

        let trailingLabel = UILabel()
        trailingLabel.text = trailing ?? ""
        trailingLabel.font = .systemFont(ofSize: 17)
        trailingLabel.textColor = Theme.secondaryTextAndIconColor
        trailingLabel.textAlignment = .right
        trailingLabel.setCompressionResistanceHigh()
        trailingLabel.setContentHuggingHigh()

        let rowStack = UIStackView(arrangedSubviews: [leftStack, trailingLabel])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 8
        rowStack.isLayoutMarginsRelativeArrangement = true
        rowStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)

        return rowStack
    }

    private func buildCard(rows: [UIView]) -> UIView {
        rows.dropLast().forEach { row in
            let sep = UIView()
            sep.backgroundColor = Theme.hairlineColor
            sep.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(sep)
            NSLayoutConstraint.activate([
                sep.heightAnchor.constraint(equalToConstant: 0.5),
                sep.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
                sep.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                sep.bottomAnchor.constraint(equalTo: row.bottomAnchor)
            ])
        }

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 0
        stack.backgroundColor = OWSTableViewController2.cellBackgroundColor(isUsingPresentedStyle: true)
        stack.layer.cornerRadius = 16
        stack.clipsToBounds = true
        return stack
    }

    private func buildPayButton() -> UIView {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .ows_accentBlue
        config.baseForegroundColor = .white
        config.title = OWSLocalizedString(
            "PAYMENTS_NEW_PAYMENT_PAY_BUTTON",
            comment: "Label for the 'pay' button in the 'send payment' UI."
        )
        config.image = UIImage(systemName: "checkmark.circle")
        config.imagePadding = 8
        config.imagePlacement = .leading
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var updated = attrs
            updated.font = UIFont.systemFont(ofSize: 17, weight: .bold)
            return updated
        }
        config.cornerStyle = .fixed
        config.background.cornerRadius = 14
        config.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)

        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(didTapPayButton), for: .touchUpInside)
        button.autoSetDimension(.height, toSize: 52)
        return button
    }

    // MARK: - Helpers

    private func formatAmountNumber(_ amount: TSPaymentAmount) -> String {
        if PaymentsDisplayPreferences.shared.isSatoshiEnabled {
            return "\(amount.picoMob)"
        }
        return PaymentsFormat.format(paymentAmount: amount, isShortForm: false)
    }

    private func unitString(for amount: TSPaymentAmount) -> String {
        if PaymentsDisplayPreferences.shared.isSatoshiEnabled {
            return PaymentsConstants.satoshiCurrencyIdentifier
        }
        return amount.currency.identifier
    }

    private func formatMobileCoinAmount(_ amount: TSPaymentAmount) -> String {
        SendPaymentHelper.formatCryptoCoinAmount(amount)
    }

    private func fiatString(for amount: TSPaymentAmount) -> String? {
        guard let conversion = paymentInfo.currencyConversion else { return nil }
        return PaymentsFormat.formatAsFiatCurrency(paymentAmount: amount, currencyConversionInfo: conversion)
    }

    private func recipientDisplayName() -> String {
        guard let recipient = paymentInfo.recipient as? SendPaymentRecipientImpl else { return "" }
        switch recipient {
        case .address(let address):
            return SSKEnvironment.shared.databaseStorageRef.read { tx in
                SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: tx).resolvedValue()
            }
        case .publicAddress(let inputType):
            return PaymentsImpl.formatForDisplay(inputType: inputType)
        }
    }

    private func updateBalanceLabel() {
        helper?.updateBalanceLabel(balanceLabel)
    }

    // MARK: - Optimistic preparation

    private func startOptimisticPreparation() {
        let task = Task {
            return try await SUIEnvironment.shared.paymentsSwiftRef.prepareOutgoingPayment(
                recipient: paymentInfo.recipient,
                paymentAmount: paymentInfo.paymentAmount,
                memoMessage: paymentInfo.memoMessage,
                isOutgoingTransfer: paymentInfo.isOutgoingTransfer,
                canDefragment: false
            )
        }
        preparedPaymentTask.set(task)
        Task {
            do {
                _ = try await task.value
                Logger.info("Pre-prepared payment ready.")
            } catch {
                Logger.warn("Could not pre-prepare payment: \(error).")
            }
        }
    }

    // MARK: - Events

    @objc
    private func didTapPayButton() {
        guard let completionDelegate else { return }
        let actionSheet = SendPaymentCompletionActionSheet(
            mode: .payment(paymentInfo: paymentInfo),
            delegate: completionDelegate,
            preparedTask: preparedPaymentTask.get(),
            startAtProgressStep: true
        )
        actionSheet.present(fromViewController: self)
    }

    @objc
    private func didTapFeeInfo() {
        PaymentsSettingsViewController.showCurrencyConversionInfoAlert(fromViewController: self)
    }
}

// MARK: -

extension SendPaymentConfirmViewController: SendPaymentHelperDelegate {
    public func balanceDidChange() {
        updateBalanceLabel()
    }

    public func currencyConversionDidChange() {}
}
