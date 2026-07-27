// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalAnonymizer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "LocalAnonymizer",
            targets: ["LocalAnonymizer"]
        )
    ],
    targets: [
        .target(
            name: "AnonymizerCore"
        ),
        .executableTarget(
            name: "LocalAnonymizer",
            dependencies: ["AnonymizerCore"]
        ),
        .executableTarget(
            name: "LocalAnonymizerSelfTest",
            dependencies: ["AnonymizerCore"],
            path: "Tests/LocalAnonymizerSelfTest"
        )
    ]
)
