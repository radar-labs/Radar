//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ContactNoteSheet: OWSTableSheetViewController {
    struct Context {
        let db: any DB
        let recipientDatabaseTable: RecipientDatabaseTable
        let nicknameManager: any NicknameManager
    }

    override var sheetBackgroundColor: UIColor {
        if #available(iOS 26, *) {
            .clear
        } else {
            super.sheetBackgroundColor
        }
    }

    override var placeOnGlassIfAvailable: Bool { true }

    private let contactNoteTableViewController: ContactNoteTableViewController
    override var tableViewController: OWSTableViewController2 {
        get { contactNoteTableViewController }
        set { }
    }

    private let thread: TSContactThread
    private let context: Context

    private weak var fromViewController: UIViewController?

    func present(from viewController: UIViewController) {
        fromViewController = viewController
        viewController.present(self, animated: true)
    }

    init(thread: TSContactThread, context: Context) {
        self.thread = thread
        self.context = context
        self.contactNoteTableViewController = ContactNoteTableViewController(thread: thread, context: context)
        super.init()
        self.tableViewController.backgroundStyle = .clear
        self.tableViewController.tableView.clipsToBounds = false
        self.contactNoteTableViewController.didTapEdit = { [weak self] in
            self?.didTapEdit()
        }
    }

    override func tableContents() -> OWSTableContents {
        return contactNoteTableViewController.tableContents()
    }

    private func didTapEdit() {
        let nicknameEditor: NicknameEditorViewController? = self.context.db.read { tx in
            NicknameEditorViewController.create(
                for: self.thread.contactAddress,
                context: .init(
                    db: self.context.db,
                    nicknameManager: self.context.nicknameManager,
                ),
                tx: tx,
            )
        }
        guard let nicknameEditor else { return }
        let navigationController = OWSNavigationController(rootViewController: nicknameEditor)

        self.dismiss(animated: true) { [weak fromViewController = self.fromViewController] in
            fromViewController?.presentFormSheet(navigationController, animated: true)
        }
    }
}

private class ContactNoteTableViewController: OWSTableViewController2, TextViewWithPlaceholderDelegate {
    typealias Context = ContactNoteSheet.Context

    private let thread: TSContactThread
    private let context: Context
    var didTapEdit: (() -> Void)?

    private let noteTextView: TextViewWithPlaceholder = {
        let textView = TextViewWithPlaceholder()
        textView.isEditable = false
        textView.linkTextAttributes = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        return textView
    }()

    init(thread: TSContactThread, context: Context) {
        self.thread = thread
        self.context = context
    }

    func tableContents() -> OWSTableContents {
        // This is trying to fake a navigation bar.
        // TODO: Make a general-purpose, navigable, self-sizing native sheet like what's used in the Call Quality Survey flow
        let header: UIView = {
            let headerContainer = UIView()
            let hMargin: CGFloat = if #available(iOS 26, *) {
                0
            } else {
                16
            }
            headerContainer.layoutMargins = .init(
                top: 0,
                left: hMargin,
                bottom: 24,
                right: hMargin,
            )

            let titleLabel = UILabel()
            headerContainer.addSubview(titleLabel)
            titleLabel.text = OWSLocalizedString(
                "CONTACT_NOTE_TITLE",
                comment: "Title for a view showing the note that has been set for a profile.",
            )
            titleLabel.font = .dynamicTypeHeadline.semibold()
            titleLabel.textColor = .Signal.label
            titleLabel.autoCenterInSuperviewMargins()
            titleLabel.autoPinHeightToSuperviewMargins()

            var config = UIButton.Configuration.mediumSecondary(title: CommonStrings.editButton)
            config.baseForegroundColor = .Signal.label
            let editButton = UIButton(
                configuration: config,
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapEdit?()
                },
            )
            headerContainer.addSubview(editButton)
            editButton.autoAlignAxis(.horizontal, toSameAxisOf: titleLabel)
            editButton.autoPinEdge(toSuperviewMargin: .trailing)
            editButton.autoPinEdge(.leading, to: .trailing, of: titleLabel, withOffset: 8, relation: .greaterThanOrEqual)

            return headerContainer
        }()

        let note: String? = self.context.db.read { tx in
            guard
                let recipient = self.context.recipientDatabaseTable.fetchRecipient(
                    address: self.thread.contactAddress,
                    tx: tx,
                ),
                let nicknameRecord = self.context.nicknameManager.fetchNickname(
                    for: recipient,
                    tx: tx,
                )
            else { return nil }
            return nicknameRecord.note
        }

        self.noteTextView.text = note

        let section = OWSTableSection(
            items: [
                self.textViewItem(
                    self.noteTextView,
                    dataDetectorTypes: .all,
                ),
            ],
            headerView: header,
        )

        return OWSTableContents(sections: [section])
    }
}
