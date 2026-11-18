//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Security

/// A simplified version of AFNetworking's AFSecurityPolicy.
public struct HttpSecurityPolicy {

    private static let defaultRejectedSPKI: Set<Data> = Set([
        "EBED6475C2C2D80FCB199F3FE8DD6E6B3CE60B77EB15D4E42C3DEC0C6F5B5105",
        "43BFFA19D6EF651451F6841E019931E96F6F2EAEFF28AB4B6F1CE4576DE2717B",
        "E0254C7FCDC265E2F0F8A428DABB75AB4AE039B4872D62F5EE57F0877D5A8A41",
        "49DD353DC2B919A3770645117D0E60C16115E7D1BC259EEFE734B00EA434FE5F",
        "63ECEFEE431D49523BC1136C4E72D0206A477086CAF606CD5CF025686C109CF8",
        "5C0660A2B164910D8FF589C18E14552E9E0EC237DCEFE2CB736D41A4811F81A0",
        "EC4FFA1AD0AC88081314B7AAFFEF6A91F97CD57291BB5BA686C5415F5EB4F6B6",
        "92C063D67E8F14DB71D288E11266FFDAF69CBF115F7BAB14F3BC2F68D25E0E30",
    ].compactMap { Data(hex: $0) })

    public static let signalCaPinned: HttpSecurityPolicy = .init(pinnedCertificates: [Certificates.load("signal-messenger", extension: "cer")])
    public static let systemDefault: HttpSecurityPolicy = .init()

    private let pinnedCertificates: [SecCertificate]?

    /// SHA-256 digests of SubjectPublicKeyInfos that must not appear anywhere in a
    /// certificate chain. Defaults to `defaultRejectedSPKI`; pass an explicit list
    /// to override it, or an empty one to reject nothing.
    private let rejectedSPKI: Set<Data>

    public init(
        pinnedCertificates: [SecCertificate]? = nil,
        rejectedSPKI: [Data]? = nil,
    ) {
        self.pinnedCertificates = pinnedCertificates
        self.rejectedSPKI = rejectedSPKI.map(Set.init) ?? Self.defaultRejectedSPKI
    }

    public func evaluate(serverTrust: SecTrust, domain: String?) -> Bool {
        let policies = [SecPolicyCreateSSL(true, domain as CFString?)]

        guard SecTrustSetPolicies(serverTrust, policies as CFArray) == errSecSuccess else {
            Logger.error("the trust policy could not be set")
            return false
        }

        // use the default anchors if none were prvided in pinnedCertificates
        if let pinnedCertificates, !pinnedCertificates.isEmpty {
            guard SecTrustSetAnchorCertificates(serverTrust, pinnedCertificates as CFArray) == errSecSuccess else {
                Logger.error("the anchor certificates could not be set")
                return false
            }
        }

        guard Self.isValid(serverTrust: serverTrust) else {
            return false
        }

        guard !containsRejectedCertificate(serverTrust: serverTrust) else {
            return false
        }

        return true
    }

    private static func isValid(serverTrust: SecTrust) -> Bool {
        guard SecTrustEvaluateWithError(serverTrust, nil) else {
            return false
        }
        var result: SecTrustResultType = .otherError // initialize to a value that would fail if SecTrustGetTrustResult doesn't overwrite it
        guard SecTrustGetTrustResult(serverTrust, &result) == errSecSuccess else {
            return false
        }
        return result == .unspecified || result == .proceed
    }

