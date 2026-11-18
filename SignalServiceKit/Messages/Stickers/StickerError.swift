//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public enum StickerError: Int, Error {
    case invalidInput
    case noSticker
    case corruptData
}
