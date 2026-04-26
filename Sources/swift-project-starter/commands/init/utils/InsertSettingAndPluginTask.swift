import SystemPackage
import SwiftSyntax
import SwiftSyntaxBuilder

private let beginMarker = "AUTO GENERATED ↓: swift-project-starter: settings"
private let endMarker = "AUTO GENERATED ↑: swift-project-starter: settings"

extension InitCommand {
    struct InsertSettingAndPluginTask: InitCommand.SwiftSyntaxTask {
        var packagePath: FilePath
        var swiftSettings: [Config.SwiftSetting]
        var hasSwiftFormatPlugin: Bool
    }
}

extension InitCommand.InsertSettingAndPluginTask {
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
        let filter = InitCommand.RegionFilter<CodeBlockItemListSyntax> { trivia in
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

        let (statements, _) = filter(source.statements)

        let endTrivia = source.endOfFileToken.leadingTrivia
        let foundEndMarker = filter.findMarker(endTrivia) == .end

        return
            source
            .with(\.statements, .init(statements))
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
