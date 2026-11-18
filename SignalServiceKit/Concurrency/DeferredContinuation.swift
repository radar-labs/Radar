//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A container that stores a Result before creating a continuation.
public struct DeferredContinuation<T>: Sendable {
    private enum State {
        case initial
        case waiting(CheckedContinuation<T, Error>)
        case completed(Result<T, Error>)
        case consumed
    }

    private let state = AtomicValue<State>(State.initial, lock: .init())

    public init() {
    }

    /// Resumes the continuation with `result`.
    ///
    /// It's safe (and harmless) to call `resume` multiple times; redundant
    /// invocations are ignored.
    public func resume(with result: Result<T, Error>) {
        let continuation = self.state.update { state -> CheckedContinuation<T, Error>? in
            switch state {
            case .initial:
                state = .completed(result)
                return nil
            case .waiting(let continuation):
                state = .consumed
                return continuation
            case .completed(_), .consumed:
                // Ignore the new result.
                return nil
            }
        }
        if let continuation {
            continuation.resume(with: result)
        }
    }

    /// Waits for the result. Should only be called once per instance!
    public func wait() async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            let result = self.state.update { state -> Result<T, Error>? in
                switch state {
                case .initial:
                    state = .waiting(continuation)
                    return nil
                case .completed(let result):
                    state = .consumed
                    return result
                case .waiting(_), .consumed:
                    continuation.resume(throwing: OWSAssertionError(
                        "should not await a DeferredContinuation multiple times",
                    ))
                    return nil
                }
            }
            if let result {
                continuation.resume(with: result)
            }
        }
    }
}
