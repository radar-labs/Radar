// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoneroCore",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "MoneroCore", targets: ["CMonero"])
    ],
    targets: [
        .target(
            name: "CMonero",
            dependencies: ["MoneroBinary"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .define("BOOST_ERROR_CODE_HEADER_ONLY")
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .binaryTarget(
            name: "MoneroBinary",
            url: "https://github.com/horizontalsystems/MoneroKit.Swift/releases/download/frameworks-4/MoneroZano.xcframework.zip",
            checksum: "07f27198593b33d05cff9bf119e7666ebcee141d6e68514af0ab9b080d06eab7"
        )
    ],
    cxxLanguageStandard: .cxx11
)
