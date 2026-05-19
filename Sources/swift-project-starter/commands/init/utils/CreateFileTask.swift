import Foundation
import SystemPackage
import Logging
import ArgumentParser

extension InitCommand {
    struct CreateFileTask {
        var path: FilePath
        var content: String
    }
}

extension InitCommand.CreateFileTask {
    func run() async throws {
        Logger.currentScope?.info("creating file: \(path.lastComponent?.string ?? "<unknown>")")

        let created = try createDirectory(at: path.directory())
        let hasOtherFiles = {
            if !created, try !enumerateContents(of: path.directory()).isEmpty {
                true
            } else {
                false
            }
        }

        // Skip if `.gitkeep` is not needed
        if path.lastComponent?.string == ".gitkeep", try hasOtherFiles() {
            return
        }

        try writeContent(content, to: path)
    }

    private func createDirectory(at directory: FilePath) throws -> Bool {
        let manager = FileManager.default

        var isDirectory: ObjCBool = false
        let exists = manager.fileExists(atPath: directory.string, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            return false
        }
        if !exists {
            try manager.createDirectory(atPath: directory.string, withIntermediateDirectories: true)
            return true
        }
        throw ValidationError("'\(directory.string)' is not a directory")
    }

    private func enumerateContents(of directory: FilePath) throws -> [String] {
        let manager = FileManager.default
        return try manager.contentsOfDirectory(atPath: directory.string)
    }

    private func writeContent(_ content: String, to path: FilePath) throws {
        let manager = FileManager.default

        let exists = manager.fileExists(atPath: path.string)
        guard !exists else {
            let path = path.relative(from: FilePath(manager.currentDirectoryPath))
            Logger.currentScope?.error("'\(path.string)' already exists")
            return
        }

        try content.write(toFile: path.string, atomically: true, encoding: .utf8)
    }
}
