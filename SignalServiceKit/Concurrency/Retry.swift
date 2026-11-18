//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum Retry {

    // MARK: -

    /// Performs `block` repeatedly until `onError` throws an error (or until cancellation).
    public static func performRepeatedly<T, E>(block: () async throws(E) -> T, onError: (E, _ attemptCount: Int) async throws -> Void) async throws -> T {
        var attemptCount = 0
        while true {
            try Task.checkCancellation()
            do {
                attemptCount += 1
                return try await block()
            } catch {
                try await onError(error, attemptCount)
            }
        }
    }

    // MARK: -

    public struct MinimumBackoff {
        fileprivate let wrappedValue: TimeInterval

        private init(wrappedValue: TimeInterval) {
            self.wrappedValue = wrappedValue
        }

        public static func retryAfterBackoff() -> Self {
            return Self(wrappedValue: 0)
        }

        public static func retryAfterAtLeast(_ delay: TimeInterval) -> Self {
            return Self(wrappedValue: delay)
        }
    }

    /// Performs `block` repeatedly with backoff.
    ///
    /// This method will invoke `block` at most `maxAttempts` times, propagating
    /// the error from the final attempt. If `block` throws an error that's
    /// rethrown by `onError`, that error will be propagated immediately.
    ///
    /// The backoff interval will be the larger of "exponential backoff based on
    /// the number of attempts" and "the `MinimumBackoff` value returned from
    /// `onError`". As an example, this allows callers to increase the backoff
    /// delay based on a Retry-After header (but it doesn't allow them to
    /// decrease the delay based on a Retry-After header).
    ///
    /// This method supports cancellation.
    public static func performWithMinimumBackoff<T, E>(
        maxAttempts: Int,
        minAverageBackoff: TimeInterval = ExponentialBackoff.Defaults.minAverageBackoff,
        maxAverageBackoff: TimeInterval = ExponentialBackoff.Defaults.maxAverageBackoff,
        block: () async throws(E) -> T,
        onError: (E) async throws(E) -> MinimumBackoff,
    ) async throws -> T {
        return try await performRepeatedly(
            block: block,
            onError: { error, attemptCount in
                if attemptCount >= maxAttempts {
                    throw error
                }
                let minimumRetryDelay = try await onError(error)
                let exponentialRetryDelay = OWSOperation.retryIntervalForExponentialBackoff(
                    failureCount: attemptCount,
                    minAverageBackoff: minAverageBackoff,
                    maxAverageBackoff: maxAverageBackoff,
                )
                let retryDelay = max(minimumRetryDelay.wrappedValue, exponentialRetryDelay)
                try await Task.sleep(nanoseconds: retryDelay.clampedNanoseconds)
            },
        )
    }

    // MARK: -

    /// Performs `block` repeatedly with backoff.
    ///
    /// This method will invoke `block` at most `maxAttempts` times, propagating
    /// the error from the final attempt. If `block` throws an error where
    /// `isRetryable` returns false, that error will be propagated immediately.
    ///
    /// The backoff interval will be, at minimum, an exponential backoff
    /// determined by the `minAverageBackoff` and `maxAverageBackoff`
    /// parameters. Additionally, callers may use `preferredBackoffBlock` to ask
    /// for an error-specific backoff that will be respected if it is longer
    /// than the minimum; for example, to respect a Retry-After header.
    ///
    /// This method supports cancellation.
    ///
    /// - SeeAlso
    /// ``OWSOperation/retryIntervalForExponentialBackoff(failureCount:minAverageBackoff:maxAverageBackoff:)``.
    public static func performWithBackoff<T, E>(
        maxAttempts: Int,
        minAverageBackoff: TimeInterval = ExponentialBackoff.Defaults.minAverageBackoff,
        maxAverageBackoff: TimeInterval = ExponentialBackoff.Defaults.maxAverageBackoff,
        preferredBackoffBlock: (Error) -> TimeInterval? = { _ in nil },
        isRetryable: (E) -> Bool = { !$0.isFatalError && $0.isRetryable },
        block: () async throws(E) -> T,
    ) async throws -> T {
        return try await Retry.performWithMinimumBackoff(
            maxAttempts: maxAttempts,
            minAverageBackoff: minAverageBackoff,
            maxAverageBackoff: maxAverageBackoff,
            block: block,
            onError: { (error) throws(E) in
                guard isRetryable(error) else {
                    throw error
                }
                return .retryAfterAtLeast(preferredBackoffBlock(error) ?? 0)
            },
        )
    }
}
