// swift-tools-version: 6.2
// Blabla — on-device speech transcription as a macOS Menu Bar app.
// Transcription engine based on https://github.com/finnvoor/yap by Finn Voorhees.

import PackageDescription

let package = Package(
    name: "Blabla",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Blabla", targets: ["Blabla"]),
    ],
    targets: [
        .executableTarget(
            name: "Blabla",
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
        .testTarget(
            name: "BlablaTests",
            dependencies: ["Blabla"],
            path: "Tests/BlablaTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
