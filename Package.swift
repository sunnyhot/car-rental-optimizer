// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CarRentalOptimizer",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CarRentalDomain", targets: ["CarRentalDomain"]),
    ],
    targets: [
        .target(name: "CarRentalDomain", path: "Sources/CarRentalDomain"),
        .testTarget(name: "CarRentalDomainTests", dependencies: ["CarRentalDomain"], path: "Tests/CarRentalDomainTests"),
    ]
)
