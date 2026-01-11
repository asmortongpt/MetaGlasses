// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetaGlassesCamera",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "MetaGlassesCamera",
            targets: ["MetaGlassesCamera"])
    ],
    dependencies: [
        // Meta Wearables Device Access Toolkit
        // Commented out for simulator testing - uses mock implementation
        .package(url: "https://github.com/facebook/meta-wearables-dat-ios.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "MetaGlassesCamera",
            dependencies: [
                // Commented out for simulator testing - uses mock implementation
                // .product(name: "MetaWearablesDAT", package: "meta-wearables-dat-ios")
            ]
        ),
        .testTarget(
            name: "MetaGlassesCameraTests",
            dependencies: ["MetaGlassesCamera"]
        )
    ]
)
