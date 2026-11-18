//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import QuartzCore

extension Upload.Constants {
    fileprivate static let uploadMaxRetries = 8
    fileprivate static let maxUploadProgressRetries = 2
}

public enum AttachmentUpload {

    // MARK: - Upload Entrypoint

    /// The main entry point into the CDN2/CDN3 upload flow.
    /// This method is responsible for prepping the source data and its metadata.
    /// From this point forward,  the upload doesn't have any knowledge of the source (attachment, backup, image, etc)
    public static func start<Metadata: UploadMetadata>(
        attempt: Upload.Attempt<Metadata>,
        dateProvider: @escaping DateProvider,
        sleepTimer: Upload.Shims.SleepTimer,
        progressBlock: OWSURLSession.ProgressBlock,
    ) async throws -> Upload.Result<Metadata> {
        try Task.checkCancellation()
        return try await attemptUpload(
            attempt: attempt,
            dateProvider: dateProvider,
            sleepTimer: sleepTimer,
            progressBlock: progressBlock,
        )
    }

    /// The retriable parts of the upload.
    /// 1. Create upload endpoint
    /// 2. Get the target URL from the endpoint
    /// 3. Initate the upload via the endpoint
    ///
    /// - Parameters:
    ///   - localMetadata: The metadata and URL path for the local upload data
    ///   will create a new request and fetch a new form.
    ///   - progressBlock: Callback notified up upload progress.
    /// - returns: `Upload.Result` reflecting the metadata of the final upload result.
    ///
    private static func attemptUpload<Metadata: UploadMetadata>(
        attempt: Upload.Attempt<Metadata>,
        dateProvider: @escaping DateProvider,
        sleepTimer: Upload.Shims.SleepTimer,
        progressBlock: OWSURLSession.ProgressBlock,
    ) async throws -> Upload.Result<Metadata> {
        attempt.logger.info("Begin upload. (CDN\(attempt.cdnNumber)) [\(attempt.encryptedDataLength) bytes]")
        try await performResumableUpload(
            attempt: attempt,
            sleepTimer: sleepTimer,
            failureCount: 0,
            immediatelyResumeAtByteOffset: nil,
            progressBlock: progressBlock,
        )
        return Upload.Result(
            cdnKey: attempt.cdnKey,
            cdnNumber: attempt.cdnNumber,
            localUploadMetadata: attempt.localMetadata,
            beginTimestamp: attempt.beginTimestamp,
            finishTimestamp: dateProvider().ows_millisecondsSince1970,
        )
    }

    /// Consult the UploadEndpoint to determine how much has already been uploaded.
    private static func getResumableUploadProgress<Metadata: UploadMetadata>(forAttempt attempt: Upload.Attempt<Metadata>) async throws -> Upload.ResumeProgress {
        return try await Retry.performWithBackoff(
            maxAttempts: Upload.Constants.maxUploadProgressRetries + 1,
            isRetryable: { $0.isNetworkFailureOrTimeout },
            block: {
                attempt.logger.info("Checking upload progress")
                return try await attempt.endpoint.getResumableUploadProgress(attempt: attempt)
            },
        )
    }

