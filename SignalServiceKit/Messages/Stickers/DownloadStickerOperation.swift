//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum DownloadStickerOperation {

    static func run(stickerInfo: StickerInfo) async throws -> Data {
        return try await Retry.performWithBackoff(maxAttempts: 4) {
            return try await _run(stickerInfo: stickerInfo)
        }
    }

    private static func _run(stickerInfo: StickerInfo) async throws -> Data {
        assert(stickerInfo.packId.count > 0)
        assert(stickerInfo.packKey.count > 0)

        let stickerManager = DependenciesBridge.shared.stickerManager
        let db = DependenciesBridge.shared.db

        if
            let installedStickerMetadata = db.read(block: { tx in
                stickerManager.installedStickerMetadata(stickerInfo: stickerInfo, transaction: tx)
            })
        {
            // Already installed.
            return try installedStickerMetadata.readStickerData()
        }

        // https://cdn.signal.org/stickers/<pack_id>/full/<sticker_id>
        let urlPath = "stickers/\(stickerInfo.packId.hexadecimalString)/full/\(stickerInfo.stickerId)"

        let encryptedFileUrl: URL = try await CDNDownloadOperation.tryToDownload(
            urlPath: urlPath,
            maxDownloadSize: CDNDownloadOperation.kMaxStickerDataDownloadSize,
        )

        let stickerData: Data
        do {
            stickerData = try StickerManager.decrypt(at: encryptedFileUrl, packKey: stickerInfo.packKey)
        } catch {
            CDNDownloadOperation.markUrlPathAsCorrupt(urlPath)
            throw OWSAssertionError("Decryption failed: \(error)")
        }

        return stickerData
    }
}
