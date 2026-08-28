// swift-tools-version: 6.0
import PackageDescription

/// Shared 3MF package reading and preview extraction.
///
/// This used to be a directory of sources that the app project compiled by relative path, which
/// meant the two Xcode projects had to stay siblings on disk, the same files were compiled into
/// three separate binaries as unrelated module types, and each project pinned ZIPFoundation
/// independently. As a package it is one versioned dependency with one pin.
let package = Package(
    name: "ThreeMFKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ThreeMFKit", targets: ["ThreeMFKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "ThreeMFKit",
            dependencies: ["ZIPFoundation"],
            swiftSettings: [
                // Consumed by Quick Look app extensions, so it must stay within the
                // extension-safe API surface.
                .unsafeFlags(["-application-extension"])
            ]
        ),
        .testTarget(
            name: "ThreeMFKitTests",
            dependencies: ["ThreeMFKit", "ZIPFoundation"]
        )
    ]
)
