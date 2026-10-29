// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Cloud",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "tunnel", targets: ["tunnel"]),
        .executable(name: "CloudBar", targets: ["CloudBar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
    ],
    targets: [
        .target(name: "CloudCore", dependencies: ["Yams"]),
        .executableTarget(
            name: "tunnel",
            dependencies: ["CloudCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .executableTarget(name: "CloudBar", dependencies: ["CloudCore"]),
        .testTarget(
            name: "CloudCoreTests",
            dependencies: ["CloudCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
