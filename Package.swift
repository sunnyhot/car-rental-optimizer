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
    targets: [
        .executableTarget(
            name: "CarRentalOptimizer",
            path: "Sources/CarRentalOptimizer"
        ),
        .testTarget(
            name: "CarRentalOptimizerTests",
            dependencies: ["CarRentalOptimizer"],
            path: "Tests/CarRentalOptimizerTests"
        )
    ]
)
