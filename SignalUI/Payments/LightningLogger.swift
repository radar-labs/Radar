//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import BreezSdkSpark
import Foundation
import SignalServiceKit

public final class LightningLogger: BreezSdkSpark.Logger {

    public static let shared = LightningLogger()

    public static let didAppendLogEntryNotification = Notification.Name(
        "LightningLoggerDidAppendLogEntryNotification"
    )

    private static let maxBufferedEntries = 10_000

    private let queue = DispatchQueue(label: "org.signal.lightning-logger", qos: .utility)
    private var buffer: [String] = []

    private static var didInstall = false

    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    public static func installIfNeeded() {
        guard !didInstall else { return }
        didInstall = true
        do {
            try initLogging(logDir: nil, appLogger: shared, logFilter: nil)
        } catch {
            Logger.warn("Failed to install Lightning logger: \(error)")
        }
    }

    public func log(l: LogEntry) {
        let line = "[\(timestampFormatter.string(from: Date()))] [\(l.level)] \(l.line)"
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(line)
            if self.buffer.count > Self.maxBufferedEntries {
                self.buffer.removeFirst(self.buffer.count - Self.maxBufferedEntries)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.didAppendLogEntryNotification,
                    object: nil
                )
            }
        }
    }

    public func currentText() -> String {
        queue.sync { buffer.joined(separator: "\n") }
    }

    public func currentTextTail(maxLines: Int) -> String {
        queue.sync {
            let slice = buffer.suffix(maxLines)
            return slice.joined(separator: "\n")
        }
    }

    public func writeToTemporaryFile() throws -> URL {
        let text = currentText().isEmpty ? "No Lightning logs captured yet." : currentText()
        let fileName = "lightning-logs-\(Int(Date().timeIntervalSince1970)).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
