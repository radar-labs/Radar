//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension Optional {

    public func mapAsync<T>(_ fn: (Wrapped) async throws -> T) async rethrows -> T? {
        switch self {
        case nil:
            return nil
        case .some(let v):
            return try await fn(v)
        }
    }

    public func owsFailUnwrap(
        _ message: String,
        logger: PrefixedLogger = .empty(),
        file: String = #file,
        function: String = #function,
        line: Int = #line,
    ) -> Wrapped {
        switch self {
        case nil:
            owsFail(message, logger: logger, file: file, function: function, line: line)
        case .some(let value):
            return value
        }
    }
}
