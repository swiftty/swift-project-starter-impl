import Foundation

struct Config: Codable {
    var project: Project
    var dependencies: [Dependency] = []
    var swiftSettings: [SwiftSetting] = []

    enum Project: Codable {
        case application(
            name: String,
            projectRoot: String,
            makefile: Makefile?,
            xcoddgen: XcodeGen?,
            resources: [File],
        )
        case library(
            resources: [File]
        )

        struct File: Codable {
            /// relative to projectRoot
            var filePath: String
            var content: String
        }

        private struct Application: Codable {
            var type = "application"
            var name: String
            var projectRoot: String
            var makefile: Makefile?
            var xcodegen: XcodeGen?
            var resources: [File]

            enum CodingKeys: String, CodingKey {
                case name
                case projectRoot
                case makefile = "Makefile"
                case xcodegen = "XcodeGen"
                case resources
            }
        }

        private struct Library: Codable {
            var type = "library"
            var resources: [File]
        }

        init(from decoder: any Decoder) throws {
            self = try decode(from: decoder, choices: [
                Application.to {
                    Self.application(
                        name: $0.name,
                        projectRoot: $0.projectRoot,
                        makefile: $0.makefile,
                        xcoddgen: $0.xcodegen,
                        resources: $0.resources
                    )
                },
                Library.to {
                    Self.library(resources: $0.resources)
                }
            ])
        }

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .application(let name, let projectRoot, let makefile, let xcodegen, let resources):
                let container = Application(
                    name: name,
                    projectRoot: projectRoot,
                    makefile: makefile,
                    xcodegen: xcodegen,
                    resources: resources
                )
                try container.encode(to: encoder)

            case .library(let resources):
                let container = Library(resources: resources)
                try container.encode(to: encoder)
            }
        }
    }

    struct Dependency: Codable {
        var url: String
        var from: String
    }

    enum SwiftSetting: Codable {
        case defaultIsolation(DefaultIsolationKey)
        case enableUpcomingFeature(String)
        case enableExperimentalFeature(String)

        enum DefaultIsolationKey: String, Codable {
            case MainActor
        }

        private struct DefaultIsolation: Codable {
            var defaultIsolation: DefaultIsolationKey
        }
        private struct EnableUpcomingFeature: Codable {
            var enableUpcomingFeature: String
        }
        private struct EnableExperimentalFeature: Codable {
            var enableExperimentalFeature: String
        }

        init(from decoder: any Decoder) throws {
            self = try decode(from: decoder, choices: [
                DefaultIsolation.to {
                    Self.defaultIsolation($0.defaultIsolation)
                },
                EnableUpcomingFeature.to {
                    Self.enableUpcomingFeature($0.enableUpcomingFeature)
                },
                EnableExperimentalFeature.to {
                    Self.enableExperimentalFeature($0.enableExperimentalFeature)
                }
            ])
        }

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .defaultIsolation(let value):
                let container = DefaultIsolation(defaultIsolation: value)
                try container.encode(to: encoder)

            case .enableUpcomingFeature(let value):
                let container = EnableUpcomingFeature(enableUpcomingFeature: value)
                try container.encode(to: encoder)

            case .enableExperimentalFeature(let value):
                let contaienr = EnableExperimentalFeature(enableExperimentalFeature: value)
                try contaienr.encode(to: encoder)
            }
        }
    }

    struct Makefile: Codable {
        var content: String
    }

    struct XcodeGen: Codable {
        var content: String
    }
}

private func decode<U>(
    from decoder: any Decoder,
    choices: [(any Decoder) throws -> U?],
) throws -> U {
    for choice in choices {
        if let result = try choice(decoder) {
            return result
        }
    }
    throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unsupported \(U.self) type")
    )
}

// helper for `decodeChoice`
private extension Decodable {
    static func to<U>(_ transform: @escaping (Self) -> U) -> (any Decoder) throws -> U? {
        return { decoder in
            do {
                return transform(try Self.init(from: decoder))
            } catch DecodingError.keyNotFound(let keys, let context) {
                print(keys, context)
                return nil
            }
        }
    }
}
