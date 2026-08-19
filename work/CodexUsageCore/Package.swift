// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"])
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .testTarget(name: "CodexUsageCoreTests", dependencies: ["CodexUsageCore"])
    ]
)
