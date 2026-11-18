//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

@MainActor
class ThroughputMonitor {

    private var previouslyCompletedBytes: Double = 0
    private var lastWholeNumberProgress = 0
    private var throughputTimer: Timer?
    let progress: Progress

    init(progress: Progress) {
        self.progress = progress
    }

    func start() {
        stop()

        previouslyCompletedBytes = Double(progress.totalUnitCount) * progress.fractionCompleted

        throughputTimer = WeakTimer.scheduledTimer(
            timeInterval: 1,
            target: self,
            userInfo: nil,
            repeats: true,
        ) { [weak self] _ in
            self?.tick()
        }
        throughputTimer?.fire()
    }

    func tick() {
        let completedBytes = Double(progress.totalUnitCount) * progress.fractionCompleted
        let bytesOverLastSecond = completedBytes - self.previouslyCompletedBytes
        let remainingBytes = Double(progress.totalUnitCount) - completedBytes
        self.previouslyCompletedBytes = completedBytes

        if let averageThroughput = progress.throughput {
            // Give more weight to the existing average than the new value
            // to "smooth" changes in throughput and estimated time remaining.
            let newAverageThroughput = 0.2 * Double(bytesOverLastSecond) + 0.8 * Double(averageThroughput)
            progress.throughput = Int(newAverageThroughput)
            progress.estimatedTimeRemaining = remainingBytes / newAverageThroughput
        } else {
            progress.throughput = Int(bytesOverLastSecond)
            progress.estimatedTimeRemaining = remainingBytes / TimeInterval(bytesOverLastSecond)
        }

        self.logProgress(progress, remainingBytes: remainingBytes)
    }

    func stop() {
        throughputTimer?.invalidate()
        throughputTimer = nil
        previouslyCompletedBytes = 0
        lastWholeNumberProgress = 0
    }

    private func logProgress(_ progress: Progress, remainingBytes: Double) {
        let currentWholeNumberProgress = Int(progress.fractionCompleted * 100)
        let percentChange = currentWholeNumberProgress - lastWholeNumberProgress

        defer { lastWholeNumberProgress = currentWholeNumberProgress }

        // Determine how frequently to log progress updates. If in verbose mode, we log
        // every 1%. Otherwise, every 10%.
        guard percentChange >= (DebugFlags.deviceTransferVerboseProgressLogging ? 1 : 10) else { return }

        var progressLog = String(format: "Transfer progress %d%%", currentWholeNumberProgress)

        var remainingNumber = remainingBytes
        var remainingUnits = "B"
        if remainingNumber / 1024 >= 1 {
            remainingNumber /= 1024
            remainingUnits = "KiB"
        }
        if remainingNumber / 1024 >= 1 {
            remainingNumber /= 1024
            remainingUnits = "MiB"
        }
        if remainingNumber / 1024 >= 1 {
            remainingNumber /= 1024
            remainingUnits = "GiB"
        }

        progressLog += String(format: " / %0.2f %@ remaining", remainingNumber, remainingUnits)

        if let throughput = progress.throughput {
            var transferSpeed = Double(throughput) / 1024
            var transferUnits = "KiB/s"
            if transferSpeed / 1024 >= 1 {
                transferSpeed /= 1024
                transferUnits = "MiB/s"
            }

            progressLog += String(format: " / %0.2f %@", transferSpeed, transferUnits)
        }

        if let estimatedTime = progress.estimatedTimeRemaining, estimatedTime.isFinite {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            formatter.unitsStyle = .full
            formatter.maximumUnitCount = 2
            formatter.includesApproximationPhrase = true
            formatter.includesTimeRemainingPhrase = true

            let formattedString = formatter.string(from: estimatedTime)!

            progressLog += " / \(formattedString)"
        }

        Logger.info(progressLog)
    }
}
