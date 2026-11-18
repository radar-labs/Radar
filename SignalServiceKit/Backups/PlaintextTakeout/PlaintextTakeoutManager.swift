//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum PlaintextTakeoutProgressPhase: String, OWSSequentialProgressStep {
    /// Exporting the Backup file.
    case backupFileExport
    /// Exporting attachments.
    case attachmentExport

    public var progressUnitCount: UInt64 {
        switch self {
        case .backupFileExport: 30
        case .attachmentExport: 70
        }
    }
}

// MARK: -

/// Responsible for "plaintext takeout"; i.e., a "plaintext Local File Backup".
///
/// Creates a plaintext JSONL-format Backup archive, along with metadata and
/// optionally plaintext attachments.
public class PlaintextTakeoutManager {
    /// ---- DIRECTORY STRUCTURE ----
    ///
    /// signal-export-{year}-{month}-{day}-{hr}-{min}-{sec}/
    /// ├─ main.jsonl
    /// ├─ metadata.json
    /// └─ files/
    ///    └─ <attachmentName prefix>/
    ///       └─ <attachmentName>.<extension>
    enum FileStructure {
        static let exportDirectoryPrefix = "signal-export-"
        static let backupFileName = "main.jsonl"
        static let metadataFileName = "metadata.json"
        static let attachmentDirectoryName = "files"

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter
        }()

        static func exportDirectoryName(date: Date) -> String {
            return "\(exportDirectoryPrefix)\(dateFormatter.string(from: date))"
        }

        /// The file name for an attachment, before any path extension.
        static func attachmentName(plaintextHash: Data) -> String {
            return plaintextHash.hexadecimalString
        }

