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
        // TODO: commented out as it changes the wallet, until we have clarity from breez
//        let keySetConfig = KeySetConfig(
//            keySetType: .nativeSegwit,
//            useAddressIndex: true,
//            accountNumber: nil
//        )
//        await builder.withKeySet(config: keySetConfig)

        return try await builder.build()
    }

    public func validateInitialLightningAddress() async throws -> LightningAddressInfo? {
        let lightningAddress = try await getLightningAddress()

        if let lightningAddress = lightningAddress {
            if let lnurlDomain = breezSdkConfig.lnurlDomain,
                !lightningAddress.lightningAddress.contains("@\(lnurlDomain)")
            {
                return await self.tryToRegisterLightningAddress()
            }
            return nil
        } else {
            return await self.tryToRegisterLightningAddress()
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

    private static let usernameWords: [String] = [
        "amber", "arctic", "azure", "beacon", "birch", "blast", "blaze", "bloom",
        "bolt", "bravo", "breeze", "bright", "brisk", "bronze", "brook", "burst",
        "calm", "cedar", "chain", "chase", "chief", "chill", "cipher", "citrus",
        "clover", "coast", "cobalt", "comet", "coral", "craft", "crest", "crisp",
        "crown", "crush", "crystal", "cyber", "delta", "dense", "depot", "depth",
        "drift", "dusk", "echo", "ember", "falcon", "fern", "finch", "flame",
        "flash", "fleet", "flint", "float", "flux", "forge", "forte", "frost",
        "gale", "ghost", "glade", "gleam", "glide", "glow", "grand", "grant",
        "gust", "haven", "hawk", "hazel", "haze", "helix", "helm", "hive",
        "indie", "inlet", "iris", "ivory", "jade", "jasper", "jetty", "kindle",
        "kite", "lance", "lark", "laser", "latch", "lava", "layer", "leap",
        "ledge", "light", "lotus", "lunar", "lynx", "maple", "marble", "marsh",
        "mist", "mosaic", "moss", "mural", "nova", "oaken", "ocean", "onyx",
        "orbit", "otter", "oxide", "ozone", "pact", "peak", "pearl", "petal",
        "pilot", "pine", "pivot", "pixel", "plaza", "plume", "polar", "pulse",
        "quartz", "quest", "radar", "rapid", "raven", "realm", "relay", "ridge",
        "ripple", "river", "roam", "rogue", "rover", "ruby", "rush", "sage",
        "scout", "serene", "shade", "shift", "shore", "signal", "silver", "slate",
        "solar", "sonic", "spark", "spire", "split", "sprint", "stark", "steel",
        "storm", "strata", "streak", "stream", "stride", "swift", "talon", "teal",
        "terra", "thunder", "tide", "timber", "titan", "torch", "trail", "trend",
        "tropic", "turbo", "ultra", "unity", "vapor", "vault", "vector", "verde",
        "vibe", "vista", "vital", "vivid", "volt", "wave", "wisp", "zenith"
    ]

    private static func generateUsername() -> String {
        var bytes = [UInt8](repeating: 0, count: 6)
        guard SecRandomCopyBytes(kSecRandomDefault, 6, &bytes) == errSecSuccess else {
            owsFailDebug("Failed to generate secure random bytes")
            return ""
        }
        let index1 = (Int(bytes[0]) << 8 | Int(bytes[1])) % usernameWords.count
        let index2 = (Int(bytes[2]) << 8 | Int(bytes[3])) % usernameWords.count
        let number = (Int(bytes[4]) << 8 | Int(bytes[5])) % 10000
        return "\(usernameWords[index1])\(usernameWords[index2])\(String(format: "%04d", number))"
    }

    private func tryToRegisterLightningAddress(rateLimit: Int = 5) async -> LightningAddressInfo? {
        for _ in 0...rateLimit {
            do {
                let username = Self.generateUsername()
                let isAvailable = try await checkLightningAddressAvailable(
                    req: CheckLightningAddressRequest(username: username))
                if isAvailable {
                    return try await registerLightningAddress(
                        request: RegisterLightningAddressRequest(username: username))
                }
            } catch {
                Logger.warn("Cannot register lightning address. Error: \(error)")
            }
        }
        Logger.warn("Cannot register lightning address. Out of rate limit: \(rateLimit)")
        return nil
    }
}
