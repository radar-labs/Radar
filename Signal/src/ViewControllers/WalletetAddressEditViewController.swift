//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

class WalletAddressEditViewController: OWSTableViewController2 {
    class var addressGlyphLimit: Int {
        24
    }

    var placeholderText: String? {
        "Address/Username"
    }

    private lazy var addressField = OWSTextField(
        placeholder: self.placeholderText,
        returnKeyType: .done,
        autocapitalizationType: .words,
        clearButtonMode: .whileEditing,
        delegate: self,
        editingChanged: { [unowned self] in
            self.updateHasUnsavedChanges()
        },
        returnPressed: { [unowned self] in
            if hasUnsavedChanges { self.didTapDone() }
        }
    )

    private let oldAddress: String
    private let setNewAddress: (String) async throws -> Void

    private var isPresentedInSheet = false

    init(oldAddress: String, setNewAddress: @escaping (String) async throws -> Void) {
        self.oldAddress = oldAddress
        self.setNewAddress = setNewAddress
        super.init()
        self.shouldAvoidKeyboard = true
    }

    func presentInNavController(from viewController: UIViewController, forceDarkMode: Bool = false) {
        self.isPresentedInSheet = true
        let navigationController = OWSNavigationController(rootViewController: self)
        if forceDarkMode {
            self.forceDarkMode = true
            navigationController.overrideUserInterfaceStyle = .dark
        }
        viewController.presentFormSheet(navigationController, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Edit address"

        if isPresentedInSheet {
            self.navigationItem.leftBarButtonItem = .cancelButton(
                dismissingFrom: self,
                hasUnsavedChanges: { [unowned self] in self.hasUnsavedChanges }
            )
        }
        self.navigationItem.rightBarButtonItem = .doneButton { [unowned self] in self.didTapDone() }
        self.navigationItem.rightBarButtonItem?.isEnabled = false

        self.addressField.text = self.oldAddress

        self.contents = OWSTableContents(sections: [
            OWSTableSection(items: [.textFieldItem(
                self.addressField,
                textColor: UIColor.Signal.label
            )]),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // It's laggy to assign first responder while pushing in a navigation
        // controller, but it's okay while presenting a sheet.
        if isPresentedInSheet {
            self.addressField.becomeFirstResponder()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !isPresentedInSheet {
            self.addressField.becomeFirstResponder()
        }
    }

    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateHasUnsavedChanges() {
        self.hasUnsavedChanges = self.addressField.text != self.oldAddress
    }

    private var hasUnsavedChanges: Bool = false {
        didSet {
            if oldValue == hasUnsavedChanges {
                return
            }
            self.navigationItem.rightBarButtonItem?.isEnabled = hasUnsavedChanges
        }
    }

    private func didTapDone() {
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            presentationDelay: 0.25,
            asyncBlock: { [weak self] modal in
                guard let self else { return }
                let updateResult = await Result {
                    try await self.setNewAddress(self.addressField.text!)
                }
                modal.dismissIfNotCanceled { [weak self] in
                    do {
                        _ = try updateResult.get()
                        if self?.isPresentedInSheet ?? false {
                            self?.dismiss(animated: true)
                        } else {
                            self?.addressField.resignFirstResponder()
                            self?.navigationController?.popViewController(animated: true)
                        }
                    } catch {
                        self?.handleError(error)
                    }
                }
            }
        )
    }

    func handleError(_ error: any Error) {
    }
}

extension WalletAddressEditViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxGlyphCount: Self.addressGlyphLimit
        )
    }
}
