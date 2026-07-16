//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import MobileCoin
@testable import Signal
@testable import SignalServiceKit
@testable import SignalUI

class PaymentsTest: SignalBaseTest {
    override func setUp() {
        super.setUp()

        SSKEnvironment.shared.setPaymentsHelperForUnitTests(PaymentsHelperImpl())
        SUIEnvironment.shared.paymentsRef = PaymentsImpl(appReadiness: AppReadinessMock())
    }

    func test_passphraseRoundtrip_randomEntropy() {
        // The property that makes restore-from-phrase work at all: the entropy
        // recovered from the displayed words must equal the entropy that seeded
        // the wallet. Check 16-byte (12-word) and 32-byte (24-word) entropy.
        for entropyLength: UInt in [PaymentsConstants.paymentsEntropyLength, 32] {
            for _ in 0..<100 {
                let paymentsEntropy = Randomness.generateRandomBytes(entropyLength)
                guard let passphrase = SUIEnvironment.shared.paymentsSwiftRef.passphrase(forPaymentsEntropy: paymentsEntropy) else {
                    XCTFail("Missing passphrase.")
                    return
                }
                XCTAssertEqual(paymentsEntropy, SUIEnvironment.shared.paymentsSwiftRef.paymentsEntropy(forPassphrase: passphrase))
            }
        }
    }

    func test_passphraseKnownBip39Vectors() {
        // Standard BIP-39 reference vectors (entropy <-> mnemonic), so the phrase
        // stays interoperable with other BIP-39 wallets.
        let vectors: [(entropyHex: String, mnemonic: String)] = [
            ("00000000000000000000000000000000",
             "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"),
            ("7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
             "legal winner thank year wave sausage worth useful legal winner thank yellow"),
            ("80808080808080808080808080808080",
             "letter advice cage absurd amount doctor acoustic avoid letter advice cage above"),
            ("ffffffffffffffffffffffffffffffff",
             "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong"),
            ("0000000000000000000000000000000000000000000000000000000000000000",
             "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"),
            ("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
             "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"),
        ]
        for vector in vectors {
            let entropy = Data.data(fromHex: vector.entropyHex)!
            let words = vector.mnemonic.split(separator: " ").map { String($0) }
            let passphrase = try! PaymentsPassphrase(words: words)
            XCTAssertEqual(entropy, SUIEnvironment.shared.paymentsSwiftRef.paymentsEntropy(forPassphrase: passphrase))
            XCTAssertEqual(passphrase, SUIEnvironment.shared.paymentsSwiftRef.passphrase(forPaymentsEntropy: entropy))
        }
    }

    func test_passphraseRejectsInvalidChecksum() {
        // 12 x "abandon" encodes all-zero entropy but the wrong checksum
        // (the valid final word is "about") -- a mistyped phrase must not
        // silently restore some other wallet.
        let words = Array(repeating: "abandon", count: 12)
        let passphrase = try! PaymentsPassphrase(words: words)
        XCTAssertNil(SUIEnvironment.shared.paymentsSwiftRef.paymentsEntropy(forPassphrase: passphrase))
    }

    func test_paymentAddressSigning() {
        let identityKeyPair = ECKeyPair.generateKeyPair()
        let publicAddressData = Randomness.generateRandomBytes(256)
        let signatureData = try! TSPaymentAddress.sign(identityKeyPair: identityKeyPair,
                                                       publicAddressData: publicAddressData)
        XCTAssertTrue(TSPaymentAddress.verifySignature(identityKey: identityKeyPair.keyPair.identityKey,
                                                       publicAddressData: publicAddressData,
                                                       signatureData: signatureData))
        let fakeSignatureData = Randomness.generateRandomBytes(UInt(signatureData.count))
        XCTAssertFalse(TSPaymentAddress.verifySignature(identityKey: identityKeyPair.keyPair.identityKey,
                                                        publicAddressData: publicAddressData,
                                                        signatureData: fakeSignatureData))
    }

    func test_isValidPhoneNumberForPayments_remoteConfigBlocklist() {
        XCTAssertTrue(PaymentsHelperImpl.isValidPhoneNumberForPayments_remoteConfigBlocklist("+523456",
                                                                                             paymentsDisabledRegions: ["1", "234"]))
        XCTAssertFalse(PaymentsHelperImpl.isValidPhoneNumberForPayments_remoteConfigBlocklist("+123456",
                                                                                              paymentsDisabledRegions: ["1", "234"]))
        XCTAssertTrue(PaymentsHelperImpl.isValidPhoneNumberForPayments_remoteConfigBlocklist("+233333333",
                                                                                             paymentsDisabledRegions: ["1", "234"]))
        XCTAssertFalse(PaymentsHelperImpl.isValidPhoneNumberForPayments_remoteConfigBlocklist("+234333333",
                                                                                              paymentsDisabledRegions: ["1", "234"]))
    }
}
