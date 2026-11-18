//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct DefaultStickerPack {
    private let info: StickerPackInfo
    private let shouldAutoInstall: Bool

    private init(packIdHex: String, packKeyHex: String, shouldAutoInstall: Bool) {
        guard let info = StickerPackInfo.parse(packIdHex: packIdHex, packKeyHex: packKeyHex) else {
            owsFail("Invalid info")
        }

        self.info = info
        self.shouldAutoInstall = shouldAutoInstall
    }

    private static let allPacks: [DefaultStickerPack] = {
        // These sticker packs aren't available in Staging.
        guard TSConstants.isUsingProductionService else {
            return []
        }

        return [
            // Rocky Talk
            DefaultStickerPack(
                packIdHex: "42fb75e1827c0c945cfb5ca0975db03c",
                packKeyHex: "eee27e2b9f773e0a55ea24c340b7be858711a6e2bd9b6ee7044343e0e428be65",
                shouldAutoInstall: true,
            ),
            // My Daily Life 1
            DefaultStickerPack(
                packIdHex: "ccc89a05dc077856b57351e90697976c",
                packKeyHex: "45730e60f09d5566115223744537a6b7d9ea99ceeacb77a1fbd6801b9607fbcf",
                shouldAutoInstall: true,
            ),
            // Zozo the French Bulldog
            DefaultStickerPack(
                packIdHex: "fb535407d2f6497ec074df8b9c51dd1d",
                packKeyHex: "17e971c134035622781d2ee249e6473b774583750b68c11bb82b7509c68b6dfd",
                shouldAutoInstall: true,
            ),
            // Croco's Feelings
            DefaultStickerPack(
                packIdHex: "3044281a51307306e5442f2e9070953a",
                packKeyHex: "c4caaa84397e1a630a5960f54a0b82753c88a5e52e0defe615ba4dd80f130cbf",
                shouldAutoInstall: true,
            ),
            // My Daily Life 2
            DefaultStickerPack(
                packIdHex: "a2414255948558316f37c1d36c64cd28",
                packKeyHex: "fda12937196d236f1ca9e1196a56542e1d1cef6ff84e2be03828717fa20ad366",
                shouldAutoInstall: false,
            ),
            // Cozy Season
            DefaultStickerPack(
                packIdHex: "684d2b7bcfc2eec6f57f2e7be0078e0f",
                packKeyHex: "866e0dcb4a1b25f2b04df270cd742723e4a6555c0a1abc3f3f30dcc5a2010c55",
                shouldAutoInstall: false,
            ),
            // Chug the Mouse
            DefaultStickerPack(
                packIdHex: "f19548e5afa38d1ce4f5c3191eba5e30",
                packKeyHex: "2cb3076740f669aa44c6c063290b249a7d00a4b02ed8f9e9a5b902a37f1bbc41",
                shouldAutoInstall: false,
            ),
            // Bandit the Cat
            DefaultStickerPack(
                packIdHex: "9acc9e8aba563d26a4994e69263e3b25",
                packKeyHex: "5a6dff3948c28efb9b7aaf93ecc375c69fc316e78077ed26867a14d10a0f6a12",
                shouldAutoInstall: false,
            ),
            // Swoon Hands
            DefaultStickerPack(
                packIdHex: "e61fa0867031597467ccc036cc65d403",
                packKeyHex: "13ae7b1a7407318280e9b38c1261ded38e0e7138b9f964a6ccbb73e40f737a9b",
                shouldAutoInstall: false,
            ),
            // Swoon Faces
            DefaultStickerPack(
                packIdHex: "cca32f5b905208b7d0f1e17f23fdc185",
                packKeyHex: "8bf8e95f7a45bdeafe0c8f5b002ef01ab95b8f1b5baac4019ccd6b6be0b1837a",
                shouldAutoInstall: false,
            ),
            // Day by Day
            DefaultStickerPack(
                packIdHex: "cfc50156556893ef9838069d3890fe49",
                packKeyHex: "5f5beab7d382443cb00a1e48eb95297b6b8cadfd0631e5d0d9dc949e6999ff4b",
                shouldAutoInstall: false,
            ),
        ]
    }()

    private static let allPacksById: [Data: DefaultStickerPack] = {
        var result = [Data: DefaultStickerPack]()
        for pack in allPacks {
            result[pack.info.packId] = pack
        }
        return result
    }()

    // MARK: -

    static var packsToAutoInstall: [StickerPackInfo] {
        allPacks
            .filter { $0.shouldAutoInstall }
            .map { $0.info }
    }

    static var packsToNotAutoInstall: [StickerPackInfo] {
        allPacks
            .filter { !$0.shouldAutoInstall }
            .map { $0.info }
    }

    static func isDefaultStickerPack(packId: Data) -> Bool {
        allPacksById[packId] != nil
    }
}
