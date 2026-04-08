import Foundation
import System
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import Logging

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
