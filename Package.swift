// swift-tools-version: 6.2
// Blabla — on-device speech transcription as a macOS Menu Bar app
//
// Core transcription files (TranscriptionEngine, OutputFormat, AttributedString+Extensions)
// are pulled DIRECTLY from the yap git submodule (https://github.com/finnvoor/yap).
// The `Sources/Blabla/YapSources/` directory contains symlinks that resolve to
// the live submodule files — no copying, no forking.
//
// Workflow:
//   git submodule update --init --recursive   # first-time setup
//   git submodule update --remote yap         # pull latest yap changes

import PackageDescription

let package = Package(
    name: "Blabla",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Blabla", targets: ["Blabla"]),
    ],
    dependencies: [
        // Required because yap/Sources/yap/OutputFormat.swift conforms to
        // ArgumentParser.EnumerableFlag. We include that file via symlink so
        // we compile it as-is without forking the repo.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Blabla",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/Blabla",
            exclude: [
                "Resources/Info.plist",
                "Resources/Blabla.entitlements",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .process("Resources/en.lproj"),
                .process("Resources/de.lproj"),
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
