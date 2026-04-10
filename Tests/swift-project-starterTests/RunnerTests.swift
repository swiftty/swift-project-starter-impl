import Foundation
import Testing
@testable import swift_project_starter

let fixturesDirectory = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "fixtures")

/// Returns path to the built products directory.
var productsDirectory: URL {
    #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("couldn't find the products directory")
    #else
        return Bundle.main.bundleURL
    #endif
}

struct `swift-project-starterTests` {
    private func exec(_ subcommand: String, arguments: [String], on target: String) throws -> (
        stdout: String,
        stderr: String
    ) {
        let bin = productsDirectory.appending(path: "swift-project-starter")

        let stdout = Pipe()
        let stderr = Pipe()
        let process = try shell(
            bin, ["init"] + arguments,
            currentDirectoryURL: fixturesDirectory.appending(path: target),
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
        arguments: [
            ([], "Error: Missing expected argument '--package-path <package-path>'"),
            (
                ["--package-path", "."],
                "Error: Missing expected argument '--project <project>' or '--config-path <config-path>'",
            ),
        ],
    )
    func `test init command requires option`(_ arguments: [String], _ expected: String) throws {
        let (_, error) = try exec("init", arguments: arguments, on: "Example")
        #expect(error.contains(expected))
    }
}

extension Trait where Self == SwiftPMSetupTrait {
    static func setupSwiftPackage(
        name: String,
        to currentDirectory: URL? = nil,
    ) -> Self {
        SwiftPMSetupTrait(name: name, currentDirectory: currentDirectory)
    }
}

struct SwiftPMSetupTrait: TestTrait, TestScoping {
    var name: String
    var currentDirectory: URL?

    private func setUp() throws {
        try shell(
            URL(filePath: "/usr/bin/env"),
            "mkdir", "-p", name,
            currentDirectoryURL: currentDirectory,
        ).waitUntilExit()
        try shell(
            URL(filePath: "/usr/bin/env"),
            "swift", "package", "init", "--type", "library",
            currentDirectoryURL: currentDirectory?.appending(path: name),
        ).waitUntilExit()
    }

    private func tearDown() throws {
        try shell(
            URL(filePath: "/usr/bin/env"),
            "rm", "-rf", name,
            currentDirectoryURL: currentDirectory,
        ).waitUntilExit()
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent () async throws -> Void,
    ) async throws {
        try setUp()
        do {
            try await function()
        } catch {
            try tearDown()
            throw error
        }

        try tearDown()
    }
}

@discardableResult
func shell(
    _ executableURL: URL,
    _ arguments: String...,
    currentDirectoryURL: URL? = nil,
    stdout: Any? = nil,
    stderr: Any? = nil,
) throws -> Process {
    try shell(
        executableURL, arguments,
        currentDirectoryURL: currentDirectoryURL,
        stdout: stdout, stderr: stderr, )
}

@discardableResult
func shell(
    _ executableURL: URL,
    _ arguments: [String],
    currentDirectoryURL: URL? = nil,
    stdout: Any? = nil,
    stderr: Any? = nil,
) throws -> Process {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectoryURL
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()

    return process
}
