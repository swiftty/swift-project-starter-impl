import Foundation
import ArgumentParser
import System

struct ProjectOption: ParsableArguments {
    enum ProjectType: String, ExpressibleByArgument {
        case application, library
    }

    @Option
    var project: ProjectType?

    @Option
    var projectName: String?

    @OptionGroup
    var options: RootOption

    var packagePath: FilePath { options.packagePath }

    func validate() throws {
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
        if let configPath = options.configPath {
            let data = try Data(contentsOf: URL(filePath: configPath)!)
            let decoder = JSONDecoder()
            return try decoder.decode(Config.self, from: data)
        }

        guard let project else {
            throw ValidationError(
                "Error: Missing expected argument '--project <project>' or '--config-path <config-path>'")
        }

        switch project {
        case .application:
            guard let projectName else {
                throw ValidationError("Error: Missing expected argument '--project-name <name>'")
            }
            let packagePath = packagePath.standardized()
            return Config.forApplicationDefault(name: projectName, packagePath: packagePath)

        case .library:
            return Config.forLibraryDefault
        }
    }
}
