// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OneBoard",
    platforms: [
        .macOS("15.0")
    ],
    dependencies: [
        .package(url: "https://github.com/6tail/lunar-swift.git", revision: "a7ec0e9b29f84a5d98b09b9ffd31145f17470d56"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin", from: "4.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "OneBoard",
            dependencies: ["OneBoardKit"],
            path: ".",
            exclude: ["Tests", "App", "Core", "Modules", "Shared", "FinderSync", "Resources"],
            sources: ["App_minimal"]
        ),
        .target(
            name: "OneBoardKit",
            dependencies: [
                .product(name: "LunarSwift", package: "lunar-swift"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin"),
            ],
            path: ".",
            exclude: ["Tests", "App_minimal", "FinderSync", "Resources"],
            sources: ["App", "Core", "Modules", "Shared"],
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security"),
                .linkedFramework("CloudKit"),
            ]
        ),
        .testTarget(
            name: "OneBoardTests",
            dependencies: ["OneBoardKit"],
            path: "Tests"
        )
    ]
)