        /// The name of the subdirectory, within the attachments directory,
        /// that holds the attachment with the given name.
        static func attachmentSubdirectoryName(attachmentName: String) -> String {
            return String(attachmentName.prefix(2))
        }
    }

    private struct Metadata: Encodable {
        static let current = Metadata(version: 1)

        let version: Int
    }

    private let attachmentStore: AttachmentStore
    private let backupArchiveManager: BackupArchiveManager
    private let dateProvider: DateProvider
    private let db: DB
    private let logger = PrefixedLogger(prefix: "[PlaintextTakeout]")
    private let securityScopedBookmarkAccess: SecurityScopedBookmarkAccess
    private let tsAccountManager: TSAccountManager

    init(
        attachmentStore: AttachmentStore,
        backupArchiveManager: BackupArchiveManager,
        dateProvider: @escaping DateProvider,
        db: DB,
        securityScopedBookmarkAccess: SecurityScopedBookmarkAccess,
        tsAccountManager: TSAccountManager,
    ) {
        self.attachmentStore = attachmentStore
        self.backupArchiveManager = backupArchiveManager
        self.dateProvider = dateProvider
        self.db = db
        self.securityScopedBookmarkAccess = securityScopedBookmarkAccess
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    /// Export a takeout into a new directory within the given folder.
    ///
    /// - Parameter destinationFolderUrl
    /// A security-scoped URL for a folder chosen by the user.
    /// - Parameter includeAttachments
    /// Whether or not the takeout should include attachments.
    /// - Returns
    /// The URL of the directory containing the export.
    @concurrent
    public func exportTakeout(
        destinationFolderUrl: URL,
        includeAttachments: Bool,
        progress: OWSSequentialProgressRootSink<PlaintextTakeoutProgressPhase>?,
    ) async throws -> URL {
        guard let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            throw OWSAssertionError("Missing local identifiers!")
        }

        guard
            securityScopedBookmarkAccess.startAccessToSecurityScopedBookmark(
                url: destinationFolderUrl,
            )
        else {
            throw OWSGenericError("Failed to access chosen folder!")
        }
        defer {
            securityScopedBookmarkAccess.stopAccessToSecurityScopedBookmark(
                url: destinationFolderUrl,
            )
        }

        let exportDirectoryUrl = destinationFolderUrl.appendingPathComponent(
            FileStructure.exportDirectoryName(date: dateProvider()),
            isDirectory: true,
        )

        guard !FileManager.default.fileExists(atPath: exportDirectoryUrl.path) else {
            throw OWSGenericError("Export directory already exists!")
        }

        do {
            try await _exportTakeout(
                exportDirectoryUrl: exportDirectoryUrl,
                localIdentifiers: localIdentifiers,
                includeAttachments: includeAttachments,
                progress: progress,
            )
            logger.info("Export complete.")
            return exportDirectoryUrl
        } catch {
            switch error {
            case is CancellationError:
                logger.warn("Export cancelled!")
            default:
                logger.error("Export failed! \(error)")
            }

            removeExportDirectory(exportDirectoryUrl)
            throw error
        }
    }

    private func _exportTakeout(
        exportDirectoryUrl: URL,
        localIdentifiers: LocalIdentifiers,
        includeAttachments: Bool,
        progress: OWSSequentialProgressRootSink<PlaintextTakeoutProgressPhase>?,
    ) async throws {
        let attachmentCollector: LocalFileBackupAttachmentCollector?
        if includeAttachments {
            attachmentCollector = LocalFileBackupAttachmentCollector()
        } else {
            attachmentCollector = nil
        }

        let backupFileUrl = try await backupArchiveManager.exportPlaintextBackupForTakeout(
            localIdentifiers: localIdentifiers,
            attachmentCollector: attachmentCollector,
            progress: progress?.child(for: .backupFileExport),
        )
        defer { try? OWSFileSystem.deleteFileIfExists(url: backupFileUrl) }

        let metadataData = failIfThrows {
            try JSONEncoder().encode(Metadata.current)
        }

        try NSFileCoordinator().coordinateThrows(writingItemAt: exportDirectoryUrl) { writeUrl in
            try FileManager.default.createDirectory(
                at: writeUrl,
                withIntermediateDirectories: true,
            )

            try FileManager.default.moveItem(
                at: backupFileUrl,
                to: writeUrl.appendingPathComponent(FileStructure.backupFileName),
            )

            try metadataData.write(
                to: writeUrl.appendingPathComponent(FileStructure.metadataFileName),
            )
        }

        if let attachmentCollector {
            try await exportAttachments(
                attachmentIds: attachmentCollector.attachments,
                attachmentDirectoryUrl: exportDirectoryUrl.appendingPathComponent(
                    FileStructure.attachmentDirectoryName,
                    isDirectory: true,
                ),
                progressSink: progress?.child(for: .attachmentExport),
            )
        } else {
            progress?.child(for: .attachmentExport)
                .addSource(withLabel: "", unitCount: 1).complete()
        }
    }

    private func removeExportDirectory(_ exportDirectoryUrl: URL) {
        do {
            try NSFileCoordinator().coordinateThrows(
                writingItemAt: exportDirectoryUrl,
                options: [.forDeleting],
            ) { writeUrl in
                guard FileManager.default.fileExists(atPath: writeUrl.path) else {
                    return
                }

                try FileManager.default.removeItem(at: writeUrl)
            }
        } catch {
            logger.error("Failed to remove export directory! \(error)")
        }
    }

    // MARK: -

    private func exportAttachments(
        attachmentIds: [Attachment.IDType],
        attachmentDirectoryUrl: URL,
        progressSink: OWSProgressSink?,
    ) async throws {
        // Attachments referenced multiple times are collected multiple times.
        let attachmentIds = Set(attachmentIds)
        logger.info("Exporting \(attachmentIds.count) attachments.")

        let progressSource = progressSink?.addSource(
            withLabel: PlaintextTakeoutProgressPhase.attachmentExport.rawValue,
            unitCount: UInt64(attachmentIds.count),
        )

        let fileCoordinator = NSFileCoordinator()
        var skippedCount = 0

        for attachmentId in attachmentIds {
            try Task.checkCancellation()
            defer { progressSource?.incrementCompletedUnitCount(by: 1) }

            let attachmentStream = db.read { tx in
                attachmentStore.fetch(id: attachmentId, tx: tx)?.asStream()
            }

            guard let attachmentStream else {
                // Not downloaded, or deleted since being collected.
                skippedCount += 1
                continue
            }

            try exportAttachment(
                attachmentStream,
                attachmentDirectoryUrl: attachmentDirectoryUrl,
                fileCoordinator: fileCoordinator,
            )
        }

        if skippedCount > 0 {
            logger.info("Skipped \(skippedCount) attachments that weren't downloaded.")
        }
    }

    private func exportAttachment(
        _ attachmentStream: AttachmentStream,
        attachmentDirectoryUrl: URL,
        fileCoordinator: NSFileCoordinator,
    ) throws {
        let attachmentName = FileStructure.attachmentName(
            plaintextHash: attachmentStream.plaintextHash,
        )
        let subdirectoryUrl = attachmentDirectoryUrl.appendingPathComponent(
            FileStructure.attachmentSubdirectoryName(attachmentName: attachmentName),
            isDirectory: true,
        )

        // Decrypted into a temporary file with the appropriate extension.
        let decryptedFileUrl = try attachmentStream.makeDecryptedCopy(filename: nil)
        defer { try? OWSFileSystem.deleteFileIfExists(url: decryptedFileUrl) }

        let fileName = "\(attachmentName).\(decryptedFileUrl.pathExtension)"

        try fileCoordinator.coordinateThrows(writingItemAt: subdirectoryUrl) { writeUrl in
            try FileManager.default.createDirectory(
                at: writeUrl,
                withIntermediateDirectories: true,
            )

            let fileUrl = writeUrl.appendingPathComponent(fileName)

            // Attachments with the same plaintext hash share a file.
            guard !FileManager.default.fileExists(atPath: fileUrl.path) else {
                return
            }

            try FileManager.default.moveItem(at: decryptedFileUrl, to: fileUrl)
        }
    }
}
