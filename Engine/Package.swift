// swift-tools-version: 6.0
import PackageDescription

// Engine/ is a library package that must never contain character data. No .png,
// no .wav, no character-named identifier. See CLAUDE.md sections 1 and 3 - the
// package boundary is what makes Rule 1 structural rather than a convention.
let package = Package(
    name: "LodgerEngine",
    platforms: [.macOS(.v14)],   // NSView.displayLink(target:selector:) needs 14.0
    products: [
        .library(name: "LodgerEngine", targets: ["LodgerEngine"]),
        .executable(name: "lodger", targets: ["lodger"]),
        .executable(name: "lodger-selftest", targets: ["lodger-selftest"]),
    ],
    targets: [
        .target(name: "LodgerEngine", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "lodger", dependencies: ["LodgerEngine"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        // Command Line Tools ships neither XCTest nor swift-testing, so the suite
        // is a plain executable. It also means CI needs no Xcode.
        .executableTarget(name: "lodger-selftest", dependencies: ["LodgerEngine"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
