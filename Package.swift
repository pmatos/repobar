// swift-tools-version: 6.2
import PackageDescription

#if os(macOS) || os(iOS)
let buildAppleUI = true
#else
let buildAppleUI = false
#endif

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/steipete/Commander", from: "0.2.0"),
    .package(url: "https://github.com/apple/swift-crypto", from: "3.13.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.8.0"),
    .package(url: "https://github.com/pmatos/Swiftdansi", branch: "linux-isatty"),
    .package(url: "https://github.com/apple/swift-markdown", from: "0.7.3"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
]

// macOS-only deps. `apollo-ios` does not build on Linux (URLRequest /
// FoundationNetworking + Sendable issues with HTTPURLResponse). The remaining
// packages are tied to AppKit / SwiftUI. RepoBarCore's runtime currently uses
// none of them — Apollo was kept for codegen tooling only — so dropping them
// from the Linux build leaves no broken imports.
if buildAppleUI {
    dependencies += [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.1"),
        .package(url: "https://github.com/openid/AppAuth-iOS", from: "2.0.0"),
        .package(url: "https://github.com/apollographql/apollo-ios", from: "2.0.3"),
        .package(url: "https://github.com/onevcat/Kingfisher", from: "8.6.0"),
    ]
}

var targets: [Target] = [
    .systemLibrary(
        name: "CZlib",
        pkgConfig: "zlib",
        providers: [
            .apt(["zlib1g-dev"]),
            .brew(["zlib"]),
        ]),
    .target(
        name: "RepoBarCore",
        dependencies: [
            "CZlib",
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "_CryptoExtras", package: "swift-crypto"),
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "Logging", package: "swift-log"),
            .product(name: "Markdown", package: "swift-markdown"),
        ],
        swiftSettings: [
            .enableUpcomingFeature("StrictConcurrency"),
        ]),
    .testTarget(
        name: "RepoBarCoreTests",
        dependencies: ["RepoBarCore"],
        resources: [
            .copy("Fixtures"),
        ],
        swiftSettings: [
            .enableUpcomingFeature("StrictConcurrency"),
            .enableExperimentalFeature("SwiftTesting"),
        ]),
    .executableTarget(
        name: "repobarcli",
        dependencies: [
            .product(name: "Commander", package: "Commander"),
            .product(name: "Swiftdansi", package: "Swiftdansi"),
            "RepoBarCore",
        ],
        path: "Sources/repobarcli",
        swiftSettings: [
            .enableUpcomingFeature("StrictConcurrency"),
        ]),
    .testTarget(
        name: "repobarcliTests",
        dependencies: ["repobarcli"],
        path: "Tests/repobarcliTests",
        resources: [
            .process("Fixtures"),
        ],
        swiftSettings: [
            .enableUpcomingFeature("StrictConcurrency"),
            .enableExperimentalFeature("SwiftTesting"),
        ]),
]

if buildAppleUI {
    targets += [
        .executableTarget(
            name: "RepoBar",
            dependencies: [
                "RepoBarCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "AppAuth", package: "AppAuth-iOS"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "Logging", package: "swift-log"),
            ],
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/RepoBar/Resources/Info.plist",
                ]),
                ]),
        .testTarget(
            name: "RepoBarTests",
            dependencies: ["RepoBar", "RepoBarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("SwiftTesting"),
            ]),
    ]
}

var products: [Product] = [
    .library(name: "RepoBarCore", targets: ["RepoBarCore"]),
    // Named to avoid colliding with `RepoBar` on case-insensitive filesystems.
    .executable(name: "repobarcli", targets: ["repobarcli"]),
]

let package = Package(
    name: "RepoBar",
    platforms: [
        .macOS(.v15),
        .iOS(.v26),
    ],
    products: products,
    dependencies: dependencies,
    targets: targets)
