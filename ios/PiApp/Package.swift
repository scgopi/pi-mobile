// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PiApp",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PiApp", targets: ["PiApp"]),
    ],
    dependencies: [
        .package(path: "../PiAI"),
        .package(path: "../PiAgentCore"),
        .package(path: "../PiTools"),
        .package(path: "../PiSession"),
        .package(path: "../PiExtensions"),
    ],
    targets: [
        .target(
            name: "PiApp",
            dependencies: ["PiAI", "PiAgentCore", "PiTools", "PiSession", "PiExtensions"],
            path: "PiApp"
        ),
        .testTarget(name: "PiAppTests", dependencies: ["PiApp"], path: "PiAppTests"),
    ]
)
