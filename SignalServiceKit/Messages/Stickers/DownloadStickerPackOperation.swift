//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum DownloadStickerPackOperation {
    static func run(stickerPackInfo: StickerPackInfo) async throws -> StickerPackRecord {
        return try await Retry.performWithBackoff(maxAttempts: 4) {
            return try await self._run(stickerPackInfo: stickerPackInfo)
        }
    }

    private static func _run(stickerPackInfo: StickerPackInfo) async throws -> StickerPackRecord {
        owsAssertDebug(stickerPackInfo.packId.count > 0)
        owsAssertDebug(stickerPackInfo.packKey.count > 0)

        let stickerManager = DependenciesBridge.shared.stickerManager
        let db = DependenciesBridge.shared.db

        if
            let stickerPack = db.read(block: { tx in
                stickerManager.fetchStickerPack(stickerPackInfo: stickerPackInfo, transaction: tx)
            })
        {
            return stickerPack
        }

        // https://cdn.signal.org/stickers/<pack_id>/manifest.proto
        let urlPath = "stickers/\(stickerPackInfo.packId.hexadecimalString)/manifest.proto"

        do {
            let encryptedFileUrl: URL = try await CDNDownloadOperation.tryToDownload(
                urlPath: urlPath,
                maxDownloadSize: CDNDownloadOperation.kMaxStickerPackDownloadSize,
            )
            do {
                let manifestData = try StickerManager.decrypt(at: encryptedFileUrl, packKey: stickerPackInfo.packKey)

                return try self.parseStickerPackManifest(
                    stickerPackInfo: stickerPackInfo,
                    manifestData: manifestData,
                )
            } catch {
                CDNDownloadOperation.markUrlPathAsCorrupt(urlPath)
                // Fail immediately; do not retry.
                throw OWSAssertionError("Decryption failed: \(error)")
            }
        } catch {
            if
                let statusCode = error.httpStatusCode,
                (400..<500).contains(statusCode),
                statusCode != 429
            {
                stickerManager.markStickerPackAsMissing(stickerPackInfo: stickerPackInfo)
            }

            throw error
        }
    }

    private static func parseStickerPackManifest(stickerPackInfo: StickerPackInfo, manifestData: Data) throws -> StickerPackRecord {
        owsAssertDebug(manifestData.count > 0)

        let manifestProto: SSKProtoPack
        do {
            manifestProto = try SSKProtoPack(serializedData: manifestData)
        } catch let error as NSError {
            owsFailDebug("Couldn't parse protos: \(error)")
            throw StickerError.invalidInput
        }
        let title = parseOptionalString(manifestProto.title)
        let author = parseOptionalString(manifestProto.author)
        let manifestCover = parsePackItem(manifestProto.cover)
        var items = [StickerPackItem]()
        for stickerProto in manifestProto.stickers {
            if let item = parsePackItem(stickerProto) {
                items.append(item)
            }
        }
        guard let firstItem = items.first else {
            owsFailDebug("Invalid manifest, no stickers")
            throw StickerError.invalidInput
        }
        let cover = manifestCover ?? firstItem

        return StickerPackRecord(info: stickerPackInfo, title: title, author: author, cover: cover, items: items)
    }

    private static func parseOptionalString(_ value: String?) -> String? {
        return value?.ows_stripped().nilIfEmpty
    }

    private static func parsePackItem(_ proto: SSKProtoPackSticker?) -> StickerPackItem? {
        guard let proto else {
            return nil
        }
        let stickerId = proto.id
        let emojiString = parseOptionalString(proto.emoji) ?? ""
        let contentType = parseOptionalString(proto.contentType) ?? ""
        return StickerPackItem(stickerId: stickerId, emojiString: emojiString, contentType: contentType)
    }
}
