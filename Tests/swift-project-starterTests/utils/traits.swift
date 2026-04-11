import Foundation
import Testing

extension Trait where Self == DirectoryScopeTrait {
    static func directoryScope(
        name: String,
        random: Bool = true,
        to parent: URL,
    ) -> Self {
        DirectoryScopeTrait(name: name, random: random, parent: parent)
    }

    static func directoryScope(
        name: String,
        random: Bool = true,
    ) -> Self {
        DirectoryScopeTrait(name: name, random: random)
    }
}

extension Trait where Self == SwiftPMSetupTrait {
    static var setupSwiftPackage: Self { .init() }
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

// MARK: -

struct DirectoryScope {
    @TaskLocal static var current: DirectoryScope?

    var name: String
    var parent: URL

    var workingDirectory: URL { parent.appending(path: name) }
}

struct DirectoryScopeTrait: TestTrait, TestScoping {
    private enum Repr {
        case `default`(name: String, parent: URL)
        case relative(name: String)
    }
    private var repr: Repr

    var name: String {
        switch repr {
        case .default(let name, _): return name
        case .relative(let name): return name
        }
    }
    var parent: URL {
        switch repr {
        case .default(_, let parent):
            return parent
        case .relative:
            return DirectoryScope.current!.workingDirectory
        }
    }

    init(name: String, random: Bool = true, parent: URL) {
        self.repr = .default(
            name: random ? "\(name)\(UUID().uuidString.prefix(4))" : name,
            parent: parent,
        )
    }

    init(name: String, random: Bool = true) {
        self.repr = .relative(
            name: random ? "\(name)\(UUID().uuidString.prefix(4))" : name
        )
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent () async throws -> Void,
    ) async throws {
        try setUp()
        do {
            try await DirectoryScope.$current.withValue(.init(name: name, parent: parent)) {
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
            currentDirectoryURL: parent,
        ).waitUntilExit()
    }

    private func tearDown() throws {
        try shell(
            "rm", "-rf", name,
            currentDirectoryURL: parent,
        ).waitUntilExit()
    }
}

struct SwiftPMSetupTrait: TestTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent () async throws -> Void,
    ) async throws {
        let setting = try #require(DirectoryScope.current)
        try shell(
            "swift", "package", "init", "--type", "library",
            currentDirectoryURL: setting.workingDirectory,
        ).waitUntilExit()
        try await function()
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
        let setting = try #require(DirectoryScope.current)
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
        let setting = try #require(DirectoryScope.current)
        let filePath = setting.workingDirectory
            .appending(path: name)
            .path(percentEncoded: false)
        let content = content.data(using: .utf8)

        FileManager.default.createFile(atPath: filePath, contents: content)
        try await function()
    }
}
