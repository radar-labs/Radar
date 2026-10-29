import XCTest
@testable import SignalUI
import SignalServiceKit
import CMonero

final class MoneroPaymentRequestTests: XCTestCase {
    func testAmountConversion() {
        XCTAssertEqual(MoneroPaymentRequest.atomicUnits("1"), 1_000_000_000_000)
        XCTAssertEqual(MoneroPaymentRequest.atomicUnits("0.000000000001"), 1)
        XCTAssertEqual(MoneroPaymentRequest.atomicUnits("0,01"), 10_000_000_000)
        XCTAssertEqual(MoneroPaymentRequest.atomicUnits(" 0,01 "), 10_000_000_000)
        XCTAssertEqual(MoneroPaymentRequest.atomicUnits("12.34"), 12_340_000_000_000)
        XCTAssertNil(MoneroPaymentRequest.atomicUnits("1.0000000000001"))
        XCTAssertNil(MoneroPaymentRequest.atomicUnits("-1"))
    }

    func testDecimalFormatting() {
        XCTAssertEqual(MoneroPaymentRequest.decimalString(1_000_000_000_000), "1")
        XCTAssertEqual(MoneroPaymentRequest.decimalString(1), "0.000000000001")
        XCTAssertEqual(MoneroPaymentRequest.decimalString(10_000_000_000), "0.01")
        XCTAssertEqual(MoneroPaymentRequest.decimalString(12_340_000_000_000), "12.34")
    }

    func testInvalidRequestIsRejected() {
        XCTAssertNil(MoneroPaymentRequest.parse("monero:not-a-monero-address?network=stagenet&tx_amount=1"))
    }

