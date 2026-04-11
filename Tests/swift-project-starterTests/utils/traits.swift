import Foundation
import Testing

extension Trait where Self == SwiftPMSetupTrait {
    static func setupSwiftPackage(
        name: String,
        to currentDirectory: URL,
    ) -> Self {
        SwiftPMSetupTrait(name: name, currentDirectory: currentDirectory)
    }
}

extension Trait where Self == AddEmptyDependencyTrait {
    /// add `dependencies: [],` to Package.swift
    static var addEmptyDependency: Self { .init() }
}

extension Trait where Self == CreateFileTrait {
    static func createFile(name: String, content: String = "") -> Self {
        CreateFileTrait(name: name, content: content)
    }
}

struct SwiftPMSetupTrait: TestTrait, TestScoping {
    var name: String
    var currentDirectory: URL

    init(name: String, random: Bool = true, currentDirectory: URL) {
        self.name =
            if random {
                "\(name)\(UUID().uuidString.prefix(4))"
            } else {
                name
            }
        self.currentDirectory = currentDirectory
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent () async throws -> Void,
    ) async throws {
        try setUp()
        do {
            try await ProjectSetting.$currentScope.withValue(.init(name: name, currentDirectory: currentDirectory)) {
                try await function()
            }
        } catch {
            try tearDown()
            throw error
        }

        try tearDown()
    }

    private func setUp() throws {
        try shell(
            "mkdir", "-p", name,
            currentDirectoryURL: currentDirectory,
        ).waitUntilExit()
        try shell(
            "swift", "package", "init", "--type", "library",
            currentDirectoryURL: currentDirectory.appending(path: name),
        ).waitUntilExit()
    }

    private func tearDown() throws {
        try shell(
            "rm", "-rf", name,
            currentDirectoryURL: currentDirectory,
        ).waitUntilExit()
    }
}

struct AddEmptyDependencyTrait: TestTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent () async throws -> Void,
    ) async throws {
        try modifyPackageSwift()
        try await function()
    }

    private func modifyPackageSwift() throws {
        let setting = try #require(ProjectSetting.currentScope)
        let packagePath = setting.workingDirectory.appending(path: "Package.swift")
        var packageManifest = try String(contentsOf: packagePath, encoding: .utf8)

        let insertText = "\n    dependencies: [],"
        let markerText = "\n    targets: ["
        packageManifest = packageManifest.replacingOccurrences(of: markerText, with: insertText + markerText)
        try packageManifest.write(to: packagePath, atomically: true, encoding: .utf8)
    }
}

struct CreateFileTrait: TestTrait, TestScoping {
    var name: String
    var content: String

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent () async throws -> Void,
    ) async throws {
        let setting = try #require(ProjectSetting.currentScope)
        let filePath = setting.workingDirectory
            .appending(path: name)
            .path(percentEncoded: false)
        let content = content.data(using: .utf8)

        FileManager.default.createFile(atPath: filePath, contents: content)
        try await function()
    }
}