    private func containsRejectedCertificate(serverTrust: SecTrust) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            // Fail closed if we can't get a certificate chain from the server trust
            return true
        }
        return chain.contains { cert in
            guard let spki = Self.subjectPublicKeyInfo(of: cert) else { return true }
            let spkiDigest = Data(SHA256.hash(data: spki))
            return rejectedSPKI.contains(spkiDigest)
        }
    }

    /// The DER-encoded SubjectPublicKeyInfo of a certificate, copied verbatim out
    /// of the certificate's own encoding.
    ///
    /// Returns `nil` if the certificate can't be parsed; callers using this for a
    /// security decision must treat that as a failure rather than as a pass.
    ///
    /// No Security framework call hands back a SubjectPublicKeyInfo directly, but RFC-conforming certificates are
    /// well-structured, and  the 'subjectPublicKeyInfo' can be extracted verbatim from a field in the certificate.
    ///
    /// Certificate / TBSCertificate are defined [here](https://www.rfc-editor.org/info/rfc5280/#section-4.1)
    static func subjectPublicKeyInfo(of certificate: SecCertificate) -> Data? {
        let data = SecCertificateCopyData(certificate) as Data

        // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
        var topLevel = DERScanner(data: data)
        guard
            let certificateSequence = topLevel.read(),
            certificateSequence.tag == DERScanner.sequenceTag
        else { return nil }

        var certificateFields = DERScanner(data: data, range: certificateSequence.contentRange)
        guard
            let tbsCertificate = certificateFields.read(),
            tbsCertificate.tag == DERScanner.sequenceTag
        else { return nil }

        // TBSCertificate ::= SEQUENCE {
        //     version              [0] EXPLICIT Version DEFAULT v1,
        //     serialNumber         CertificateSerialNumber,
        //     signature            AlgorithmIdentifier,
        //     issuer               Name,
        //     validity             Validity,
        //     subject              Name,
        //     subjectPublicKeyInfo SubjectPublicKeyInfo,
        //     ... }
        var tbsFields = DERScanner(data: data, range: tbsCertificate.contentRange)
        guard let firstField = tbsFields.read() else { return nil }
        if firstField.tag == DERScanner.explicitTag0 {
            // The version is optional and omitted from v1 certificates. When it is
            // present, the serial number is the element after it.
            guard tbsFields.skip(1) else { return nil }
        }
        // Skip the signature, issuer, validity and subject to reach the key.
        guard tbsFields.skip(4) else { return nil }

        guard
            let subjectPublicKeyInfo = tbsFields.read(),
            subjectPublicKeyInfo.tag == DERScanner.sequenceTag
        else { return nil }

        return Data(data[subjectPublicKeyInfo.elementRange])
    }

    // MARK: -

    /// A minimal DER reader. It walks tag-length-value elements without interpreting their contents.
    /// Each DER scanner reads a 'level' of the DER tree.  The data range returned by the `read()`
    /// method can then be fed to another DERScanner instance to parse the next level of the tree.
    struct DERScanner {

        /// The tag of a SEQUENCE.
        static let sequenceTag: UInt8 = 0x30
        /// The tag of a constructed, context-specific `[0]` element.
        static let explicitTag0: UInt8 = 0xA0

        struct Element {
            let tag: UInt8
            /// The whole element, header and contents together.
            let elementRange: Range<Int>
            /// The contents of the element, without its header.
            let contentRange: Range<Int>
        }

        private let data: Data
        private let end: Int
        private var index: Int

        init(data: Data) {
            self.init(data: data, range: 0..<data.count)
        }

        init(data: Data, range: Range<Int>) {
            self.data = data
            self.end = range.upperBound
            self.index = range.lowerBound
        }

        /// Reads the element at the current position and advances past it, returning
        /// `nil` if the remaining bytes aren't a well-formed element.
        mutating func read() -> Element? {
            let start = index
            // Every element has at least a tag byte and a length byte.
            guard index + 2 <= end else { return nil }

            let tag = data[index]
            index += 1

            let firstLengthByte = data[index]
            index += 1

            var length = 0
            if firstLengthByte & 0x80 == 0 {
                // 0x80 signifies the a multi byte length value, 0x7F or lower represents a single-byte length
                length = Int(firstLengthByte)
            } else {
                // The low 7 bits hold the number of bytes the length itself occupies. A
                // count of zero is the indefinite form, which DER doesn't permit, and
                // nothing in a certificate needs more than four bytes of length.
                // see: https://en.wikipedia.org/wiki/X.690#DER_encoding
                let lengthByteCount = Int(firstLengthByte & 0x7F)
                guard lengthByteCount > 0, lengthByteCount <= 4, index + lengthByteCount <= end else {
                    return nil
                }
                for _ in 0..<lengthByteCount {
                    length = (length << 8) | Int(data[index])
                    index += 1
                }
            }

            let contentsStart = index
            guard contentsStart + length <= end else { return nil }
            index = contentsStart + length

            return Element(tag: tag, elementRange: start..<index, contentRange: contentsStart..<index)
        }

        /// Reads and discards `count` elements, failing if any of them is malformed.
        mutating func skip(_ count: Int) -> Bool {
            for _ in 0..<count {
                guard read() != nil else { return false }
            }
            return true
        }
    }
}
