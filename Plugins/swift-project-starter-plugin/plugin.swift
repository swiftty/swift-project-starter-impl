import Foundation
import PackagePlugin

@main
struct Plugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let executableURL = try context.tool(named: "swift-project-starter").url
        let process = try Process.run(executableURL, arguments: arguments)
        process.waitUntilExit()

        guard process.terminationReason == .exit && process.terminationStatus == 0 else {
            let problem = "\(process.terminationReason): \(process.terminationStatus)"
            Diagnostics.error("invocation failed: \(problem)")
            return
        }
    }
}
