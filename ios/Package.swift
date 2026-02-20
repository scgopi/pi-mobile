// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PiMobile",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PiAI", targets: ["PiAI"]),
        .library(name: "PiAgentCore", targets: ["PiAgentCore"]),
        .library(name: "PiTools", targets: ["PiTools"]),
        .library(name: "PiSession", targets: ["PiSession"]),
        .library(name: "PiExtensions", targets: ["PiExtensions"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0"),
    ],
    targets: [
        .target(name: "PiAI", path: "PiAI/Sources/PiAI"),
        .target(name: "PiAgentCore", dependencies: ["PiAI"], path: "PiAgentCore/Sources/PiAgentCore"),
        .target(name: "PiTools", dependencies: ["PiAgentCore"], path: "PiTools/Sources/PiTools"),
        .target(
            name: "PiSession",
            dependencies: [
                "PiAI",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "PiSession/Sources/PiSession"
        ),
        .target(name: "PiExtensions", dependencies: ["PiAgentCore"], path: "PiExtensions/Sources/PiExtensions"),

        .testTarget(name: "PiAITests", dependencies: ["PiAI"], path: "PiAI/Tests/PiAITests"),
        .testTarget(name: "PiAgentCoreTests", dependencies: ["PiAgentCore", "PiAI"], path: "PiAgentCore/Tests/PiAgentCoreTests"),
        .testTarget(name: "PiToolsTests", dependencies: ["PiTools", "PiAgentCore", "PiAI"], path: "PiTools/Tests/PiToolsTests"),
        .testTarget(
            name: "PiSessionTests",
            dependencies: [
                "PiSession",
                "PiAI",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "PiSession/Tests/PiSessionTests"
        ),
        .testTarget(name: "PiExtensionsTests", dependencies: ["PiExtensions", "PiAgentCore", "PiAI"], path: "PiExtensions/Tests/PiExtensionsTests"),
    ]
)
