//
// Copyright 2026 Radar contributors
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CMonero
import SignalServiceKit

public func MoneroLocalized(_ englishText: String) -> String {
    OWSLocalizedString(englishText, value: englishText, comment: "Monero wallet and payment text.")
}

public struct MoneroPaymentRequest: Equatable, Sendable {
    public let address: String
    public let amount: UInt64?
    public let memo: String?
    public let network: MoneroNetwork
    public let requestID: String

    public init(
        address: String,
        amount: UInt64? = nil,
        memo: String? = nil,
        network: MoneroNetwork,
        requestID: String = UUID().uuidString
    ) throws {
        guard MoneroWalletService.isValidAddress(address, network: network) else {
            throw MoneroWalletError.invalidAddress
        }
        guard amount == nil || amount! > 0 else {
            throw MoneroWalletError.invalidAmount
        }
        self.address = address
        self.amount = amount
        self.memo = memo?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.network = network
        self.requestID = requestID
    }

    public var uri: String {
        var components = URLComponents()
        components.scheme = "monero"
        components.path = address

        var query: [URLQueryItem] = [
            URLQueryItem(name: "network", value: network.queryValue),
            URLQueryItem(name: "r", value: requestID)
        ]
        if let amount {
            query.append(URLQueryItem(name: "tx_amount", value: Self.decimalString(amount)))
        }
        if let memo {
            query.append(URLQueryItem(name: "tx_description", value: memo))
        }
        components.queryItems = query
        return components.string ?? "monero:\(address)"
    }

    public static func parse(_ value: String) -> MoneroPaymentRequest? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: normalized),
              components.scheme?.lowercased() == "monero",
              let address = components.path.nilIfEmpty else {
            return nil
        }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            let key = item.name.lowercased()
            guard query[key] == nil else { return nil }
            query[key] = value
        }
        let network = MoneroNetwork(queryValue: query["network"]) ?? .mainnet
        let amount: UInt64?
        if let amountString = query["tx_amount"] {
            guard let parsed = Self.atomicUnits(amountString), parsed > 0 else { return nil }
            amount = parsed
        } else {
            amount = nil
        }

        return try? MoneroPaymentRequest(
            address: address,
            amount: amount,
            memo: query["tx_description"],
            network: network,
            requestID: query["r"] ?? UUID().uuidString
        )
    }

    public static func parse(_ value: String, fallbackNetwork: MoneroNetwork) -> MoneroPaymentRequest? {
        if let request = parse(value) {
            return request
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let components = URLComponents(string: normalized)
        let isMoneroURI = components?.scheme?.lowercased() == "monero"
        let address = isMoneroURI ? components?.path : normalized
        guard let address, !address.isEmpty else { return nil }

        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            guard let value = item.value else { continue }
            let key = item.name.lowercased()
            guard query[key] == nil else { return nil }
            query[key] = value
        }
        if let networkValue = query["network"], MoneroNetwork(queryValue: networkValue) != fallbackNetwork {
            return nil
        }
        let amount: UInt64?
        if let amountString = query["tx_amount"] {
            guard let parsed = atomicUnits(amountString), parsed > 0 else { return nil }
            amount = parsed
        } else {
            amount = nil
        }
        return try? MoneroPaymentRequest(
            address: address,
            amount: amount,
            memo: query["tx_description"],
            network: fallbackNetwork,
            requestID: query["r"] ?? UUID().uuidString
        )
    }

    public static func parseAddress(_ value: String, network: MoneroNetwork) -> MoneroPaymentRequest? {
        guard let request = try? MoneroPaymentRequest(address: value, network: network) else { return nil }
        return request
    }

    public static func decimalString(_ amount: UInt64) -> String {
        let whole = amount / 1_000_000_000_000
        let fraction = String(format: "%012llu", amount % 1_000_000_000_000)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
        return fraction.isEmpty ? String(whole) : "\(whole).\(fraction)"
    }

    public static func atomicUnits(_ value: String) -> UInt64? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let pattern = #"^[0-9]+(?:\.[0-9]{1,12})?$"#
        guard normalizedValue.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let parts = normalizedValue.split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = UInt64(parts[0]), whole <= UInt64.max / 1_000_000_000_000 else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]).padding(toLength: 12, withPad: "0", startingAt: 0) : String(repeating: "0", count: 12)
        guard let fractional = UInt64(fraction) else { return nil }
        let base = whole * 1_000_000_000_000
        let (result, overflow) = base.addingReportingOverflow(fractional)
        return overflow ? nil : result
    }
}

private extension MoneroNetwork {
    var queryValue: String {
        switch self {
        case .mainnet: return "mainnet"
        case .testnet: return "testnet"
        case .stagenet: return "stagenet"
        }
    }

    init?(queryValue: String?) {
        switch queryValue?.lowercased() {
        case "mainnet": self = .mainnet
        case "testnet": self = .testnet
        case "stagenet": self = .stagenet
        case nil: return nil
        default: return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
