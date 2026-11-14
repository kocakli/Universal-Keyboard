// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "KeyMapper",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "KeyMapper", targets: ["KeyMapper"]),
        .executable(name: "kmctl", targets: ["kmctl"]),
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
        .executableTarget(
            name: "KeyMapper",
            dependencies: ["KeyMapperCore"],
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
    ]
)
