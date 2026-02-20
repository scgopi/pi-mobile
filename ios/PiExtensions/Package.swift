// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PiExtensions",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PiExtensions", targets: ["PiExtensions"]),
    ],
    dependencies: [
        .package(path: "../PiAgentCore"),
    ],
    targets: [
        .target(name: "PiExtensions", dependencies: ["PiAgentCore"], path: "Sources/PiExtensions"),
    ]
)
