// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CarRentalOptimizer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CarRentalOptimizer",
            targets: ["CarRentalOptimizer"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.4.0")
    ],
    targets: [
        .executableTarget(
            name: "CarRentalOptimizer",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/CarRentalOptimizer"
        ),
        .testTarget(
            name: "CarRentalOptimizerTests",
            dependencies: ["CarRentalOptimizer"],
            path: "Tests/CarRentalOptimizerTests"
        )
    ]
)
