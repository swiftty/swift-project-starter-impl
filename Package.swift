// swift-tools-version: 6.2.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-project-starter",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "swift-project-starter", targets: ["swift-project-starter"]),
        .plugin(name: "swift-project-starter-plugin", targets: ["swift-project-starter-plugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "603.0.1"),
        .package(url: "https://github.com/apple/swift-system", from: "1.6.4"),
        .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
        // AUTO GENERATED ↓: swift-project-starter: deps
        .package(url: "https://github.com/swiftty/swift-format-plugin", from: "1.0.0"),
        // AUTO GENERATED ↑: swift-project-starter: deps
    ],
    targets: [
        .executableTarget(
            name: "swift-project-starter",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftRefactor", package: "swift-syntax"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "Logging", package: "swift-log"),
            ],
        ),

        .testTarget(
            name: "swift-project-starterTests",
            dependencies: [
                "swift-project-starter"
            ],
            exclude: ["fixtures"],
            resources: [.copy("dummy")],
        ),

        .plugin(
            name: "swift-project-starter-plugin",
            capability: .command(
                intent: .custom(
                    verb: "starter",
                    description: "This command generates a starter file for your project.",
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "This command generates a starter file for your project.")
                ],
            ),
            dependencies: [
                "swift-project-starter"
            ],
        ),
    ],
    swiftLanguageModes: [.v6],
)

// AUTO GENERATED ↓: swift-project-starter: settings
for target in package.targets {
    if [.executable, .test, .regular].contains(target.type) {
        do {
            var swiftSettings = target.swiftSettings ?? []
            defer {
                target.swiftSettings = swiftSettings
            }
            swiftSettings += [
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        }
        do {
            var plugins = target.plugins ?? []
            defer {
                target.plugins = plugins
            }
            plugins += [
                .plugin(name: "Lint", package: "swift-format-plugin")
            ]
        }
    }
}
// AUTO GENERATED ↑: swift-project-starter: settings
