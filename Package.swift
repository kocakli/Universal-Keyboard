// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KeyMapper",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "KeyMapper", targets: ["KeyMapper"]),
        .executable(name: "kmctl", targets: ["kmctl"]),
        .executable(name: "keymapper-usage", targets: ["keymapper-usage"]),
        .library(name: "KeyMapperCore", targets: ["KeyMapperCore"]),
    ],
    targets: [
        .target(
            name: "KeyMapperCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedLibrary("compression"),
            ]
        ),
        // AI tool quotas (Claude, Codex, Cursor). Credentials are only read inside the keymapper-usage helper.
        .target(
            name: "KeyMapperUsage",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "keymapper-usage",
            dependencies: ["KeyMapperUsage"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "KeyMapper",
            dependencies: ["KeyMapperCore", "KeyMapperUsage"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "kmctl",
            dependencies: ["KeyMapperCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KeyMapperCoreTests",
            dependencies: ["KeyMapperCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KeyMapperUsageTests",
            dependencies: ["KeyMapperUsage"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
