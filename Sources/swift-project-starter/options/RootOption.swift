import Foundation
public import ArgumentParser
public import System

struct RootOption: ParsableArguments {
    @Option
    var packagePath: FilePath

    @Option
    var configPath: FilePath?

    mutating func validate() throws {
        let manager = FileManager.default

        try normalizePath(&packagePath, fileName: "Package.swift", with: manager)

        if var configPath {
            try normalizePath(&configPath, fileName: "config.json", with: manager)
            self.configPath = configPath
        }
    }
}

private func normalizePath(
    _ path: inout FilePath,
    fileName: FilePath.Component,
    with manager: FileManager,
) throws(ValidationError) {
    if path.lastComponent != fileName {
        var isDirectory: ObjCBool = false
        if !manager.fileExists(atPath: path.string, isDirectory: &isDirectory) {
            throw ValidationError("\(path) is not a valid path.")
        }
        if isDirectory.boolValue {
            path.append(fileName)
        }
    }

    if !manager.fileExists(atPath: path.string) {
        throw ValidationError("\(path) is not a valid path.")
    }
}

// MARK: - extensions
extension FilePath: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(argument)
    }
}
