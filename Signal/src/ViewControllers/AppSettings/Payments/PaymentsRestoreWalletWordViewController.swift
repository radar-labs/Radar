//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsRestoreWalletWordViewController: OWSViewController, UITextFieldDelegate {

    private weak var restoreWalletDelegate: PaymentsRestoreWalletDelegate?

    private let partialPassphrase: PartialPaymentsPassphrase

    private let wordIndex: Int

    // Radar: the first word page lets the user pick a 12-word (Breez) or 24-word phrase.
    private static let switcherAccentBlue = UIColor(red: 0, green: 105 / 255, blue: 254 / 255, alpha: 1)
    private static let switcherContainerFill = UIColor(red: 233 / 255, green: 233 / 255, blue: 234 / 255, alpha: 1)

    private var twelveWordTabButton: UIButton?
    private var twentyFourWordTabButton: UIButton?

    private lazy var textField: UITextField = {
        let textField = UITextField()
        textField.textColor = .Signal.label
        textField.tintColor = .Signal.label // caret color
        textField.font = .dynamicTypeBodyClamped
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addAction(
            UIAction { [weak self] _ in self?.textFieldDidChange() },
            for: .editingChanged,
        )
        return textField
    }()

    private lazy var warningLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .dynamicTypeCaption1
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .Signal.red
        label.text = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INVALID_WORD",
            comment: "Error indicating that the user has entered an invalid word in the 'enter word' step of the 'restore payments wallet' views.",
        )
        label.alpha = 0
        return label
    }()

    private var wordText: String? {
        textField.text?.strippedOrNil?.lowercased()
    }

    private var hasValidWord: Bool {
        isValidWord(wordText)
    }

    private func isValidWord(_ wordText: String?) -> Bool {
        guard let wordText, !wordText.isEmpty else { return false }
        return SUIEnvironment.shared.paymentsSwiftRef.isValidPassphraseWord(wordText)
    }

    func clearInput() {
        partialPassphrase.reset()
        textField.text = ""
    }

    init(
        restoreWalletDelegate: PaymentsRestoreWalletDelegate,
        partialPassphrase: PartialPaymentsPassphrase,
        wordIndex: Int,
    ) {
        self.restoreWalletDelegate = restoreWalletDelegate
        self.partialPassphrase = partialPassphrase
        self.wordIndex = wordIndex

        super.init()

        textField.text = partialPassphrase.getWord(atIndex: wordIndex)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_TITLE",
            comment: "Title for the 'enter word' step of the 'restore payments wallet' views.",
        )

        view.backgroundColor = .Signal.groupedBackground

        let instructionsFormat = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INSTRUCTIONS_FORMAT",
            comment: "Format for the instructions for the 'enter word' step of the 'restore payments wallet' views. Embeds {{ the index of the current word }}.",
        )
        let instructions = String.nonPluralLocalizedStringWithFormat(instructionsFormat, OWSFormat.formatInt(wordIndex + 1))
        let instructionsLabel = UILabel.explanationTextLabel(text: instructions)

        let placeholderFormat = OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_PLACEHOLDER_FORMAT",
            comment: "Format for the placeholder text in the 'confirm payments passphrase' view of the app settings. Embeds: {{ the index of the word }}.",
        )
        textField.placeholder = String.nonPluralLocalizedStringWithFormat(
            placeholderFormat,
            OWSFormat.formatInt(wordIndex + 1),
        )

        let textFieldContainer = UIView()
        textFieldContainer.backgroundColor = .Signal.secondaryGroupedBackground
        textFieldContainer.directionalLayoutMargins = .init(
            hMargin: OWSTableViewController2.cellHInnerMargin,
            vMargin: OWSTableViewController2.cellVInnerMargin,
        )
        if #available(iOS 26, *) {
            textFieldContainer.cornerConfiguration = .capsule(maximumRadius: 26)
        } else {
            textFieldContainer.layer.cornerRadius = 10
        }
        textFieldContainer.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: textFieldContainer.layoutMarginsGuide.topAnchor),
            textField.leadingAnchor.constraint(equalTo: textFieldContainer.layoutMarginsGuide.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: textFieldContainer.layoutMarginsGuide.trailingAnchor),
            textField.bottomAnchor.constraint(equalTo: textFieldContainer.layoutMarginsGuide.bottomAnchor),
        ])

        let nextButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.nextButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapNextButton()
            },
        )

        var arrangedSubviews: [UIView] = [.spacer(withHeight: 16)]
        if wordIndex == 0 {
            arrangedSubviews.append(buildWordCountSwitcher())
            arrangedSubviews.append(.spacer(withHeight: 20))
        }
        arrangedSubviews.append(contentsOf: [
            instructionsLabel,
            textFieldContainer,
            warningLabel,
            .vStretchingSpacer(),
            nextButton,
            .spacer(withHeight: 16),
        ])
        let stackView = addStaticContentStackView(
            arrangedSubviews: arrangedSubviews,
            shouldAvoidKeyboard: true,
        )
        stackView.setCustomSpacing(24, after: instructionsLabel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        textField.becomeFirstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        textField.becomeFirstResponder()
    }

    // MARK: - Word count switcher (Radar)

    private func buildWordCountSwitcher() -> UIView {
        let twelveTitle = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_COUNT_12",
            comment: "Switcher option for restoring a 12-word recovery phrase.",
        )
        let twentyFourTitle = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_COUNT_24",
            comment: "Switcher option for restoring a 24-word recovery phrase.",
        )

        let twelveBtn = makeWordCountTabButton(title: twelveTitle)
        twelveBtn.addTarget(self, action: #selector(didTapTwelveWordTab), for: .touchUpInside)
        let twentyFourBtn = makeWordCountTabButton(title: twentyFourTitle)
        twentyFourBtn.addTarget(self, action: #selector(didTapTwentyFourWordTab), for: .touchUpInside)

        twelveWordTabButton = twelveBtn
        twentyFourWordTabButton = twentyFourBtn
        applyWordCountTabStyling()

        let tabStack = UIStackView(arrangedSubviews: [twelveBtn, twentyFourBtn])
        tabStack.axis = .horizontal
        tabStack.spacing = 0
        tabStack.alignment = .center
        tabStack.distribution = .fillEqually

        let container = UIView()
        container.backgroundColor = Self.switcherContainerFill
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

    private func makeWordCountTabButton(title: String) -> UIButton {
        var cfg = UIButton.Configuration.plain()
        cfg.attributedTitle = AttributedString(
            title,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 13, weight: .medium)]),
        )
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18)
        cfg.background.cornerRadius = 20
        cfg.background.backgroundColor = .clear
        return UIButton(configuration: cfg)
    }

    private func applyWordCountTabStyling() {
        let isTwelve = (partialPassphrase.wordCount == 12)
        if let tBtn = twelveWordTabButton, var tCfg = tBtn.configuration {
            tCfg.background.backgroundColor = isTwelve ? .white : .clear
            tCfg.baseForegroundColor = isTwelve ? Self.switcherAccentBlue : UIColor.black.withAlphaComponent(0.5)
            tBtn.configuration = tCfg
        }
        if let fBtn = twentyFourWordTabButton, var fCfg = fBtn.configuration {
            fCfg.background.backgroundColor = isTwelve ? .clear : .white
            fCfg.baseForegroundColor = isTwelve ? UIColor.black.withAlphaComponent(0.5) : Self.switcherAccentBlue
            fBtn.configuration = fCfg
        }
    }

    @objc
    private func didTapTwelveWordTab() {
        guard partialPassphrase.wordCount != 12 else { return }
        partialPassphrase.reset(wordCount: 12)
        textField.text = nil
        warningLabel.alpha = 0
        applyWordCountTabStyling()
    }

    @objc
    private func didTapTwentyFourWordTab() {
        guard partialPassphrase.wordCount != 24 else { return }
        partialPassphrase.reset(wordCount: 24)
        textField.text = nil
        warningLabel.alpha = 0
        applyWordCountTabStyling()
    }

    // MARK: - Events

    private func didTapNextButton() {
        guard let restoreWalletDelegate else {
            owsFailDebug("Missing restoreWalletDelegate.")
            dismiss(animated: true, completion: nil)
            return
        }
        guard let wordText, isValidWord(wordText) else {
            warningLabel.alpha = 1
            return
        }
        partialPassphrase.set(word: wordText, index: wordIndex)
        if partialPassphrase.isComplete {
            guard let paymentsPassphrase = partialPassphrase.asPaymentsPassphrase() else {
                OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INVALID_PASSPHRASE",
                    comment: "Error indicating that the user has entered an invalid payments passphrase in the 'restore payments wallet' views.",
                ))
                return
            }
            let view = PaymentsRestoreWalletCompleteViewController(
                restoreWalletDelegate: restoreWalletDelegate,
                passphrase: paymentsPassphrase,
            )
            navigationController?.pushViewController(view, animated: true)
        } else {
            let view = PaymentsRestoreWalletWordViewController(
                restoreWalletDelegate: restoreWalletDelegate,
                partialPassphrase: partialPassphrase,
                wordIndex: wordIndex + 1,
            )
            navigationController?.pushViewController(view, animated: true)
        }
    }

    private func textFieldDidChange() {
        // Clear any warning.
        warningLabel.alpha = 0
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapNextButton()
        return false
    }
}

// MARK: -

class PartialPaymentsPassphrase {

    private var wordMap = [Int: String]()

    /// Radar: 12 (Breez seed) or 24 words.
    private(set) var wordCount: Int

    var isComplete: Bool {
        wordMap.count == wordCount
    }

    init(wordCount: Int = PaymentsConstants.passphraseWordCount) {
        self.wordCount = wordCount
    }

    static var empty: PartialPaymentsPassphrase { PartialPaymentsPassphrase() }

    func set(word: String, index: Int) {
        let word = word.stripped
        guard !word.isEmpty else {
            owsFailDebug("Invalid word.")
            return
        }
        wordMap[index] = word
    }

    func getWord(atIndex index: Int) -> String? {
        wordMap[index]
    }

    func asPaymentsPassphrase() -> PaymentsPassphrase? {
        var words = [String]()

        for index in 0..<wordCount {
            guard let word = wordMap[index] else {
                owsFailDebug("Missing word: \(index)")
                return nil
            }
            words.append(word)
        }

        do {
            return try PaymentsPassphrase(words: words)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    func reset() {
        wordMap.removeAll()
    }

    func reset(wordCount: Int) {
        self.wordCount = wordCount
        wordMap.removeAll()
    }
}
