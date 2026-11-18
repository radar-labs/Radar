//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

/// Abstract base class for jobs that need to delete elements as those elements
/// "expire" while the app is running.
///
/// Implementations should override the `open` methods below, pursuant to their
/// documentation.
///
/// When new expiring elements are saved, callers should call ``restart()`` to
/// tell the `ExpirationJob` that the "next-expiring element" may have changed.
open class ExpirationJob<ExpiringElement> {
    private let dateProvider: DateProvider
    private let db: DB
    private let minIntervalBetweenDeletes: TimeInterval

    public let logger: PrefixedLogger

    private struct State {
        var isRunning = false
        var delayValidityToken: UInt = 0
        var nextExpirationDelayTask: Task<Void, Never>?
    }

    private let state = AtomicValue(State(), lock: .init())

    public init(
        dateProvider: @escaping DateProvider,
        db: DB,
        logger: PrefixedLogger,
        minIntervalBetweenDeletes: TimeInterval = 1,
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.logger = logger
        self.minIntervalBetweenDeletes = minIntervalBetweenDeletes
    }

    // MARK: -

    /// Returns the next element that will expire, regardless of whether that
    /// element is currently expired.
    open func nextExpiringElement(tx: DBReadTransaction) -> ExpiringElement? {
        owsFail("Must be overridden by subclasses!")
    }

    /// Returns the expiration date of the given element.
    open func expirationDate(ofElement element: ExpiringElement) -> Date {
        owsFail("Must be overridden by subclasses!")
    }

    /// Deletes the given element, which is guaranteed to have expired when this
    /// is called.
    open func deleteExpiredElement(_ element: ExpiringElement, tx: DBWriteTransaction) {
        owsFail("Must be overridden by subclasses!")
    }

    // MARK: -

    /// "Restart" a running job, such that it can detect potential new expiring
    /// elements. Callers should do this any time the underlying store of
    /// `ExpiringElement` changes such that expiration status may be affected.
    ///
    /// For example, for the disappearing messages job, this should be called
    /// whenever a message's "expiration timer" starts or changes.
    public final func restart() {
        state.update { _state in
            _state.delayValidityToken += 1
            _state.nextExpirationDelayTask?.cancel()
        }
    }

    public func run() async throws {
        // We can only run() the task once at a time.
        state.update {
            owsPrecondition(!$0.isRunning)
            $0.isRunning = true
        }
        defer {
            state.update {
                $0.isRunning = false
            }
        }

        // When the Task is running, listen for significant time changes.
        let observer = NotificationCenter.default.addObserver(
            name: UIApplication.significantTimeChangeNotification,
            block: { [weak self] _ in
                self?.restart()
            },
        )
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        while true {
            let nextExpirationDelayTask: Task<Void, Never>

            let delayValidityToken = state.get().delayValidityToken
            let nextExpirationDate = try await deleteExpiredElements()

            let now = dateProvider()
            var nextExpirationDelay = (nextExpirationDate ?? .distantFuture).timeIntervalSince(now)

            nextExpirationDelayTask = state.update { _state in
                if _state.delayValidityToken != delayValidityToken {
                    // If the token has changed, we can't trust the delay we just computed. Use
                    // a minimum delay instead.
                    nextExpirationDelay = 0
                }

                let nextExpirationDelayTask = Task {
                    _ = try? await Task.sleep(nanoseconds: nextExpirationDelay.clampedNanoseconds)
                }
                _state.nextExpirationDelayTask = nextExpirationDelayTask
                return nextExpirationDelayTask
            }

            // Always wait for at least minIntervalBetweenDeletes.
            try await Task.sleep(nanoseconds: minIntervalBetweenDeletes.clampedNanoseconds)

            // Then, wait until the next expiration (but stop waiting if we're canceled).
            await withTaskCancellationHandler(
                operation: { await nextExpirationDelayTask.value },
                onCancel: { nextExpirationDelayTask.cancel() },
            )
            // To distinguish between "run() was canceled" and "restart() was called".
            try Task.checkCancellation()
        }
    }

    private func deleteExpiredElements() async throws -> Date? {
        var deletedCount = 0
        defer {
            if deletedCount > 0 {
                logger.info("Deleted \(deletedCount) elements.")
            }
        }
        try Task.checkCancellation()
        return try await TimeGatedBatch.processAll(db: db) { tx throws -> TimeGatedBatch.ProcessBatchResult<Date?> in
            try Task.checkCancellation()
            let element = nextExpiringElement(tx: tx)
            if let element, dateProvider() >= expirationDate(ofElement: element) {
                // Expired element: delete it and keep iterating.
                deleteExpiredElement(element, tx: tx)
                deletedCount += 1
                return .more
            }
            // Nothing expired to delete: stop iterating.
            return .done(element.map(expirationDate(ofElement:)))
        }
    }
}
