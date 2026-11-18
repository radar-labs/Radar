//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(StickerPackItem)
public final class StickerPackItem: NSObject, NSSecureCoding, NSCopying {
    public let stickerId: UInt32
    public let emojiString: String
    public let contentType: String?

    init(
        stickerId: UInt32,
        emojiString: String,
        contentType: String?,
    ) {
        self.stickerId = stickerId
        self.emojiString = emojiString
        self.contentType = contentType?.nilIfEmpty
    }

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        if let contentType {
            coder.encode(contentType, forKey: "contentType")
        }
        coder.encode(self.emojiString, forKey: "emojiString")
        coder.encode(NSNumber(value: self.stickerId), forKey: "stickerId")
    }

    public init?(coder: NSCoder) {
        self.contentType = (coder.decodeObject(of: NSString.self, forKey: "contentType") as String?)?.nilIfEmpty
        self.emojiString = coder.decodeObject(of: NSString.self, forKey: "emojiString") as String? ?? ""
        self.stickerId = coder.decodeObject(of: NSNumber.self, forKey: "stickerId")?.uint32Value ?? 0
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.contentType)
        hasher.combine(self.emojiString)
        hasher.combine(self.stickerId)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.contentType == object.contentType else { return false }
        guard self.emojiString == object.emojiString else { return false }
        guard self.stickerId == object.stickerId else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    func stickerInfoWith(stickerPack: StickerPackRecord) -> StickerInfo {
        let packId = stickerPack.info.packId
        let packKey = stickerPack.info.packKey
        return StickerInfo(packId: packId ?? Data(), packKey: packKey ?? Data(), stickerId: self.stickerId)
    }
}
