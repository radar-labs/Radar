//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Output stream for writing a "varint-proto" Backup file, where headers and
/// frames are represented as concatenated, varint-prefixed serialized protos.
class BackupArchiveProtoOutputStream: BackupArchiveOutputStream {
    private let outputStream: TransformingOutputStream
    private let exportProgress: BackupArchiveExportProgress?

    /// - Important
    /// In practice, the "varint-prefixing" of serialized protos is implemented
    /// via a `ChunkedOutputStreamTransform`. Consequently, callers must include
    /// a `ChunkedOutputStreamTransform` in the passed list of transforms.
    init(
        transforms: [any StreamTransform],
        outputStream: any OutputStreamable,
        exportProgress: BackupArchiveExportProgress?,
    ) {
        owsPrecondition(transforms.contains(where: { $0 is ChunkedOutputStreamTransform }))

        self.outputStream = TransformingOutputStream(
            transforms: transforms,
            outputStream: outputStream,
        )
        self.exportProgress = exportProgress
    }

    func writeHeader(_ header: BackupProto_BackupInfo) throws {
        let bytes = failIfThrows {
            try header.serializedData()
        }

        let options = [GzipStreamTransform.optionsKey: GzipStreamTransform.Options.forceFlush]
        try outputStream.write(data: bytes, options: options)
        exportProgress?.didExportFrame()
    }

    func writeFrame(_ frame: BackupProto_Frame, flush: BackupArchiveFlushBehavior?) throws {
        let bytes = failIfThrows {
            try frame.serializedData()
        }

        let options: StreamTransform.Options = switch flush {
        case nil: [:]
        case .afterWrite: [GzipStreamTransform.optionsKey: GzipStreamTransform.Options.forceFlush]
        case .afterInterval: [GzipStreamTransform.optionsKey: GzipStreamTransform.Options.intervalFlush]
        }
        try outputStream.write(data: bytes, options: options)
        exportProgress?.didExportFrame()
    }

    func closeFileStream() throws {
        exportProgress?.didCloseStream()
        try outputStream.close()
    }
}
