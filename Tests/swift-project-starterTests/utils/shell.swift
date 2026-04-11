import Foundation

let fixturesDirectory = URL(filePath: #filePath)
    .deletingLastPathComponent()
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

@discardableResult
func shell(
    _ launchPath: String,
    _ arguments: String...,
    currentDirectoryURL: URL? = nil,
    stdout: Any? = nil,
    stderr: Any? = nil,
) throws -> Process {
    try shell(
        URL(filePath: "/usr/bin/env"), [launchPath] + arguments,
        currentDirectoryURL: currentDirectoryURL,
        stdout: stdout, stderr: stderr,
    )
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
        stdout: stdout, stderr: stderr,
    )
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