    /// Upload the file using the endpoint and report progress
    private static func performResumableUpload<Metadata: UploadMetadata>(
        attempt: Upload.Attempt<Metadata>,
        sleepTimer: Upload.Shims.SleepTimer,
        failureCount: Int,
        immediatelyResumeAtByteOffset: UInt64?,
        progressBlock: OWSURLSession.ProgressBlock,
    ) async throws {
        guard failureCount < Upload.Constants.uploadMaxRetries else {
            throw Upload.Error.uploadFailure(recovery: .noMoreRetries)
        }
        let startTime = CACurrentMediaTime()

        let totalDataLength = UInt64(safeCast: attempt.encryptedDataLength)
        let bytesAlreadyUploaded: UInt64

        if let immediatelyResumeAtByteOffset {
            bytesAlreadyUploaded = immediatelyResumeAtByteOffset
        } else if attempt.isResumedUpload || failureCount > 0 {
            // Only check remote upload progress if we think progress was made locally
            let uploadProgress = try await getResumableUploadProgress(forAttempt: attempt)
            switch uploadProgress {
            case .complete:
                attempt.logger.info("Endpoint reported complete upload")
                return
            case .uploaded(let remoteByteCount):
                attempt.logger.info("Endpoint reported \(remoteByteCount) of \(totalDataLength) bytes uploaded")
                bytesAlreadyUploaded = remoteByteCount
            case .restart:
                attempt.logger.warn("Endpoint couldn't provide upload progress; restarting")
                throw Upload.Error.uploadFailure(recovery: .restart(.afterBackoff))
            }
        } else {
            bytesAlreadyUploaded = 0
        }

        if bytesAlreadyUploaded == totalDataLength {
            attempt.logger.info("Upload has been completed")
            return
        }

        if bytesAlreadyUploaded > totalDataLength {
            attempt.logger.warn("Too many bytes have been uploaded")
            throw Upload.Error.uploadFailure(recovery: .restart(.afterBackoff))
        }

        // If we're resuming an upload, we want the first progress update to
        // contain what we've already uploaded. If we're starting a new upload,
        // this will be zero.
        try await progressBlock(OWSURLSession.ProgressUpdate(
            completedByteCount: bytesAlreadyUploaded,
            totalByteCount: totalDataLength,
        ))

        func downloadTimeLogString(_ bytesUploaded: UInt64) -> String {
            let totalTime = CACurrentMediaTime() - startTime
            guard totalTime > 0 else { return "" }

            let bytesDownloaded = bytesUploaded - bytesAlreadyUploaded
            let rate = Double(bytesDownloaded / 1024) / totalTime
            let timeMessage = String(format: "%lld bytes in %.2fs", bytesDownloaded, totalTime)

            if bytesDownloaded > 0 {
                return timeMessage + String(format: " (%.2f KiB/s)", rate)
            } else {
                return timeMessage
            }
        }

        do {
            var newBytesUploaded = bytesAlreadyUploaded
            try await attempt.endpoint.performUpload(
                startPoint: bytesAlreadyUploaded,
                attempt: attempt,
                progressBlock: { chunkUpdate in
                    // We're uploading a chunk starting at bytesAlreadyUploaded, so we need to
                    // offset the progress we've made by the amount we're skipping.
                    let overallUpdate = OWSURLSession.ProgressUpdate(
                        completedByteCount: bytesAlreadyUploaded + chunkUpdate.completedByteCount,
                        totalByteCount: chunkUpdate.totalByteCount != nil ? totalDataLength : nil,
                    )
                    newBytesUploaded = max(newBytesUploaded, overallUpdate.completedByteCount)
                    try await progressBlock(overallUpdate)
                },
            )
            attempt.logger.info("Uploaded chunk of \(downloadTimeLogString(newBytesUploaded)) (now complete at \(newBytesUploaded) bytes)")
        } catch {
            if case .partialUpload = error {
                // This isn't a "failure"; don't report a warning.
            } else if let statusCode = error.httpStatusCode {
                attempt.logger.warn("Couldn't upload (code=\(statusCode)")
            } else {
                attempt.logger.warn("Couldn't upload")
            }

            let failureMode: Upload.FailureMode
            var immediatelyResumeAtByteOffset: UInt64?
            switch error {
            case .partialUpload(let bytesUploaded):
                attempt.logger.info("Uploaded chunk of \(downloadTimeLogString(bytesAlreadyUploaded + bytesUploaded)) (now at \(bytesAlreadyUploaded + bytesUploaded) of \(totalDataLength) bytes)")
                immediatelyResumeAtByteOffset = bytesAlreadyUploaded + bytesUploaded
                failureMode = .resume(.afterBackoff)
            case .uploadFailure(let retryMode):
                // if a failure mode was passed back
                failureMode = retryMode
            case .networkTimeout:
                // if this isn't an understood error, map into a failure mode
                // fetch the progress to determine if we've made progress.
                let uploadProgress = try? await getResumableUploadProgress(forAttempt: attempt)
                switch uploadProgress {
                case .complete:
                    immediatelyResumeAtByteOffset = totalDataLength
                    failureMode = .resume(.afterBackoff)
                case .restart:
                    failureMode = .restart(.afterBackoff)
                case .none:
                    failureMode = .resume(.afterBackoff)
                case .uploaded(let remoteByteCount):
                    if remoteByteCount > bytesAlreadyUploaded {
                        // The remote endpoint reports progress was made, so retry immediately.
                        attempt.logger.info("Uploaded chunk of \(downloadTimeLogString(remoteByteCount)) (now at \(remoteByteCount) of \(totalDataLength) bytes)")
                        immediatelyResumeAtByteOffset = remoteByteCount
                    } else {
                        attempt.logger.warn("Endpoint reported no progress on the prior attempt")
                    }
                    failureMode = .resume(.afterBackoff)
                }
            case .networkError:
                failureMode = .resume(.afterBackoff)
            case .missingFile:
                attempt.logger.error("Missing attachment file!")
                failureMode = .noMoreRetries
            case .invalidUploadURL, .unsupportedEndpoint, .unexpectedResponseStatusCode, .unknown:
                // These errors are unrecoverable, so restart the upload in hopes of correcting the issue.
                failureMode = .restart(.afterBackoff)
            }

            switch failureMode {
            case .noMoreRetries:
                attempt.logger.warn("No more retries.")
                throw error
            case .resume(let recoveryMode):
                switch recoveryMode {
                case .afterBackoff where immediatelyResumeAtByteOffset != nil:
                    // If we confirmed that we made progress, we want to retry immediately.
                    // This may be because we uploaded a single chunk (and have more chunks to
                    // upload) or because we got interrupted partway through and want to start
                    // again immediately. (This flag requires positive confirmation that the
                    // server accepted some number of bytes we sent.)
                    break
                case .afterBackoff:
                    let backoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount, maxAverageBackoff: 14.1 * .minute)
                    attempt.logger.warn(String(format: "Resuming upload after %.3f seconds.", backoff))
                    try await sleepTimer.sleep(for: backoff)
                case .afterServerRequestedDelay(let delay):
                    attempt.logger.warn(String(format: "Resuming upload after %.3f seconds.", delay))
                    try await sleepTimer.sleep(for: delay)
                }
            case .restart:
                // Restart is handled at a higher level since the whole
                // upload form needs to be rebuilt.
                throw Upload.Error.uploadFailure(recovery: failureMode)
            }

            try await performResumableUpload(
                attempt: attempt,
                sleepTimer: sleepTimer,
                // Reset the attempt count to zero if we made confirmed progress.
                failureCount: immediatelyResumeAtByteOffset != nil ? 0 : failureCount + 1,
                immediatelyResumeAtByteOffset: immediatelyResumeAtByteOffset,
                progressBlock: progressBlock,
            )
        }
    }

    // MARK: - Helper Methods

    public static func buildAttempt(
        for localMetadata: Upload.LocalUploadMetadata,
        form: Upload.Form,
        existingSessionUrl: URL? = nil,
        signalService: OWSSignalServiceProtocol,
        fileSystem: Upload.Shims.FileSystem,
        dateProvider: @escaping DateProvider,
        logger: PrefixedLogger,
    ) async throws -> Upload.Attempt<Upload.LocalUploadMetadata> {
        return try await buildAttempt(
            for: localMetadata,
            fileUrl: localMetadata.fileUrl,
            encryptedDataLength: localMetadata.encryptedDataLength,
            form: form,
            existingSessionUrl: existingSessionUrl,
            signalService: signalService,
            fileSystem: fileSystem,
            dateProvider: dateProvider,
            logger: logger,
        )
    }

    public static func buildAttempt(
        for metadata: Upload.LinkNSyncUploadMetadata,
        form: Upload.Form,
        existingSessionUrl: URL? = nil,
        signalService: OWSSignalServiceProtocol,
        fileSystem: Upload.Shims.FileSystem,
        dateProvider: @escaping DateProvider,
        logger: PrefixedLogger,
    ) async throws -> Upload.Attempt<Upload.LinkNSyncUploadMetadata> {
        return try await buildAttempt(
            for: metadata,
            fileUrl: metadata.fileUrl,
            encryptedDataLength: metadata.encryptedDataLength,
            form: form,
            existingSessionUrl: existingSessionUrl,
            signalService: signalService,
            fileSystem: fileSystem,
            dateProvider: dateProvider,
            logger: logger,
        )
    }

    public static func buildAttempt(
        for localMetadata: Upload.EncryptedBackupUploadMetadata,
        form: Upload.Form,
        existingSessionUrl: URL? = nil,
        signalService: OWSSignalServiceProtocol,
        fileSystem: Upload.Shims.FileSystem,
        dateProvider: @escaping DateProvider,
        logger: PrefixedLogger,
    ) async throws -> Upload.Attempt<Upload.EncryptedBackupUploadMetadata> {
        return try await buildAttempt(
            for: localMetadata,
            fileUrl: localMetadata.fileUrl,
            encryptedDataLength: localMetadata.encryptedDataLength,
            form: form,
            existingSessionUrl: existingSessionUrl,
            signalService: signalService,
            fileSystem: fileSystem,
            dateProvider: dateProvider,
            logger: logger,
        )
    }

    public static func buildAttempt<Metadata: UploadMetadata>(
        for localMetadata: Metadata,
        fileUrl: URL,
        encryptedDataLength: UInt32,
        form: Upload.Form,
        existingSessionUrl: URL? = nil,
        signalService: OWSSignalServiceProtocol,
        fileSystem: Upload.Shims.FileSystem,
        dateProvider: @escaping DateProvider,
        logger: PrefixedLogger,
    ) async throws -> Upload.Attempt<Metadata> {
        let endpoint: UploadEndpoint = try {
            switch form.cdnNumber {
            case 2:
                return UploadEndpointCDN2(
                    form: form,
                    signalService: signalService,
                    fileSystem: fileSystem,
                    logger: logger,
                )
            case 3:
                return UploadEndpointCDN3(
                    form: form,
                    signalService: signalService,
                    fileSystem: fileSystem,
                    logger: logger,
                )
            default:
                throw OWSAssertionError("Unsupported Endpoint: \(form.cdnNumber)")
            }
        }()
        let uploadLocation = try await {
            if let existingSessionUrl {
                return existingSessionUrl
            }
            return try await endpoint.fetchResumableUploadLocation()
        }()
        return Upload.Attempt(
            cdnKey: form.cdnKey,
            cdnNumber: form.cdnNumber,
            fileUrl: fileUrl,
            encryptedDataLength: encryptedDataLength,
            localMetadata: localMetadata,
            beginTimestamp: dateProvider().ows_millisecondsSince1970,
            endpoint: endpoint,
            uploadLocation: uploadLocation,
            isResumedUpload: existingSessionUrl != nil,
            logger: logger,
        )
    }
}
