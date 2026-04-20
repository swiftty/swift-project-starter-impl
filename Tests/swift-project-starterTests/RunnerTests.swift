import Foundation
import Testing
@testable import swift_project_starter

struct `swift-project-starterTests` {

    @Test(
        .directoryScope(name: "Example", to: fixturesDirectory),
        .setupSwiftPackage,
    )
    func `test dump-config command`() throws {
        // swift-format-ignore
        let expected = """
        {
          "dependencies" : [
            {
              "from" : "1.0.0",
              "url" : "https:\\/\\/github.com\\/swiftty\\/swift-format-plugin"
            }
          ],
          "project" : {
            "resources" : [
              {
                "content" : "{\\n  \\"indentation\\": {\\n    \\"spaces\\": 4\\n  },\\n  \\"lineLength\\": 120,\\n  \\"multilineTrailingCommaBehavior\\": \\"alwaysUsed\\",\\n  \\"multiElementCollectionTrailingCommas\\": false,\\n  \\"rules\\": {\\n    \\"NoAccessLevelOnExtensionDeclaration\\": false\\n  },\\n  \\"version\\": 1\\n}\\n",
                "filePath" : ".swift-format"
              }
            ],
            "type" : "library"
          },
          "swiftSettings" : [
            {
              "enableUpcomingFeature" : "InternalImportsByDefault"
            },
            {
              "enableUpcomingFeature" : "NonisolatedNonsendingByDefault"
            }
          ]
        }

        """
        let (output, error) = try exec("dump-config", "--package-path", ".", "--project", "library")
        #expect(output == expected)
        #expect(error == "")
    }

    @Test(
        .directoryScope(name: "Example", to: fixturesDirectory),
        .setupSwiftPackage,
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
        .directoryScope(name: "Example", to: fixturesDirectory),
        .setupSwiftPackage,
        .addEmptyDependency,
    )
    func `test init command succeeds for library type`() throws {
        let (output, _) = try exec("init", "--package-path", ".", "--project", "library")
        #expect(output.contains("✅"))
        #expect(!output.contains("❌"))
    }

    @Test(
        .directoryScope(name: "Example", to: fixturesDirectory),
        .setupSwiftPackage,
        .addEmptyDependency,
        .createFile(name: ".swift-format"),
    )
    func `test init command succeeds for library type partially overriding`() throws {
        let (output, _) = try exec("init", "--package-path", ".", "--project", "library")
        #expect(output.contains("✅"))
        #expect(output.contains("❌ : '.swift-format' already exists"))

        let path = try #require(
            DirectoryScope.current?.workingDirectory
                .appending(path: ".swift-format")
        )
        #expect(try String(contentsOf: path, encoding: .utf8) == "")
    }

    @Test(
        .directoryScope(name: "Example", to: fixturesDirectory),
        .directoryScope(name: "LocalPackage", random: false),
        .setupSwiftPackage,
        .addEmptyDependency,
        arguments: [
            (
                ["--package-path", "."],
                "Error: Missing expected argument '--project-name <name>'",
            )
        ],
    )
    func `test init command requires option for application type`(_ arguments: [String], _ expected: String) throws {
        let (_, error) = try exec("init", arguments + ["--project", "application"])
        #expect(error.contains(expected))
    }

    @Test(
        .directoryScope(name: "Example", to: fixturesDirectory),
        .directoryScope(name: "LocalPackage", random: false),
        .setupSwiftPackage,
        .addEmptyDependency,
    )
    func `test init command succeeds for application type`() throws {
        let (output, _) = try exec(
            "init", "--package-path", ".", "--project", "application", "--project-name", "Example",
        )
        #expect(output.contains("✅"))
        #expect(!output.contains("❌"))

        let root = try #require(DirectoryScope.current?.parent)
        #expect(root.lastPathComponent.hasPrefix("Example"))

        func content(of file: String) -> String? {
            try? String(contentsOf: root.appending(path: file), encoding: .utf8)
        }

        #expect(content(of: ".swift-format") != "")
        #expect(content(of: "Makefile") != "")
        #expect(content(of: "project.yml") != "")
    }
}

extension `swift-project-starterTests` {
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
            bin, [subcommand] + arguments,
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
}
