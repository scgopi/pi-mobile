// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PiTools",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PiTools", targets: ["PiTools"]),
    ],
    dependencies: [
        .package(path: "../PiAgentCore"),
    ],
    targets: [
        .target(name: "PiTools", dependencies: ["PiAgentCore"], path: "Sources/PiTools"),
    ]
)
