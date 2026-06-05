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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CarRentalOptimizer",
            dependencies: [
                "CarRentalDomain",
            ],
            path: "Sources/CarRentalOptimizer",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker",
                    "-sectcreate",
                    "-Xlinker",
                    "__TEXT",
                    "-Xlinker",
                    "__info_plist",
                    "-Xlinker",
                    "native/Info.plist",
                ])
            ]
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
