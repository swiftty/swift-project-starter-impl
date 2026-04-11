import Foundation
import Testing
@testable import swift_project_starter

struct `swift-project-starterTests` {
    private func exec(_ subcommand: String, _ arguments: String...) throws -> (
        stdout: String,
        stderr: String
    ) {
        try exec(subcommand, arguments)
    }

    private func exec(_ subcommand: String, _ arguments: [String]) throws -> (
        stdout: String,
        stderr: String
    ) {
        let setting = try #require(DirectoryScope.current)

        let bin = productsDirectory.appending(path: "swift-project-starter")

        let stdout = Pipe()
        let stderr = Pipe()
        let process = try shell(
            bin, ["init"] + arguments,
            currentDirectoryURL: setting.workingDirectory,
            stdout: stdout, stderr: stderr,
        )

        process.waitUntilExit()

        func string(_ pipe: Pipe) throws -> String {
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            return String(data: data, encoding: .utf8) ?? ""
        }

        return (try string(stdout), try string(stderr))
    }

    @Test(
        .setupSwiftPackage(name: "Example", to: fixturesDirectory),
        .addEmptyDependency,
        arguments: [
            ([], "Error: Missing expected argument '--package-path <package-path>'"),
            (
                ["--package-path", "."],
                "Error: Missing expected argument '--project <project>' or '--config-path <config-path>'",
            ),
        ],
    )
    func `test init command requires option`(_ arguments: [String], _ expected: String) throws {
        let (_, error) = try exec("init", arguments)
        #expect(error.contains(expected))
    }

    @Test(
        .setupSwiftPackage(name: "Example", to: fixturesDirectory),
        .addEmptyDependency,
    )
    func `test init command runs success`() throws {
        let (output, _) = try exec("init", "--package-path", ".", "--project", "library")
        #expect(output.contains("✅"))
        #expect(!output.contains("❌"))
    }

    @Test(
        .setupSwiftPackage(name: "Example", to: fixturesDirectory),
        .addEmptyDependency,
        .createFile(name: ".swift-format"),
    )
    func `test init command runs partially success`() throws {
        let (output, _) = try exec("init", "--package-path", ".", "--project", "library")
        #expect(output.contains("✅"))
        #expect(output.contains("❌ : '.swift-format' already exists"))

        let path = try #require(
            DirectoryScope.current?.workingDirectory
                .appending(path: ".swift-format")
        )
        #expect(try String(contentsOf: path, encoding: .utf8) == "")
    }
}
