//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import zlib

public class GzipStreamTransform: StreamTransform, FinalizableStreamTransform {
    public static let optionsKey = "GzipTransformOptions"

    public struct Options: OptionSet {
        public var rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        // Force a Z_FULL_FLUSH on the next processing operation.
        // This is a no-op for `GzipStreamTransform.Operation.decompress`
        static let forceFlush = Self(rawValue: 1 << 1)

        // Enter the 'interval tracking' flush behavior.  This will write a certain
        // intervals of data before issuing a Z_FULL_FLUSH
        // This is a no-op for `GzipStreamTransform.Operation.decompress`
        static let intervalFlush = Self(rawValue: 1 << 2)
    }

    public enum Operation {
        case compress
        case decompress
    }

    public enum GzipError: Swift.Error {
        case initializeFailed
        case streamError
        case dataError
        case outOfMemoryError
        case transformFailed
        case finalizeFailed
    }

    private enum Constants {
        static let BufferSize: Int = 65_536

        // Use the maximum memory window (32K) for compressing the data
        static let MaxWindowBits = MAX_WBITS

        // adding 16 to the window bits will signal the gzip header should be written
        static let GzipDeflateHeaderWindowBits: Int32 = 16

        // adding 32 to the window bits will signal the gzip header/footer should be read
        static let GzipInflateHeaderWindowBits: Int32 = 32
    }

    public private(set) var hasFinalized = false

    // The overall output generated (in bytes)
    private var outputCount: UInt64 = 0

    // The largest bytes interval encountered
    private var maxIntervalBytes: UInt64 = 0

    // Estimated size of the prior backup used to estimate the flush interval
    private var estimatedTotalUncompressedLength: UInt64?

    // Set to true if `intervalFlush` has been passed as an option.
    // Currently, once interval flushing has started, it remains in place for the duration of the stream
    private var isTrackingFlushIntervals: Bool = false

    // The byte count at the beginning of the region that requires flush intervals
    private var bytesSinceRegionStart: UInt64 = 0

    // The number of bytes processed in the current interval
    // This is the number compared to value returned by libSignal flushInterval()
    // to determine if a new interval should be started
    private var bytesSinceIntervalStart: UInt64 = 0

    private var stream: z_stream
    private let operation: Operation

