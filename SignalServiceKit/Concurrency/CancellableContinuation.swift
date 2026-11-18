//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A container that immediately resumes when canceled.
///
/// This is useful when there is no operation that needs to be canceled. For
/// example, when waiting for an event to occur, "cancellation" means "stop
/// waiting for the event to occur" and not "stop the event from occurring".
public struct CancellableContinuation<T>: Sendable {
    private let deferredContinuation = DeferredContinuation<T>()

    public init() {
    }

    func cancel() {
        self.deferredContinuation.resume(with: .failure(CancellationError()))
    }

    /// Resumes the continuation with `result`.
    ///
    /// It's safe (and harmless) to call `resume` multiple times; redundant
    /// invocations are ignored.
    public func resume(with result: Result<T, Error>) {
        self.deferredContinuation.resume(with: result)
    }

    /// Waits for the result. Should only be called once per instance!
    public func wait() async throws -> T {
        try await withTaskCancellationHandler(
            operation: { try await self.deferredContinuation.wait() },
            onCancel: { self.cancel() },
        )
    }
}
