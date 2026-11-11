//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum PaymentsFormat {

    private static func buildMobFormatter(
        isShortForm: Bool,
        locale: Locale? = nil,
    ) -> NumberFormatter {

        let numberFormatter = NumberFormatter()
        numberFormatter.locale = locale ?? Locale.current
        // We use .decimal and not .currency because we don't
        // want to append currency symbol.
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.maximumFractionDigits = (
            isShortForm
                ? 4
                : Int(PaymentsConstants.maxMobDecimalDigits),
        )
        numberFormatter.usesSignificantDigits = false
        numberFormatter.usesGroupingSeparator = true
        if isShortForm {
            numberFormatter.roundingMode = .halfEven
        }
        return numberFormatter
    }

    private static let satoshiFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale.current
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f
    }()

    public static func formatSatoshi(_ picoMob: UInt64) -> String {
        satoshiFormatter.string(from: NSNumber(value: picoMob)) ?? "\(picoMob)"
    }

    // Used for formatting decimal numbers in the
    // send payment flow.  _NOT_ used for display.
    // The format is convenient to parse into an "input string"
    // the corresponds to our custom keyboard.
    private static var doubleFormat: NumberFormatter = {
        // For formatting numbers as arabic numerals without
        // any commas, etc. 1234567.890123
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "en_US")
        // Hide commas.
        numberFormatter.groupingSeparator = ""
        numberFormatter.numberStyle = .decimal

        numberFormatter.maximumFractionDigits = Int(PaymentsConstants.maxMobDecimalDigits)
        numberFormatter.usesSignificantDigits = false
        numberFormatter.roundingMode = .halfEven

        return numberFormatter
    }()

    public static func formatInChat(
        paymentAmount: TSPaymentAmount,
        amountBuilder: (String) -> NSAttributedString,
    ) -> NSAttributedString {
        let mob = PaymentsConstants.convertPicoMobToMob(paymentAmount.picoMob)
        let mobFormat = buildMobFormatter(isShortForm: false)
        guard let amount = mobFormat.string(from: NSNumber(value: mob)) else {
            owsFailDebug("Couldn't format currency.")
            return NSAttributedString(
                string: OWSLocalizedString(
                    "PAYMENTS_CURRENCY_UNKNOWN",
                    comment: "Indicator for unknown currency.",
                ),
            )
        }

        return amountBuilder(amount)
    }

    public static func format(
        paymentAmount: TSPaymentAmount,
        isShortForm: Bool,
        withCurrencyCode: Bool = false,
        withSpace: Bool = false,
        withPaymentType paymentType: TSPaymentType? = nil,
        isSatoshi: Bool = false,
    ) -> String {
        switch paymentAmount.currency {
        case .bitcoin, .mobileCoin:
            guard
                let amountString = format(
                    picoMob: paymentAmount.picoMob,
                    isShortForm: isShortForm,
                )
            else {
                owsFailDebug("Couldn't format currency.")
                return OWSLocalizedString(
                    "PAYMENTS_CURRENCY_UNKNOWN",
                    comment: "Indicator for unknown currency.",
                )
            }

            let amount = isSatoshi ? formatSatoshi(paymentAmount.picoMob) : amountString

            return format(
                amountString: amount,
                withCurrency: withCurrencyCode ? paymentAmount.currency : nil,
                withSpace: withSpace,
                isIncoming: paymentType?.isIncoming,
                isSatoshi: isSatoshi,
            )
        default:
            owsFailDebug("Unknown currency.")
            return OWSLocalizedString(
                "PAYMENTS_CURRENCY_UNKNOWN",
                comment: "Indicator for unknown currency.",
            )
        }
    }

    public static func format(
        amountString: String,
        withCurrency paymentCurrency: TSPaymentCurrency?,
        withSpace: Bool = false,
        isIncoming: Bool? = nil,
        isSatoshi: Bool = false,
    ) -> String {
        var result = ""

        if let isIncoming {
            result += isIncoming ? "+" : "-"
        }

        result += amountString

        if
            let paymentCurrency,
            let currencyCode = isSatoshi
            ? PaymentsConstants.satoshiCurrencyIdentifier
            : identifierFor(currency: paymentCurrency)
        {
            if withSpace {
                result += " "
            }

            result += currencyCode
        }
        return result
    }

    public static func format(mob: Double, isShortForm: Bool) -> String? {
        format(
            picoMob: PaymentsConstants.convertMobToPicoMob(mob),
            isShortForm: isShortForm,
        )
    }

    public static func format(picoMob: UInt64, isShortForm: Bool, locale: Locale? = nil) -> String? {
        let mob = PaymentsConstants.convertPicoMobToMob(picoMob)
        let mobFormat = Self.buildMobFormatter(isShortForm: isShortForm, locale: locale)
        guard let result = mobFormat.string(from: NSNumber(value: mob)) else {
            owsFailDebug("Couldn't format currency.")
            return nil
        }
        return result
    }

    public static func formatAsDoubleString(picoMob: UInt64) -> String? {
        formatAsDoubleString(PaymentsConstants.convertPicoMobToMob(picoMob))
    }

    public static func formatAsDoubleString(_ value: Double) -> String? {
        guard let result = doubleFormat.string(from: NSNumber(value: value)) else {
            owsFailDebug("Couldn't format double.")
            return nil
        }
        return result
    }

    public static func formatAsFiatCurrency(
        paymentAmount: TSPaymentAmount,
        currencyConversionInfo: CurrencyConversionInfo,
        locale: Locale? = nil,
    ) -> String? {
        guard let fiatCurrencyAmount = currencyConversionInfo.convertToFiatCurrency(paymentAmount: paymentAmount) else {
            return nil
        }
        return format(
            fiatCurrencyAmount: fiatCurrencyAmount,
            locale: locale,
        )
    }

    // Used to format fiat currency values for display.
    public static func format(
        fiatCurrencyAmount: Double,
        minimumFractionDigits: Int = 2,
        maximumFractionDigits: Int = 2,
        locale: Locale? = nil,
    ) -> String? {
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = locale ?? Locale.current
        // We use .decimal and not .currency because we don't
        // want to append currency symbol.
        numberFormatter.numberStyle = .decimal
        // TODO: Check with design.
        numberFormatter.minimumFractionDigits = minimumFractionDigits
        numberFormatter.maximumFractionDigits = maximumFractionDigits
        return numberFormatter.string(from: NSNumber(value: fiatCurrencyAmount))
    }

    public static func formatForArchive(picoMob: UInt64) -> String? {
        let paymentFormatLocale = Locale(identifier: "en_US_POSIX")
        return PaymentsFormat.format(
            picoMob: picoMob,
            isShortForm: false,
            locale: paymentFormatLocale,
        )
    }

    public static func formatFromArchive(amount: String?) -> String? {
        guard let amount else { return nil }
        let posixNumberFormatter = NumberFormatter()
        posixNumberFormatter.locale = Locale(identifier: "en_US_POSIX")
        posixNumberFormatter.numberStyle = .decimal

        if let amountMobDouble = posixNumberFormatter.number(from: amount)?.doubleValue {
            // Now format to the current Locale
            return PaymentsFormat.format(mob: amountMobDouble, isShortForm: true)
        }
        return nil
    }

    public static func identifierFor(currency: TSPaymentCurrency) -> String? {
        switch currency {
        case .bitcoin:
            return PaymentsConstants.bitcoinCurrencyIdentifier
        case .mobileCoin:
            return PaymentsConstants.mobileCoinCurrencyIdentifier
        default:
            return nil
        }
    }
}
