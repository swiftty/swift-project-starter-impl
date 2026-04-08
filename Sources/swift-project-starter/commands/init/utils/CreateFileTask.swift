import Foundation
import System
import Logging
import ArgumentParser

struct CreateFileTask {
    var path: FilePath
    var content: String

    func run() async throws {
        Logger.currentScope?.info("creating file: \(path.lastComponent?.string ?? "<unknown>")")

        try createDirectory(at: path.directory())

        try writeContent(content, to: path)
    }

    private func createDirectory(at path: FilePath) throws {
        let manager = FileManager.default

        var isDirectory: ObjCBool = false
        let exists = manager.fileExists(atPath: path.string, isDirectory: &isDirectory)
        if exists && isDirectory.boolValue {
            return
        }
        if !exists {
            try manager.createDirectory(atPath: path.string, withIntermediateDirectories: true)
            return
        }
        if !isDirectory.boolValue {
            throw ValidationError("'\(path.string)' is not a directory")
        }
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
