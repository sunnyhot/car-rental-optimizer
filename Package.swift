// swift-tools-version: 5.9

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
        ),
        .library(name: "CarRentalDomain", targets: ["CarRentalDomain"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.4.0")
    ],
    targets: [
        .executableTarget(
            name: "CarRentalOptimizer",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                "CarRentalDomain",
            ],
            path: "Sources/CarRentalOptimizer"
        ),
        .target(name: "CarRentalDomain", path: "Sources/CarRentalDomain"),
        .testTarget(
            name: "CarRentalOptimizerTests",
            dependencies: ["CarRentalOptimizer"],
            path: "Tests/CarRentalOptimizerTests"
        ),
        .testTarget(name: "CarRentalDomainTests", dependencies: ["CarRentalDomain"], path: "Tests/CarRentalDomainTests"),
    ]
)
