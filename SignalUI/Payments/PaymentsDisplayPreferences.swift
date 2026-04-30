// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
public import SignalServiceKit

public final class PaymentsDisplayPreferences {

    public static let shared = PaymentsDisplayPreferences()
    private init() {}

    public static let balanceHiddenDidChange = Notification.Name("paymentsBalanceHiddenDidChange")
    public static let amountTypeDidChange = Notification.Name("paymentsAmountTypeDidChange")

    private static let balanceHiddenKey = "payments_balance_hidden"

    public var isBalanceHidden: Bool {
        get { UserDefaults.standard.bool(forKey: Self.balanceHiddenKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.balanceHiddenKey)
            NotificationCenter.default.post(name: Self.balanceHiddenDidChange, object: nil)
        }
    }

    public var isSatoshiEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: PaymentsConstants.satoshiAmountTypeEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: PaymentsConstants.satoshiAmountTypeEnabledKey)
            NotificationCenter.default.post(name: Self.amountTypeDidChange, object: nil)
        }
    }

    @discardableResult
    public func toggleBalanceHidden() -> Bool {
        isBalanceHidden.toggle()
        return isBalanceHidden
    }

    @discardableResult
    public func toggleAmountType() -> Bool {
        isSatoshiEnabled.toggle()
        return isSatoshiEnabled
    }
}
