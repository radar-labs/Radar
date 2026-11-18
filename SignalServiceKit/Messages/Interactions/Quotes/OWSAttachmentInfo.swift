//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Holds metadata about an attachment, belonging to a quoted message, used as
/// part of the quoted reply.
///
/// - Important
/// Values here refer to the original attachment, not any attachment thumbnail
/// owned by the quoted-reply itself.
///
/// - Important
/// Values here may be set based on an incoming proto. If the original
/// attachment is available locally, prefer reading from it directly.
///
/// - SeeAlso ``TSQuotedMessage``
@objc(OWSAttachmentInfo)
public class OWSAttachmentInfo: NSObject, NSSecureCoding {

    /// The mime type of an attachment that was quoted.
    public let originalAttachmentMimeType: String?
    /// The source filename of an attachment that was quoted.
    public let originalAttachmentSourceFilename: String?
    /// The rendering flag of an attachment that was quoted.
    public let originalAttachmentRenderingFlag: AttachmentReference.RenderingFlag?

    init(
        originalAttachmentMimeType: String?,
        originalAttachmentSourceFilename: String?,
        originalAttachmentRenderingFlag: AttachmentReference.RenderingFlag?,
    ) {
        self.originalAttachmentMimeType = originalAttachmentMimeType
        self.originalAttachmentSourceFilename = originalAttachmentSourceFilename
        self.originalAttachmentRenderingFlag = originalAttachmentRenderingFlag
    }

    // MARK: -

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        if let originalAttachmentMimeType {
            coder.encode(originalAttachmentMimeType, forKey: "contentType")
        }
        if let originalAttachmentSourceFilename {
            coder.encode(originalAttachmentSourceFilename, forKey: "sourceFilename")
        }
        if let originalAttachmentRenderingFlag {
            coder.encode(NSNumber(integerLiteral: originalAttachmentRenderingFlag.rawValue), forKey: "renderingFlag")
        }
    }

    public required init?(coder: NSCoder) {
        self.originalAttachmentMimeType = coder.decodeObject(of: NSString.self, forKey: "contentType") as String?
        self.originalAttachmentSourceFilename = coder.decodeObject(of: NSString.self, forKey: "sourceFilename") as String?
        self.originalAttachmentRenderingFlag = coder.decodeObject(of: NSNumber.self, forKey: "renderingFlag")
            .flatMap { AttachmentReference.RenderingFlag(rawValue: $0.intValue) }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(originalAttachmentMimeType)
        hasher.combine(originalAttachmentSourceFilename)
        hasher.combine(originalAttachmentRenderingFlag)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard self.originalAttachmentMimeType == object.originalAttachmentMimeType else { return false }
        guard self.originalAttachmentSourceFilename == object.originalAttachmentSourceFilename else { return false }
        guard self.originalAttachmentRenderingFlag == object.originalAttachmentRenderingFlag else { return false }
        return true
    }
}
