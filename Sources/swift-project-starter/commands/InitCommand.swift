import Foundation
import ArgumentParser
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
        if case let dependencies = config.dependencies, !dependencies.isEmpty {
            Logger.currentScope?.info("install dependencies")
            // TODO: refactor
            for dep in dependencies {
                Logger.currentScope?.info("installing dependency: \(dep.url)")
                let task = InstallDependencyTask(dependencies: [dep], packagePath: options.packagePath)
                try await task.run()

                Logger.currentScope?.info("installed dependency: \(dep.url)")
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
                }),
            )
            try await task.run()
        }

        // install resources
        if case let resources = config.project.files(relativeTo: options.packagePath.directory()),
            !resources.isEmpty
        {
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

protocol SwiftSyntaxTask {}

extension SwiftSyntaxTask {
    func loadSourceFileSyntax(for path: FilePath) throws -> SourceFileSyntax {
        let url = URL(filePath: path)!
        let content = try String(contentsOf: url, encoding: .utf8)
        return Parser.parse(source: content)
    }

    func writeSourceFileSyntax(_ source: some SyntaxProtocol, to path: FilePath) throws {
        let url = URL(filePath: path)!
        let content = source.formatted().description
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - tasks
struct InstallDependencyTask: SwiftSyntaxTask {
    var dependencies: [Config.Dependency]
    var packagePath: FilePath

    private static let beginMarker = "BEGIN AUTO GENERATED: swift-project-starter: deps"
    private static let endMarker = "END AUTO GENERATED: swift-project-starter: deps"

    private static func isMarker(_ trivia: TriviaPiece) -> Bool {
        if case .lineComment(let string) = trivia {
            return string.hasPrefix("// \(beginMarker)") || string.hasPrefix("// \(endMarker)")
        }
        return false
    }

    func run() async throws {
        let source = try loadSourceFileSyntax(for: packagePath)

        let result = DepsRewriter(dependencies: dependencies).rewrite(source)
        try writeSourceFileSyntax(result, to: packagePath)
    }

    private class DepsRewriter: SyntaxRewriter {
        let dependencies: [Config.Dependency]

        init(dependencies: [Config.Dependency]) {
            self.dependencies = dependencies
            super.init()
        }

        override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
            // find Package(...)
            guard let called = node.calledExpression.as(DeclReferenceExprSyntax.self),
                called.baseName.trimmed.text == "Package"
            else {
                return super.visit(node)
            }

            guard
                let argIndex = node.arguments.firstIndex(where: {
                    $0.label?.trimmed.text == "dependencies"
                })
            else {
                return super.visit(node)
            }

            let rewriter = AutoGeneratedDependencyRemover()
            let deps =
                rewriter
                .rewrite(node.arguments[argIndex])

            var dependencies = dependencies
            var insertedPackages = rewriter.insertedPackages

            // cleaning existing dependencies
            for (index, pkg) in insertedPackages.enumerated().reversed() {
                let status = checkExistingStatus(for: pkg, in: &dependencies)
                switch status {
                case .removed, .exists, .missing:
                    insertedPackages.remove(at: index)

                case .modified(let cleaned):
                    insertedPackages[index] = cleaned
                }
            }

            // insert dependencies
            guard
                let deps =
                    AutoGeneratedDependencyInserter(insertedPackages: insertedPackages, dependencies: dependencies)
                    .rewrite(deps)
                    .as(LabeledExprSyntax.self)
            else {
                return super.visit(node)
            }

            return super.visit(node.with(\.arguments[argIndex], deps))
        }

        private enum ExistingStatus {
            case missing
            case removed
            case exists
            case modified(cleaned: FunctionCallExprSyntax)
        }

        private func checkExistingStatus(for expr: FunctionCallExprSyntax, in deps: inout [Config.Dependency])
            -> ExistingStatus
        {
            func extractValue(forKey key: String) -> String? {
                expr.arguments
                    .first(where: { $0.label?.trimmed.text == key })?
                    .expression
                    .as(StringLiteralExprSyntax.self)?
                    .segments
                    .trimmedDescription
            }

            guard let url = extractValue(forKey: "url") else {
                return .missing
            }

            for (index, dep) in deps.enumerated().reversed() where dep.url == url {
                guard
                    let from = extractValue(forKey: "from"),
                    from == dep.from
                else {
                    let cleaned = TriviaRemover()
                        .rewrite(expr)
                        .cast(FunctionCallExprSyntax.self)
                    deps.remove(at: index)
                    Logger.currentScope?.warning("skipping dependency: \(url)")
                    return .modified(cleaned: cleaned)
                }
                return .exists
            }

            return .removed
        }

        struct RegionFilter<C: SyntaxCollection> {
            enum MarkerPosition {
                case begin, end
            }

            var checkMarker: (TriviaPiece) -> MarkerPosition?

            @specialized(where C == ArrayElementListSyntax)
            func callAsFunction(_ collection: C) -> (passed: [C.Element], filtered: [C.Element]) {
                func findMarker(_ trivia: Trivia) -> MarkerPosition? {
                    trivia.lazy.compactMap(checkMarker).first
                }

                var passed: [C.Element] = []
                var filtered: [C.Element] = []
                var isInAutoGeneratedCode = false

                for item in collection {
                    func shouldPass() -> Bool {
                        let position = findMarker(item.leadingTrivia)
                        if position == .begin {
                            isInAutoGeneratedCode = true
                            return false
                        }
                        if position == .end {
                            isInAutoGeneratedCode = false
                            return false
                        }
                        return !isInAutoGeneratedCode
                    }

                    if shouldPass() {
                        passed.append(item)
                    } else {
                        filtered.append(item)
                    }
                }
                return (passed, filtered)
            }
        }

        private class AutoGeneratedDependencyRemover: SyntaxRewriter {
            private(set) var insertedPackages: [FunctionCallExprSyntax] = []

            override func visit(_ node: ArrayExprSyntax) -> ExprSyntax {
                let filter = RegionFilter<ArrayElementListSyntax> { trivia in
                    if case .lineComment(let string) = trivia {
                        if string.hasPrefix("// \(beginMarker)") {
                            return .begin
                        }
                        if string.hasPrefix("// \(endMarker)") {
                            return .end
                        }
                    }
                    return nil
                }

                let (passed, filtered) = filter(node.elements)
                insertedPackages.append(
                    contentsOf: filtered.compactMap {
                        $0.expression.as(FunctionCallExprSyntax.self)
                    }
                )

                let pieces = node.rightSquare.leadingTrivia.filter { filter.checkMarker($0) == nil }
                let newNode =
                    node
                    .with(\.elements, .init(passed))
                    .with(\.rightSquare.leadingTrivia, Trivia(pieces: pieces))
                return super.visit(newNode)
            }
        }

        private class AutoGeneratedDependencyInserter: SyntaxRewriter {
            var insertedPackages: [FunctionCallExprSyntax]
            var dependencies: [Config.Dependency]

            init(insertedPackages: [FunctionCallExprSyntax], dependencies: [Config.Dependency]) {
                self.insertedPackages = insertedPackages
                self.dependencies = dependencies
                super.init()
            }

            override func visit(_ node: ArrayExprSyntax) -> ExprSyntax {
                guard !insertedPackages.isEmpty || !dependencies.isEmpty else {
                    return super.visit(node)
                }

                defer {
                    insertedPackages = []
                    dependencies = []
                }

                var elements: [ArrayElementSyntax] = []
                for pkg in insertedPackages {
                    elements.append(
                        ArrayElementSyntax(expression: pkg)
                            .with(\.leadingTrivia, .newline)
                    )
                }
                for dep in dependencies {
                    let expr = ExprSyntax(
                        """
                        .package(url: "\(raw: dep.url)", from: "\(raw: dep.from)")
                        """)
                    elements.append(
                        ArrayElementSyntax(expression: expr)
                            .with(\.leadingTrivia, .newline)
                    )
                }

                if let elem = elements.first {
                    elements[elements.startIndex] =
                        elem
                        .with(
                            \.leadingTrivia,
                            elem.leadingTrivia.appending([.lineComment("// \(beginMarker)"), .newlines(1)]),
                        )
                }

                return super.visit(
                    node
                        .with(\.elements, node.elements + elements)
                        .with(
                            \.rightSquare.leadingTrivia,
                            [.newlines(1), .spaces(4 * 2), .lineComment("// \(endMarker)"), .newlines(1), .spaces(4)],
                        )
                )
            }
        }

        private class TriviaRemover: SyntaxRewriter {
            override func visitAny(_ node: Syntax) -> Syntax? {
                node.trimmed
            }
        }
    }
}

struct InsertSettingAndPluginTask: SwiftSyntaxTask {
    var packagePath: FilePath
    var swiftSettings: [Config.SwiftSetting]
    var hasSwiftFormatPlugin: Bool

    private let beginMarker = "BEGIN AUTO GENERATED: swift-project-starter: settings"
    private let endMarker = "END AUTO GENERATED: swift-project-starter: settings"

    func run() async throws {
        var source = try loadSourceFileSyntax(for: packagePath)
        source = removingInsertionCode(from: source)

        let code = try makeInsertionCode()
            .with(\.leadingTrivia, [.newlines(2), .lineComment("// \(beginMarker)"), .newlines(1)])
            .with(\.trailingTrivia, [.newlines(1), .lineComment("// \(endMarker)")])

        var statements = source.statements
        statements.append(contentsOf: code)
        let result = source.with(\.statements, statements)

        try writeSourceFileSyntax(result, to: packagePath)
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

        return
            source
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
                                let plugin = ExprSyntax(
                                    """
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
