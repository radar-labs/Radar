public import BreezSdkSpark
import CryptoKit
import SignalServiceKit

extension BreezSdk {
    enum Constants {
        static let defaultBreezDirectoryName = "breez"
    }

    public static func build(with entropy: Data) async throws -> BreezSdk {
        let config = breezSdkConfig
        let seed = Seed.entropy(entropy)
        let fileManager = FileManager.default
        let documentsDirectory = try fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let breezDirectory = documentsDirectory.appendingPathComponent(
            Constants.defaultBreezDirectoryName,
            isDirectory: true
        )

        if !fileManager.fileExists(atPath: breezDirectory.path) {
            try fileManager.createDirectory(
                atPath: breezDirectory.path, withIntermediateDirectories: true)
        }

        let builder = SdkBuilder(config: config, seed: seed)
        await builder.withDefaultStorage(storageDir: breezDirectory.path)
        let keySetConfig = KeySetConfig(
            keySetType: .nativeSegwit,
            useAddressIndex: true,
            accountNumber: nil
        )
        await builder.withKeySet(config: keySetConfig)

        return try await builder.build()
    }

    public func validateInitialLightningAddress() async throws {
        let lightningAddress = try await getLightningAddress()

        if let lightningAddress = lightningAddress {
            if let lnurlDomain = breezSdkConfig.lnurlDomain,
                !lightningAddress.lightningAddress.contains("@\(lnurlDomain)")
            {
                await self.tryToRegisterLightningAddress()
            }
        } else {
            await self.tryToRegisterLightningAddress()
        }
    }

    private static func generateUsername(withAci aci: String, prefixLength: Int = 10) throws -> String {
        guard let aciData = aci.data(using: .utf8) else {
            throw OWSAssertionError("Cannot get UTF-8 encoded data from ACI")
        }

        let hash = SHA256.hash(data: aciData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return String(hashString.prefix(prefixLength))
    }

    private static func generateUsername(length: Int = 16) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            owsFailDebug("Failed to generate secure random bytes")
            return ""
        }

        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func tryToRegisterLightningAddress(rateLimit: Int = 5) async {
         for _ in 0...rateLimit {
             do {
                 let username = Self.generateUsername()
                 let isAvailable = try await checkLightningAddressAvailable(
                         req: CheckLightningAddressRequest(username: username))

                 if isAvailable {
                     _ = try await registerLightningAddress(
                             request: RegisterLightningAddressRequest(username: username))
                     return
                 }
             } catch {
                 owsFailDebug("Cannot to register lightning address. Error: \(error)")
             }
         }

        owsFailDebug("Cannot to register lightning address. Out of rate limit: \(rateLimit)")
    }
}
