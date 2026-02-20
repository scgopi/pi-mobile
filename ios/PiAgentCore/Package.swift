// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PiAgentCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PiAgentCore", targets: ["PiAgentCore"]),
    ],
    dependencies: [
        .package(path: "../PiAI"),
    ],
    targets: [
        .target(name: "PiAgentCore", dependencies: ["PiAI"], path: "Sources/PiAgentCore"),
    ]
)
