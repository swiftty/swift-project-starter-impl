import Foundation
import SystemPackage
import ArgumentParser

struct DefaultConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "default-config"
    )

    @OptionGroup
    var options: ProjectOption

    func run() async throws {
        let config = try options.asConfig()
        print(try config.toJSON())
    }
}

private extension Config {
    func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
