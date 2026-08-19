// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageHUD",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexUsageHUD", targets: ["CodexUsageHUD"])
    ],
    dependencies: [
        .package(path: "../CodexUsageCore")
    ],
    targets: [
        .executableTarget(
            name: "CodexUsageHUD",
            dependencies: [
                .product(name: "CodexUsageCore", package: "CodexUsageCore")
            ]
        )
    ]
)
