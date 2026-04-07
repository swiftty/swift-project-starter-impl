// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-project-starter",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "swift-project-starter", targets: ["swift-project-starter"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.4.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "603.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "swift-project-starter",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "Logging", package: "swift-log"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
