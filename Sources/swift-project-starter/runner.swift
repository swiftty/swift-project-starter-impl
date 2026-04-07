import ArgumentParser
import Logging

private let bootstrap = { @Sendable in
    LoggingSystem.bootstrap { label in
        SimpleLogHandler(label: label)
    }
    return { @Sendable in }
}()

@main
struct Runner: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [
            InitCommand.self,
            DefaultConfigCommand.self,
        ]
    )

    init() {
        bootstrap()
    }
}

private struct SimpleLogHandler: LogHandler {
    var label: String
    var logLevel: Logger.Level = .trace
    var metadata: Logger.Metadata = .init()

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }

    func log(event: LogEvent) {
        print("\(emoji(event.level)) : \(event.message), in [\(label)]")
    }

    private func emoji(_ value: Logger.Level) -> String {
        switch value {
        case .trace: return "🔍"
        case .debug: return "🐛"
        case .info: return "✅"
        case .notice: return "📌"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🚨"
        }
    }
}