    func testMoneroURIIsDetectedAsTappableLinkWithoutDataDetector() {
        let uri = "monero:stagenet-address?network=stagenet&tx_amount=0.01&r=request-id"
        let items = TextCheckingDataItem.detectedItems(in: "Monero payment request\n\(uri)", using: nil)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.url.absoluteString, uri)
    }

    func testSentPaymentNoticeUsesNaturalMessageWithoutNetworkName() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let notice = MoneroAddressExchange.paymentSent(amount: 100_000_000, network: .stagenet, now: now)
        let body = try notice.body()
        let parsed = try XCTUnwrap(MoneroAddressExchange.parse(body, now: now))
        let expectedMessage = String(
            format: MoneroLocalized("Hey, I sent you %@ XMR."),
            "0.0001"
        )

        XCTAssertEqual(parsed.kind, .paymentSent)
        XCTAssertEqual(parsed.amount, 100_000_000)
        XCTAssertNil(parsed.address)
        XCTAssertEqual(MoneroChatPaymentMessage.displayText(for: body), expectedMessage)
        XCTAssertEqual(MoneroChatPaymentMessage.displayText(for: body, isOutgoing: true), expectedMessage)
    }

    func testWalletAddressExchangeControlMessagesAreNotShownInConversation() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let request = MoneroAddressExchange.request(network: .stagenet, now: now)
        let response = request.reply(address: nil)

        XCTAssertEqual(
            MoneroChatPaymentMessage.displayText(for: try request.body(), isOutgoing: true),
            ""
        )
        XCTAssertEqual(
            MoneroChatPaymentMessage.displayText(for: try response.body()),
            ""
        )
    }

    func testPublishedAddressCanBeParsedWithoutARequest() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let address = "42ey1afDFnn4886T7196doS9GPMzexD9gXpsZJDwVjeRVdFCSoHnv7KPbBeGpzJBzHRCAs9UxqeoyFQMYbqSWYTfJJQAWDm"
        let published = MoneroAddressExchange.announcement(address: address, network: .mainnet, now: now)
        let body = try published.body()

        XCTAssertEqual(MoneroAddressExchange.parse(body, now: now)?.address, address)
        XCTAssertEqual(MoneroChatPaymentMessage.displayText(for: body), "")
    }

    func testGeneratedStagenetSubaddressIsValidForStagenet() throws {
        let manager = MONERO_WalletManagerFactory_getWalletManager()
        let walletPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-monero-test-\(UUID().uuidString)")
            .path
        guard let wallet = MONERO_WalletManager_createWallet(manager, walletPath, "test-password", "English", 2) else {
            XCTFail("Could not create temporary Stagenet wallet.")
            return
        }
        defer {
            _ = MONERO_WalletManager_closeWallet(manager, wallet, true)
            try? FileManager.default.removeItem(atPath: walletPath)
            try? FileManager.default.removeItem(atPath: "\(walletPath).keys")
            try? FileManager.default.removeItem(atPath: "\(walletPath).address.txt")
        }

        let before = MONERO_Wallet_numSubaddresses(wallet, 0)
        MONERO_Wallet_addSubaddress(wallet, 0, "request-test")
        let after = MONERO_Wallet_numSubaddresses(wallet, 0)
        XCTAssertGreaterThan(after, before)

        guard let addressPointer = MONERO_Wallet_address(wallet, 0, UInt64(after - 1)) else {
            XCTFail("MoneroCore returned no subaddress.")
            return
        }
        let address = String(cString: addressPointer)
        MONERO_free(UnsafeMutableRawPointer(mutating: addressPointer))

        let primaryAddressPointer = MONERO_Wallet_address(wallet, 0, 0)
        let primaryAddress = String(cString: primaryAddressPointer!)
        MONERO_free(UnsafeMutableRawPointer(mutating: primaryAddressPointer))
        let walletNetwork = MONERO_Wallet_nettype(wallet)
        let validityByNetwork = (0...2).map { MONERO_Wallet_addressValid(address, Int32($0)) }
        XCTAssertTrue(
            MONERO_Wallet_addressValid(address, 2),
            "Generated subaddress rejected: nativeWalletNetwork=\(walletNetwork), validatorByNetwork=\(validityByNetwork), primaryValidForStagenet=\(MONERO_Wallet_addressValid(primaryAddress, 2)), addressLength=\(address.count), primaryLength=\(primaryAddress.count), subaddressCount=\(after)"
        )
        let request = try MoneroPaymentRequest(
            address: address,
            amount: 10_000_000_000,
            network: .stagenet,
            requestID: "test-request"
        )
        XCTAssertEqual(MoneroPaymentRequest.parse(request.uri), request)
        XCTAssertEqual(MoneroPaymentRequest.parse(address, fallbackNetwork: .stagenet)?.address, address)
        let standardURI = "monero:\(address)?tx_amount=0.01"
        XCTAssertEqual(
            MoneroPaymentRequest.parse(standardURI, fallbackNetwork: .stagenet)?.amount,
            10_000_000_000
        )
        XCTAssertNil(MoneroPaymentRequest.parse(address, fallbackNetwork: .mainnet))

        let exchangeTime = Date(timeIntervalSince1970: 1_800_000_000)
        let exchange = MoneroAddressExchange.request(network: .stagenet, now: exchangeTime)
        let response = exchange.reply(address: address)
        let decoded = try XCTUnwrap(MoneroAddressExchange.parse(try response.body(), now: exchangeTime))
        XCTAssertEqual(
            MoneroChatPaymentMessage.displayText(for: try response.body(), isOutgoing: true),
            ""
        )
        XCTAssertTrue(decoded.matches(exchange, threadID: "trusted-thread", expectedThreadID: "trusted-thread", now: exchangeTime))
        XCTAssertFalse(decoded.matches(exchange, threadID: "other-thread", expectedThreadID: "trusted-thread", now: exchangeTime))
        XCTAssertNil(MoneroAddressExchange.parse(
            try response.body(),
            now: exchangeTime.addingTimeInterval(MoneroAddressExchange.lifetime + 1)
        ))
        XCTAssertNotNil(MoneroAddressExchange.parse(
            try response.body(),
            now: exchangeTime.addingTimeInterval(MoneroAddressExchange.lifetime + 1),
            allowExpired: true
        ))
    }

    func testMainnetWalletUsesMainnetAddressEncoding() throws {
        XCTAssertTrue(MoneroWalletService.isMainnetPaymentsEnabled)

        let manager = MONERO_WalletManagerFactory_getWalletManager()
        let walletPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-monero-mainnet-test-\(UUID().uuidString)")
            .path
        guard let wallet = MONERO_WalletManager_createWallet(manager, walletPath, "test-password", "English", 0) else {
            XCTFail("Could not create temporary Mainnet wallet.")
            return
        }
        defer {
            _ = MONERO_WalletManager_closeWallet(manager, wallet, true)
            try? FileManager.default.removeItem(atPath: walletPath)
            try? FileManager.default.removeItem(atPath: "\(walletPath).keys")
            try? FileManager.default.removeItem(atPath: "\(walletPath).address.txt")
        }

        XCTAssertEqual(MONERO_Wallet_nettype(wallet), 0)
        guard let addressPointer = MONERO_Wallet_address(wallet, 0, 0) else {
            XCTFail("MoneroCore returned no Mainnet address.")
            return
        }
        let address = String(cString: addressPointer)
        MONERO_free(UnsafeMutableRawPointer(mutating: addressPointer))

        XCTAssertTrue(MONERO_Wallet_addressValid(address, 0))
        XCTAssertFalse(MONERO_Wallet_addressValid(address, 2), "A Mainnet address must not validate as Stagenet.")
    }

    func testRecoveryPhraseRestoresTheSameMainnetAddress() throws {
        let manager = MONERO_WalletManagerFactory_getWalletManager()
        let originalPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-monero-original-\(UUID().uuidString)").path
        let restoredPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-monero-restored-\(UUID().uuidString)").path
        defer {
            for path in [originalPath, restoredPath] {
                try? FileManager.default.removeItem(atPath: path)
                try? FileManager.default.removeItem(atPath: "\(path).keys")
                try? FileManager.default.removeItem(atPath: "\(path).address.txt")
            }
        }

        let original = try XCTUnwrap(MONERO_WalletManager_createWallet(manager, originalPath, "original-test-password", "English", 0))
        let originalAddress = try XCTUnwrap(MONERO_Wallet_address(original, 0, 0))
        let address = String(cString: originalAddress)
        MONERO_free(UnsafeMutableRawPointer(mutating: originalAddress))
        let seedPointer = try XCTUnwrap(MONERO_Wallet_seed(original, ""))
        let seed = String(cString: seedPointer)
        MONERO_free(UnsafeMutableRawPointer(mutating: seedPointer))
        XCTAssertTrue(MONERO_WalletManager_closeWallet(manager, original, true))

        let restored = try XCTUnwrap(MONERO_WalletManager_recoveryWallet(
            manager, restoredPath, "restored-test-password", seed, 0, 0, 1, ""
        ))
        defer { _ = MONERO_WalletManager_closeWallet(manager, restored, true) }
        let restoredAddress = try XCTUnwrap(MONERO_Wallet_address(restored, 0, 0))
        XCTAssertEqual(String(cString: restoredAddress), address)
        MONERO_free(UnsafeMutableRawPointer(mutating: restoredAddress))
    }
}
