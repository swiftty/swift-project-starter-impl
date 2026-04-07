import Foundation
import ArgumentParser
import Subprocess
import System
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import Logging

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init"
    )

    @OptionGroup
    var options: ProjectOption

    func run() async throws {
        try await Logger.$currentScope.withValue(Logger(label: "init")) {
            try await _run()
        }
    }

    private func _run() async throws {
        let config = try options.asConfig()

        // install dependencies
        do {
            Logger.currentScope?.info("install dependencies")
            let task = InstallDependencyTask(packagePath: options.packagePath)
            for dep in config.dependencies {
                try await task.run(url: dep.url, version: dep.from)
            }
        }

        // insert swiftSettings to Package.swift
        do {
            Logger.currentScope?.info("insert swift settings")
            let task = InsertSettingAndPluginTask(
                packagePath: options.packagePath,
                swiftSettings: config.swiftSettings,
                hasSwiftFormatPlugin: config.dependencies.contains(where: {
                    $0.url.contains("swiftty/swift-format-plugin")
                })
            )
            try await task.run()
        }

        // install resources
        if case let resources = config.project.files(relativeTo: options.packagePath.directory()),
           !resources.isEmpty {
            Logger.currentScope?.info("install resources")

            for file in resources {
                let task = CreateFileTask(path: FilePath(file.filePath), content: file.content)
                try await task.run()
            }
        }
    }
}

private extension Config.Project {
    func files(relativeTo packagePath: FilePath) -> [Config.Project.File] {
        switch self {
        case .application(_, let projectRoot, let makefile, let xcodegen, let resources):
            let path = packagePath.appending(FilePath(projectRoot).components)

            var files: [Config.Project.File] = []
            if let makefile {
                files.append(.init(filePath: "Makefile", content: makefile.content))
            }
            if let xcodegen {
                files.append(.init(filePath: "project.yml", content: xcodegen.content))
            }
            files.append(contentsOf: resources)
            return files.map {
                var resource = $0
                resource.filePath = path.appending(resource.filePath).string
                return resource
            }

        case .library(let resources):
            return resources.map {
                var resource = $0
                resource.filePath = packagePath.appending(resource.filePath).string
                return resource
            }
        }
    }
}

protocol SwiftPackageTask {}

extension SwiftPackageTask {
    @discardableResult
    func `swift-package`(_ arguments: String..., packagePath: FilePath) async throws -> Bool {
        let result = try await Subprocess.run(
            .name("swift"),
            arguments: Arguments([
                "package",
                "--package-path",
                packagePath.directory().string,
            ] + arguments),
            output: .discarded,
            error: .standardError
        )

        return result.terminationStatus.isSuccess
    }
}

// MARK: - tasks
struct InstallDependencyTask: SwiftPackageTask {
    var packagePath: FilePath

    func run(url: String, version: String) async throws {
        Logger.currentScope?.info("installing dependency: \(url)")
        let executed = try await `swift-package`("add-dependency", url, "--from", version, packagePath: packagePath)
        guard executed else {
            Logger.currentScope?.warning("skipping dependency: \(url)")
            return
        }
        Logger.currentScope?.info("installed dependency: \(url)")
    }
}

struct InsertSettingAndPluginTask {
    var packagePath: FilePath
    var swiftSettings: [Config.SwiftSetting]
    var hasSwiftFormatPlugin: Bool

    private let beginMarker = "BEGIN AUTO GENERATED: swift-project-starter"
    private let endMarker = "END AUTO GENERATED: swift-project-starter"

