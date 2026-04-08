import Foundation
import ArgumentParser
import System
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import Logging

struct InitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init"
    )

    @OptionGroup
    var options: ProjectOption

    func run() async throws {
        try await Logger.$currentScope.withValue(Logger(label: "init")) {
            try await _run()
        }
    }

    private func _run() async throws {
        let config = try options.asConfig()

        // install dependencies
        if case let dependencies = config.dependencies, !dependencies.isEmpty {
            Logger.currentScope?.info("install dependencies")
            // TODO: refactor
            for dep in dependencies {
                Logger.currentScope?.info("installing dependency: \(dep.url)")
                let task = InstallDependencyTask(dependencies: [dep], packagePath: options.packagePath)
                try await task.run()

                Logger.currentScope?.info("installed dependency: \(dep.url)")
            }
        }

        // insert swiftSettings to Package.swift
        do {
            Logger.currentScope?.info("insert swift settings")
            let task = InsertSettingAndPluginTask(
                packagePath: options.packagePath,
                swiftSettings: config.swiftSettings,
                hasSwiftFormatPlugin: config.dependencies.contains(where: {
                    $0.url.contains("swiftty/swift-format-plugin")
                }),
            )
            try await task.run()
        }

        // install resources
        if case let resources = config.project.files(relativeTo: options.packagePath.directory()),
            !resources.isEmpty
        {
            Logger.currentScope?.info("install resources")

            for file in resources {
                let task = CreateFileTask(path: FilePath(file.filePath), content: file.content)
                try await task.run()
            }
        }
    }
}

private extension Config.Project {
    func files(relativeTo packagePath: FilePath) -> [Config.Project.File] {
        switch self {
        case .application(_, let projectRoot, let makefile, let xcodegen, let resources):
            let path = packagePath.appending(FilePath(projectRoot).components)

            var files: [Config.Project.File] = []
            if let makefile {
                files.append(.init(filePath: "Makefile", content: makefile.content))
            }
            if let xcodegen {
                files.append(.init(filePath: "project.yml", content: xcodegen.content))
            }
            files.append(contentsOf: resources)
            return files.map {
                var resource = $0
                resource.filePath = path.appending(resource.filePath).string
                return resource
            }

        case .library(let resources):
            return resources.map {
                var resource = $0
                resource.filePath = packagePath.appending(resource.filePath).string
                return resource
            }
        }
    }
}
