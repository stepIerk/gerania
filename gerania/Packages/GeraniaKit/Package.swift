// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GeraniaKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "GeraniaKit",
            targets: ["GeraniaCore", "HermesKit", "VoiceKit", "RealtimeKit", "GeraniaUI"]
        ),
        .executable(name: "gerania-cli", targets: ["gerania-cli"]),
        .executable(name: "live-probe", targets: ["live-probe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/textual.git", from: "0.5.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "GeraniaCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "HermesKit",
            dependencies: ["GeraniaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "VoiceKit",
            dependencies: ["GeraniaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "RealtimeKit",
            dependencies: ["GeraniaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "GeraniaUI",
            dependencies: [
                "GeraniaCore",
                "HermesKit",
                "VoiceKit",
                "RealtimeKit",
                .product(name: "Textual", package: "textual"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "gerania-cli",
            dependencies: ["GeraniaCore", "HermesKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "live-probe",
            dependencies: ["GeraniaCore", "RealtimeKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GeraniaCoreTests",
            dependencies: ["GeraniaCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "HermesKitTests",
            dependencies: ["HermesKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VoiceKitTests",
            dependencies: ["VoiceKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RealtimeKitTests",
            dependencies: ["RealtimeKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GeraniaUITests",
            dependencies: ["GeraniaUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