    init(_ operation: Operation, estimatedTotalUncompressedLength: UInt64? = nil) throws {
        self.operation = operation
        self.estimatedTotalUncompressedLength = estimatedTotalUncompressedLength
        self.stream = z_stream()

        var status = Z_OK
        switch operation {
        case .compress:
            status = deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                Constants.MaxWindowBits + Constants.GzipDeflateHeaderWindowBits,
                MAX_MEM_LEVEL,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size),
            )
        case .decompress:
            status = inflateInit2_(
                &stream,
                Constants.MaxWindowBits + Constants.GzipInflateHeaderWindowBits,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size),
            )
        }

        guard status == Z_OK else {
            throw GzipError.initializeFailed
        }
    }

    /// Pass the supplied `data` to zlib for processing and return any data that results.
    /// Note that there is no guarantee that data will be retuned from the transform since compression/decompression
    /// will buffer internally.
    public func transform(data: Data, options: StreamTransform.Options) throws -> Data {
        try process(data: data, options: options, finalize: false)
    }

    private var buffer = Data(count: Constants.BufferSize)

    // The various steps that can happen in the processing of a gzip data buffer.
    private enum ProcessStep {

        // Process the data via inflate/deflate.
        // Note: UIn32 limit due to zlib API limits.
        case process(UInt32)

        // Processing is finished. Close the stream.
        case finalize

        // Close the current processing block at the zlib level.
        // Note this is only applicable to `deflate` and translates to a no-op for `inflate`
        case flush

        var flags: Int32 {
            switch self {
            case .finalize: Z_FINISH
            case .flush: Z_FULL_FLUSH
            case .process: Z_NO_FLUSH
            }
        }
    }

    private func process(data: Data, options: StreamTransform.Options, finalize: Bool) throws -> Data {

        var status: Int32 = Z_OK
        var currentOffset = 0
        var operationQueue = [ProcessStep]()

        if finalize {
            operationQueue.append(.finalize)
        } else {
            // If the buffer is larger that zlib can handle, split into multiple passes
            operationQueue.append(contentsOf: splitLargeProcessStepsIfNecessary(size: data.count))
            if let options = options[Self.optionsKey] as? GzipStreamTransform.Options {
                if options.contains(.forceFlush) {
                    // Flush after processing
                    operationQueue.append(.flush)
                } else if options.contains(.intervalFlush) {
                    if !isTrackingFlushIntervals {
                        // Insert a flush the first time intervalFlush is encountered
                        operationQueue.insert(.flush, at: 0)
                    }
                    isTrackingFlushIntervals = true
                }
            }
        }

        try data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in

            // Initialized the input buffer.
            // Set stream.next_in to point at the passed in data buffer.
            // Then move the pointer forward the amount of data that's aready been passed to deflate()
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: ptr.bindMemory(to: Bytef.self).baseAddress!)

            while !operationQueue.isEmpty, status != Z_STREAM_END {
                let proposedStep = operationQueue.removeFirst()

                // Check if the currently proposed step needs to be split into multiple steps
                // The method returns the step to be run, along with any followup steps that
                // may need to exeucute after this. These followup steps should be considered 'part'
                // of the current step, so insert them at the head of the queue.
                let (step, operationsToPush) = splitStepsOnFlushIntervalIfNecessary(proposedStep)
                operationQueue.insert(contentsOf: operationsToPush, at: 0)

                switch step {
                case .finalize, .flush:
                    stream.avail_in = 0
                case .process(let bytesToProcess):
                    stream.avail_in = bytesToProcess
                }

                // `stream.avail_in` will reflect the number of bytes in the buffer to process
                // going into the inflate/deflate calls, but these calls will adjust `avail_in`
                // as processing happens. After the calls, `avail_in` will reflect a count of any
                // unprocessed bytes still in the buffer. So, capture how many bytes should be processed
                // before processing happens so this value can be used in accounting after the calls.
                var bufferBytesConsumedThisLoop = UInt64(safeCast: stream.avail_in)

                repeat {
                    buffer.withUnsafeMutableBytes { (outputPtr: UnsafeMutableRawBufferPointer) in
                        // Set stream.next_out to point at the output buffer and move the pointer
                        // forward the amount of data that's already been written to the output buffer.
                        // In most use cases `bufferWritten` should be '0', but there is nothing preventing
                        // inflate/deflate from returning without having processed the entire input.
                        // If this happens, and `avail_out` > 0, we should attempt to append to the output
                        // buffer on subsequent calls into inflate/deflate
                        stream.next_out = outputPtr.bindMemory(to: Bytef.self).baseAddress!.advanced(by: currentOffset)
                        stream.avail_out = UInt32(outputPtr.count - currentOffset)

                        switch operation {
                        case .compress:
                            status = deflate(&stream, step.flags)
                        case .decompress:
                            status = inflate(&stream, step.flags)
                        }

                        currentOffset = outputPtr.count - Int(stream.avail_out)
                        stream.next_out = nil
                    }

                    // From zlib docs:
                    // "If inflate (or deflate) returns Z_OK and with zero avail_out, it must be called again
                    // after making room in the output buffer because there might be more output pending."
                    if stream.avail_out == 0 {
                        buffer.count *= 2
                        // currentOffset can remain the same
                    }

                    // Continue to call deflate/inflate as long as the status remains Z_OK and one of the
                    // following is true:
                    //   a) The stream reports that the output buffer is full (avail_out == 0). This signals
                    //      that there may be additional output available, but the output buffer ran out of room.
                    //   b) There is still data available to pass into inflate/deflate (avail_in > 0). The
                    //      situations where this occurs should be less frequent (e.g. - input larger
                    //      than inflate/deflate can handle in one call) or happen in association
                    //      with (a) above.
                    //
                    // From the zlib docs:
                    //   "If not all input can be processed (because there is not enough room in the output
                    //    buffer), then next_in and avail_in are updated accordingly, and processing will
                    //    resume at this point for the next call of inflate (or deflate)."
                } while
                    (stream.avail_out == 0 || stream.avail_in > 0) && status == Z_OK

                // If the above processing loop is exited due to status != Z_OK, adjust
                // bufferBytesConsumedThisLoop to account for any data that might not have been processed.
                // The only two non-error scenarios that could drop out of the loop are Z_BUF_ERROR & Z_STREAM_END
                // Z_STREAM_END means no more processing can happen, and Z_BUF_ERROR is effectively Z_OK with
                // a note that the output exactly filled the output buffer. (See below for more explanation)
                // All this to say, this adjustment doesn't really affect the processing of the stream,
                // but does make this value more accurate if it's being used for debugging/logging.
                bufferBytesConsumedThisLoop -= UInt64(safeCast: stream.avail_in)

                // If interval flushing is active, keep track of how many bytes have been processed,
                // both overall (for the end padding), and for this interval (to be used in the
                // interval boundary checks)
                if isTrackingFlushIntervals {
                    self.bytesSinceRegionStart += bufferBytesConsumedThisLoop
                    self.bytesSinceIntervalStart += bufferBytesConsumedThisLoop
                }

                if case .flush = step {
                    // As part of the interval flush, keep track of the largest interval.
                    // This is used to determine the proper padding at the end of the stream.
                    maxIntervalBytes = max(maxIntervalBytes, bytesSinceIntervalStart)

                    // Reset the interval count on every flush
                    bytesSinceIntervalStart = 0
                }

                switch status {
                case Z_OK, Z_STREAM_END:
                    break
                case Z_STREAM_ERROR:
                    throw GzipError.streamError
                case Z_DATA_ERROR:
                    throw GzipError.dataError
                case Z_MEM_ERROR:
                    throw GzipError.outOfMemoryError
                case Z_BUF_ERROR:
                    // This usually indicates that the deflate has no more output, but the final
                    // chunk of output _exactly_ fills the output buffer, causing avail_out to be 0.
                    // This will cause the code above to attempt another deflate, but since there's
                    // nothing further to read, deflate() needs to signal back to the caller with
                    // Z_BUF_ERROR that it was no longer able to either consume input or produce output.
                    // According to zlib docs, Z_BUF_ERROR doesn't need to be checked for inflate()
                    break
                default:
                    throw GzipError.transformFailed
                }
            }
        }

        let returnData = buffer.prefix(currentOffset)
        outputCount += UInt64(returnData.count)
        return returnData
    }

    /// zlib processing works in terms of UInt32 pointers, so given a possibly > UInt32.max buffer size,
    /// decompose the processing step into multiple <=UInt32.max steps
    private func splitLargeProcessStepsIfNecessary(size: Int) -> [ProcessStep] {
        return stride(from: 0, to: size, by: Int(UInt32.max)).map { offset in
            let stepSize = UInt32(min(Int(UInt32.max), size - offset))
            return ProcessStep.process(stepSize)
        }
    }

    /// Check if the given step needs to be decomposed into multiple processing steps due to hitting
    /// a flush interval during output.  If a flush intervals are active, and an interval is reached, the current
    /// `process` step will be broken into up to three steps:
    ///
    /// 1. Process remianing bytes in interval
    /// 2. Flush
    /// 3. If necessary, process the rest of the bytes. This could result itself result
    ///   in the next interval window being filled, but that operation would then fall back
    ///   into this section when it's processed
    ///
    private func splitStepsOnFlushIntervalIfNecessary(_ step: ProcessStep) -> (ProcessStep, [ProcessStep]) {
        switch step {
        case .finalize:
            return (step, [])
        case .flush:
            return (step, [])
        case .process(let numberOfBytesToProcess):
            guard isTrackingFlushIntervals else { return (step, []) }

            let currentIntervalSize = MessageBackupSizing.flushInterval(
                uncompressedLength: bytesSinceRegionStart,
                estimatedTotalUncompressedLength: estimatedTotalUncompressedLength,
            )

            // Determine how many bytes are remaining in this flush interval
            let (remainingBytesInInterval, underflow) = currentIntervalSize.subtractingReportingOverflow(bytesSinceIntervalStart)

            if underflow {
                // The interval has already been passed, so immediately flush and try the step again.
                // Also log an error since this shouldn't happen
                Logger.error("Missed a flush interval")
                return (.flush, [step])
            }

            guard numberOfBytesToProcess >= remainingBytesInInterval else {
                // No flush necessary, return the passed in step
                return (step, [])
            }

            // Number of bytes to process exceeds this interval, split things up.
            //
            // Note: The UInt32 cast below is safe due to the prior guard checking <= numberOfBytesToProcess
            let firstBlock = UInt32(remainingBytesInInterval)
            let processRemainingIntervalOperation = ProcessStep.process(firstBlock)
            var nextSteps: [ProcessStep] = [.flush]
            let remaining = numberOfBytesToProcess - firstBlock
            if remaining > 0 {
                nextSteps.append(.process(remaining))
            }
            return (processRemainingIntervalOperation, nextSteps)
        }
    }

    public func finalize() throws -> Data {
        hasFinalized = true

        // Finalize the gzip and return any remaining data
        var finalData = try process(data: Data(), options: [:], finalize: true)

        // Do one final check of the last interval to see if it was the largest
        self.maxIntervalBytes = max(maxIntervalBytes, bytesSinceIntervalStart)

        switch operation {
        case .compress:
            let paddingSize = MessageBackupSizing.paddingSize(
                maxIntervalBytes: maxIntervalBytes,
                compressedLength: outputCount,
            )
            finalData.append(Data(repeating: 0, count: Int(paddingSize)))
        case .decompress:
            break
        }

        // Close the zlib stream
        var status = Z_OK
        switch operation {
        case .compress:
            status = deflateEnd(&stream)
        case .decompress:
            status = inflateEnd(&stream)
        }
        guard status == Z_OK else {
            throw GzipError.finalizeFailed
        }

        return finalData
    }
}
