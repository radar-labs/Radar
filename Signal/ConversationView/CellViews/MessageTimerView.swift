//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

private enum Constants {
    static let layoutSize: CGFloat = 12
    // 0 == about to expire, 12 == just started countdown.
    static let quantizationLevelCount: UInt64 = 12
}

final class MessageTimerUpdater {

    private var animationTimer: Timer?

    deinit {
        clearAnimation()
    }

    func configure(
        expirationTimestampMs: UInt64,
        disappearingMessageInterval: UInt32,
        update: @escaping (UInt64) -> Void,
    ) -> UInt64 {
        let expirationProgress = Self.expirationProgress(
            expirationTimestampMs: expirationTimestampMs,
            disappearingMessageInterval: disappearingMessageInterval,
            nowMs: Date.ows_millisecondTimestamp(),
        )
        startAnimation(expirationProgress: expirationProgress, update: update)
        return expirationProgress.quantizedValue
    }

    static func quantizedValue(
        expirationTimestampMs: UInt64,
        disappearingMessageInterval: UInt32,
    ) -> UInt64 {
        expirationProgress(
            expirationTimestampMs: expirationTimestampMs,
            disappearingMessageInterval: disappearingMessageInterval,
            nowMs: Date.ows_millisecondTimestamp(),
        ).quantizedValue
    }

    static func signalSymbol(quantizedValue: UInt64) -> SignalSymbol {
        switch quantizedValue {
        case 0: .messageTimer00
        case 1: .messageTimer05
        case 2: .messageTimer10
        case 3: .messageTimer15
        case 4: .messageTimer20
        case 5: .messageTimer25
        case 6: .messageTimer30
        case 7: .messageTimer35
        case 8: .messageTimer40
        case 9: .messageTimer45
        case 10: .messageTimer50
        case 11: .messageTimer55
        default: .messageTimer60
        }
    }

    private struct ExpirationProgress {
        var quantizedValue: UInt64
        var timerConfiguration: TimerConfiguration?
    }

    private struct TimerConfiguration {
        let nextRefreshMs: UInt64
        let refreshIntervalMs: UInt64
    }

    private static func expirationProgress(
        expirationTimestampMs: UInt64,
        disappearingMessageInterval: UInt32,
        nowMs: UInt64,
    ) -> ExpirationProgress {
        // Every N milliseconds we move to the next progress level.
        let refreshIntervalMs = UInt64(disappearingMessageInterval) * 1000 / Constants.quantizationLevelCount

        // It will never expire because the timer hasn't started yet.
        guard expirationTimestampMs > 0, refreshIntervalMs > 0 else {
            return ExpirationProgress(quantizedValue: Constants.quantizationLevelCount)
        }

        let remainingMs = expirationTimestampMs.subtractingReportingOverflow(nowMs)
        // It already expired because the expiration date is in the past.
        guard !remainingMs.overflow else {
            return ExpirationProgress(quantizedValue: 0)
        }

        let intermediateValue = remainingMs.partialValue.addingReportingOverflow(refreshIntervalMs / 2)
        // The disappearing interval is way too large -- something is wrong.
        guard !intermediateValue.overflow else {
            return ExpirationProgress(quantizedValue: Constants.quantizationLevelCount)
        }

        let quantizedValue = intermediateValue.partialValue / refreshIntervalMs
        return ExpirationProgress(
            quantizedValue: quantizedValue,
            timerConfiguration: {
                guard quantizedValue > 0 else {
                    return nil
                }
                return TimerConfiguration(
                    nextRefreshMs: expirationTimestampMs - (quantizedValue - 1) * refreshIntervalMs - refreshIntervalMs / 2,
                    refreshIntervalMs: refreshIntervalMs,
                )
            }(),
        )
    }

    private func startAnimation(
        expirationProgress: ExpirationProgress,
        update: @escaping (UInt64) -> Void,
    ) {
        AssertIsOnMainThread()

        clearAnimation()
        guard let timerConfiguration = expirationProgress.timerConfiguration else {
            return
        }

        var quantizedValue = expirationProgress.quantizedValue
        let animationTimer = Timer(
            fire: Date(millisecondsSince1970: timerConfiguration.nextRefreshMs),
            interval: TimeInterval(timerConfiguration.refreshIntervalMs) / 1000,
            repeats: true,
            block: { timer in
                quantizedValue -= 1
                update(quantizedValue)
                guard quantizedValue > 0 else {
                    timer.invalidate()
                    return
                }
            },
        )
        self.animationTimer = animationTimer
        RunLoop.main.add(animationTimer, forMode: .common)
    }

    func clearAnimation() {
        AssertIsOnMainThread()

        animationTimer?.invalidate()
        animationTimer = nil
    }
}

final class MessageTimerView: ManualLayoutView {

    private let imageView = CVImageView()
    private let timerUpdater = MessageTimerUpdater()

    init() {
        super.init(name: "OWSMessageTimerView")

        addSubviewToFillSuperviewEdges(imageView)
    }

    func configure(
        expirationTimestampMs: UInt64,
        disappearingMessageInterval: UInt32,
        tintColor: UIColor,
    ) {
        let quantizedValue = timerUpdater.configure(
            expirationTimestampMs: expirationTimestampMs,
            disappearingMessageInterval: disappearingMessageInterval,
            update: { [weak self] quantizedValue in
                self?.updateIcon(quantizedValue: quantizedValue, tintColor: tintColor)
            },
        )
        updateIcon(quantizedValue: quantizedValue, tintColor: tintColor)
    }

    private func updateIcon(quantizedValue: UInt64, tintColor: UIColor) {
        let progressIcon = self.progressIcon(quantizedValue: quantizedValue, tintColor: tintColor)
        imageView.image = progressIcon?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = tintColor
    }

    private func progressIcon(quantizedValue: UInt64, tintColor: UIColor) -> UIImage? {
        owsAssertDebug(quantizedValue <= Constants.quantizationLevelCount)
        let imageName = String(format: "messagetimer-%02ld", quantizedValue * 5)
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Missing icon.")
            return nil
        }
        owsAssertDebug(image.size.width == Constants.layoutSize)
        owsAssertDebug(image.size.height == Constants.layoutSize)
        return image
    }

    func prepareForReuse() {
        timerUpdater.clearAnimation()
        imageView.image = nil
    }

    static var measureSize: CGSize {
        .square(Constants.layoutSize)
    }
}
