//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// Creates streams for JSON-Lines Backup files, in plaintext.
class BackupArchiveJsonLinesStreamProvider {
    init() {}

    func openOutputFileStream(
        exportProgress: BackupArchiveExportProgress?,
    ) throws -> (
        outputJsonLinesStream: BackupArchiveJsonLinesOutputStream,
        fileUrl: URL,
    ) {
        let fileUrl = OWSFileSystem.temporaryFileUrl(
            fileExtension: nil,
            isAvailableWhileDeviceLocked: true,
        )

        guard let outputStream = OutputStream(url: fileUrl, append: false) else {
            throw OWSGenericError("Failed to open output stream!")
        }

        outputStream.open()

        guard outputStream.streamStatus == .open else {
            throw OWSGenericError("Output stream not open after calling .open()!")
        }

        let outputJsonLinesStream = BackupArchiveJsonLinesOutputStream(
            outputStream: outputStream,
            exportProgress: exportProgress,
        )

        return (
            outputJsonLinesStream: outputJsonLinesStream,
            fileUrl: fileUrl,
        )
    }
}

// MARK: -

/// Output stream for writing a "JSON Lines" Backup file, where headers and
/// frames are represented as newline-separated JSON representations of the
/// underlying Backup protos.
class BackupArchiveJsonLinesOutputStream: BackupArchiveOutputStream {

    private let exportProgress: BackupArchiveExportProgress?
    private let logger = PrefixedLogger(prefix: "[Backups]")
    private let outputStream: any OutputStreamable

    private var libsignalJsonExporter: BackupJsonExporter?

    init(
        outputStream: any OutputStreamable,
        exportProgress: BackupArchiveExportProgress?,
    ) {
        self.exportProgress = exportProgress
        self.libsignalJsonExporter = nil
        self.outputStream = outputStream
    }

    func writeHeader(_ header: BackupProto_BackupInfo) throws {
        guard libsignalJsonExporter == nil else {
            throw OWSAssertionError("Tried to write header twice!")
        }

        let headerBytes = failIfThrows {
            try header.serializedData()
        }

        let jsonExporter: BackupJsonExporter
        do {
            jsonExporter = try BackupJsonExporter(backupInfo: headerBytes)
        } catch {
            logger.error("Invalid BackupInfo header bytes! \(error)")
            throw error
        }

        libsignalJsonExporter = jsonExporter

        try writeLine(jsonExporter.initialChunk)
        exportProgress?.didExportFrame()
    }

    func writeFrame(_ frame: BackupProto_Frame, flush: BackupArchiveFlushBehavior?) throws {
        guard let libsignalJsonExporter else {
            throw OWSAssertionError("Missing exporter! Did we not write the header?")
        }

        let frameBytes = failIfThrows {
            try frame.serializedData()
        }

        let exportFramesResult: [BackupJsonExporter.FrameExportResult]
        do {
            let bytes = frameBytes.prefixedWithVarintLength()
            exportFramesResult = try libsignalJsonExporter.exportFrames(bytes)
        } catch {
            logger.error("Failed to parse frame bytes! \(error)")
            throw error
        }

        guard
            exportFramesResult.count == 1,
            let exportFrameResult = exportFramesResult.first
        else {
            throw OWSAssertionError("Unexpected count of exportFramesResult: \(exportFramesResult.count)")
        }

        if let errorMessage = exportFrameResult.errorMessage {
            throw OWSGenericError("Failed to export frame! \(errorMessage)")
        }

        // LibSignal omits the line for frames it filters out. Our own filtering
        // should be a superset of LibSignal's, so this is unexpected.
        guard let line = exportFrameResult.line else {
            throw OWSAssertionError("LibSignal unexpectedly filtered out frame!")
        }

        try writeLine(line)
        exportProgress?.didExportFrame()
    }

    func closeFileStream() throws {
        guard let libsignalJsonExporter else {
            throw OWSAssertionError("Missing exporter! Did we not write the header?")
        }

        exportProgress?.didCloseStream()
        try outputStream.close()
        try libsignalJsonExporter.finishExport()
    }

    private func writeLine(_ line: String) throws {
        let line = line + "\n"
        let bytes = Data(line.utf8)
        try outputStream.write(data: bytes, options: [:])
    }
}
