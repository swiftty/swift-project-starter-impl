import Foundation
public import ArgumentParser
public import SystemPackage

struct Options: ParsableArguments {
    enum ProjectType: String, ExpressibleByArgument {
        case application, library
    }

    @Option
    var project: ProjectType?

    @Option
    var projectName: String?

    @Option
    var packagePath: FilePath

    @Option
    var configPath: FilePath?

    @Option
    var applicationPath: FilePath?

    mutating func validate() throws {
        let manager = FileManager.default

        try normalizePath(&packagePath, fileName: "Package.swift", with: manager)

        if var configPath {
            try normalizePath(&configPath, fileName: "config.json", with: manager)
            self.configPath = configPath
        }

        let config = try asConfig()
        if case .application(_, let projectRoot, _, _, _) = config.project {
            let path = FilePath(projectRoot)
            if path.isAbsolute {
                throw ValidationError(
                    "Error: Project root path '\(projectRoot)' must be relative from '--package-path'")
            }
        }
    }

    func asConfig() throws -> Config {
        if let configPath {
            let data = try Data(contentsOf: URL(filePath: configPath)!)
            let decoder = JSONDecoder()
            return try decoder.decode(Config.self, from: data)
        }

        guard let project else {
            throw ValidationError(
                "Error: Missing expected argument '--project <project>' or '--config-path <config-path>'"
            )
        }

        switch project {
        case .application:
            guard let projectName else {
                throw ValidationError("Error: Missing expected argument '--project-name <name>'")
            }
            guard let applicationPath else {
                throw ValidationError("Error: Missing expected argument '--application-path <name>'")
            }
            guard applicationPath.isRelative else {
                throw ValidationError(
                    "Error: Project root path '\(applicationPath)' must be relative from '--application-path <name>'")
            }

            return Config.forApplicationDefault(
                name: projectName,
                packagePath: packagePath,
                applicationPath: applicationPath,
            )

        case .library:
            return Config.forLibraryDefault
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
