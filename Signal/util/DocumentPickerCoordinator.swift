//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import UniformTypeIdentifiers

/// Presents a `UIDocumentPickerViewController` and returns the picked
/// document or throws cancellation.
class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private var continuation: CheckedContinuation<URL?, Never>?

    /// Present the picker and return the URL of the picked document.
    ///
    /// - Throws
    /// `CancellationError` if the user dismisses the picker without picking.
    func pickDocument(
        fromViewController: UIViewController,
        contentTypes: [UTType],
    ) async throws(CancellationError) -> URL {
        let pickedUrl = await withCheckedContinuation { continuation in
            self.continuation = continuation

            let pickerController = UIDocumentPickerViewController(
                forOpeningContentTypes: contentTypes,
                asCopy: false,
            )
            pickerController.delegate = self
            fromViewController.present(pickerController, animated: true)
        }

        guard let pickedUrl else {
            throw CancellationError()
        }
        return pickedUrl
    }

    private func finish(pickedUrl: URL?) {
        continuation.take()?.resume(returning: pickedUrl)
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL],
    ) {
        finish(pickedUrl: urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(pickedUrl: nil)
    }
}
