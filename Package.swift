// swift-tools-version: 6.2
// YapMenuBar — on-device speech transcription as a macOS Menu Bar app
//
// Core transcription files (TranscriptionEngine, OutputFormat, AttributedString+Extensions)
// are pulled DIRECTLY from the yap git submodule (https://github.com/finnvoor/yap).
// The `Sources/YapMenuBar/YapSources/` directory contains symlinks that resolve to
// the live submodule files — no copying, no forking.
//
// Workflow:
//   git submodule update --init --recursive   # first-time setup
//   git submodule update --remote yap         # pull latest yap changes

import PackageDescription

let package = Package(
    name: "YapMenuBar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "YapMenuBar", targets: ["YapMenuBar"]),
    ],
    dependencies: [
        // Required because yap/Sources/yap/OutputFormat.swift conforms to
        // ArgumentParser.EnumerableFlag. We include that file via symlink so
        // we compile it as-is without forking the repo.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        // ── YapMenuBar ─────────────────────────────────────────────────────────
        // Single target: our SwiftUI app + yap core (via symlinks in YapSources/).
        // All yap types stay `internal`, which is perfect for an app target.
        .executableTarget(
            name: "YapMenuBar",
            dependencies: [
                // OutputFormat.swift (from yap, via symlink) conforms to EnumerableFlag
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/YapMenuBar",
            exclude: [
                "Resources/Info.plist",
                "Resources/YapMenuBar.entitlements",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
    ]
)
