// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OneBoard",
    platforms: [
        .macOS("15.0")
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin", from: "4.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "OneBoard",
            dependencies: ["OneBoardKit"],
            path: ".",
            exclude: ["Tests", "App", "Core", "Modules", "Shared"],
            sources: ["App_minimal"]
        ),
        .target(
            name: "OneBoardKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin"),
            ],
            path: ".",
            exclude: ["Tests", "App_minimal"],
            sources: ["App", "Core", "Modules", "Shared"]
        ),
        .testTarget(
            name: "OneBoardTests",
            dependencies: ["OneBoard"],
            path: "Tests"
        )
    ]
)
