//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class LightningLogsViewController: OWSViewController {

    private static let displayedLineLimit = 1000

    private let textView = UITextView()
    private var exportButton: OWSFlatButton!
    private let bottomContainer = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_LIGHTNING_LOGS",
            comment: "Label for the 'lightning logs' row in payment settings."
        )

        view.backgroundColor = Theme.backgroundColor

        configureTextView()
        configureExportButton()
        layoutViews()
        loadLogs()
    }

    override func themeDidChange() {
        super.themeDidChange()
        view.backgroundColor = Theme.backgroundColor
        textView.backgroundColor = Theme.backgroundColor
        textView.textColor = Theme.primaryTextColor
        bottomContainer.backgroundColor = Theme.backgroundColor
    }

    private func configureTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = Theme.backgroundColor
        textView.textColor = Theme.primaryTextColor
        textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureExportButton() {
        exportButton = OWSFlatButton.button(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_LIGHTNING_LOGS_EXPORT_BUTTON",
                comment: "Title for the 'export lightning logs' button in the lightning logs view."
            ),
            font: UIFont.dynamicTypeHeadline,
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(didTapExport)
        )
        exportButton.layer.cornerRadius = 12
        exportButton.clipsToBounds = true
        exportButton.autoSetDimension(.height, toSize: 48)
        exportButton.translatesAutoresizingMaskIntoConstraints = false
    }

    private func layoutViews() {
        bottomContainer.backgroundColor = Theme.backgroundColor
        bottomContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomContainer.addSubview(exportButton)

        view.addSubview(textView)
        view.addSubview(bottomContainer)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomContainer.topAnchor),

            bottomContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            exportButton.topAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: 12),
            exportButton.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor, constant: 20),
            exportButton.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor, constant: -20),
            exportButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    private func loadLogs() {
        let text = LightningLogger.shared.currentTextTail(maxLines: Self.displayedLineLimit)
        textView.text = text.isEmpty
            ? OWSLocalizedString(
                "SETTINGS_PAYMENTS_LIGHTNING_LOGS_EMPTY",
                comment: "Placeholder text shown when no lightning logs have been captured yet."
            )
            : text
        textView.scrollToBottom()
    }

    @objc
    private func didTapExport() {
        let logUrl: URL
        do {
            logUrl = try LightningLogger.shared.writeToTemporaryFile()
        } catch {
            OWSActionSheets.showErrorAlert(
                message: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_LIGHTNING_LOGS_EXPORT_FAILED",
                    comment: "Error message shown when exporting lightning logs fails."
                )
            )
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [logUrl],
            applicationActivities: nil
        )
        activityVC.popoverPresentationController?.sourceView = exportButton
        activityVC.popoverPresentationController?.sourceRect = exportButton.bounds
        present(activityVC, animated: true)
    }
}

private extension UITextView {
    func scrollToBottom() {
        layoutIfNeeded()
        let bottomOffset = contentSize.height - bounds.height
        guard bottomOffset > 0 else { return }
        setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
    }
}
