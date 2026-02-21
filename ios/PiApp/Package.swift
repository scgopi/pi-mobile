// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PiApp",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PiApp", targets: ["PiApp"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .target(
            name: "PiApp",
            dependencies: [
                .product(name: "PiAI", package: "PiMobile"),
                .product(name: "PiAgentCore", package: "PiMobile"),
                .product(name: "PiTools", package: "PiMobile"),
                .product(name: "PiSession", package: "PiMobile"),
                .product(name: "PiExtensions", package: "PiMobile"),
            ],
            path: "PiApp"
        ),
        .testTarget(name: "PiAppTests", dependencies: ["PiApp"], path: "PiAppTests"),
    ]
)