    func run() async throws {
        let url = URL(filePath: packagePath)!

        var source = try loadPackageSwift(from: url)
        source = removingInsertionCode(from: source)

        let code = try makeInsertionCode()
            .with(\.leadingTrivia, [.newlines(2), .lineComment("// \(beginMarker)"), .newlines(1)])
            .with(\.trailingTrivia, [.newlines(1), .lineComment("// \(endMarker)")])

        var statements = source.statements
        statements.append(contentsOf: code)
        let result = source
            .with(\.statements, statements)
            .formatted()
            .description

        try result.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadPackageSwift(from url: URL) throws -> SourceFileSyntax {
        let content = try String(contentsOf: url, encoding: .utf8)
        return Parser.parse(source: content)
    }

    private func removingInsertionCode(from source: SourceFileSyntax) -> SourceFileSyntax {
        func hasMarker(_ trivia: Trivia, marker: String) -> Bool {
            trivia.contains {
                if case .lineComment(let text) = $0 {
                    return text.hasPrefix("// \(marker)")
                }
                return false
            }
        }

        var statements: [CodeBlockItemSyntax] = []
        var isInAutoGeneratedCode = false

        for item in source.statements {
            if hasMarker(item.leadingTrivia, marker: beginMarker) {
                isInAutoGeneratedCode = true
                continue
            }
            if hasMarker(item.leadingTrivia, marker: endMarker) {
                isInAutoGeneratedCode = false
                continue
            }
            if isInAutoGeneratedCode {
                continue
            }

            statements.append(item)
        }
        let endTrivia = source.endOfFileToken.leadingTrivia
        let foundEndMarker = isInAutoGeneratedCode && hasMarker(endTrivia, marker: endMarker)

        return source
            .with(\.statements, CodeBlockItemListSyntax(statements))
            .with(\.endOfFileToken.leadingTrivia, foundEndMarker ? .newline : endTrivia)
    }

    private func makeInsertionCode() throws -> CodeBlockItemListSyntax {
        return try CodeBlockItemListSyntax {
            try ForStmtSyntax("for target in package.targets") {
                try IfExprSyntax("if [.executable, .test, .regular].contains(target.type)") {
                    try DoStmtSyntax("do") {
                        let settings = ArrayElementListSyntax {
                            for setting in swiftSettings {
                                ArrayElementSyntax(expression: setting.toSyntax())
                                    .with(\.leadingTrivia, .newline)
                            }
                        }.with(\.trailingTrivia, .newline)

                        "var swiftSettings = target.swiftSettings ?? []"
                        "defer { target.swiftSettings = swiftSettings }"
                        "swiftSettings += [\(settings)]"
                    }

                    if hasSwiftFormatPlugin {
                        try DoStmtSyntax("do") {
                            let plugins = ArrayElementListSyntax {
                                let plugin = ExprSyntax("""
                                .plugin(name: "Lint", package: "swift-format-plugin")
                                """)
                                ArrayElementSyntax(expression: plugin)
                                    .with(\.leadingTrivia, .newline)
                            }.with(\.trailingTrivia, .newline)

                            "var plugins = target.plugins ?? []"
                            "defer { target.plugins = plugins }"
                            "plugins += [\(plugins)]"
                        }
                    }
                }
            }
        }
    }
}

private extension Config.SwiftSetting {
    func toSyntax() -> ExprSyntax {
        switch self {
        case .defaultIsolation(let isolation):
            return ExprSyntax(".defaultIsolation(\(raw: isolation.rawValue).self)")

        case .enableUpcomingFeature(let feature):
            return ExprSyntax(".enableUpcomingFeature(\"\(raw: feature)\")")

        case .enableExperimentalFeature(let feature):
            return ExprSyntax(".enableExperimentalFeature(\"\(raw: feature)\")")
        }
    }
}

struct CreateFileTask {
    var path: FilePath
    var content: String

    func run() async throws {
        Logger.currentScope?.info("creating file: \(path.lastComponent?.string ?? "<unknown>")")

        try createDirectory(at: path.directory())

        try writeContent(content, to: path)
    }

    private func createDirectory(at path: FilePath) throws {
        let manager = FileManager.default

        var isDirectory: ObjCBool = false
        let exists = manager.fileExists(atPath: path.string, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            return
        }
        if !exists {
            try manager.createDirectory(atPath: path.string, withIntermediateDirectories: true)
            return
        }
        if !isDirectory.boolValue {
            throw ValidationError("'\(path.string)' is not a directory")
        }
    }

    private func writeContent(_ content: String, to path: FilePath) throws {
        let manager = FileManager.default

        let exists = manager.fileExists(atPath: path.string)
        guard !exists else {
            let path = path.relative(from: FilePath(manager.currentDirectoryPath))
            Logger.currentScope?.error("'\(path.string)' already exists")
            return
        }

        try content.write(toFile: path.string, atomically: true, encoding: .utf8)
    }
}
