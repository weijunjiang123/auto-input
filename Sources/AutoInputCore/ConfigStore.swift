import Foundation

public final class ConfigStore {
    public let configDirectory: URL
    public let configURL: URL

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(configDirectory: URL? = nil) {
        let directory = configDirectory ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AutoInput", isDirectory: true)

        self.configDirectory = directory
        self.configURL = directory.appendingPathComponent("config.json")

        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> AutoInputConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: configURL)
        return try decoder.decode(AutoInputConfig.self, from: data)
    }

    public func save(_ config: AutoInputConfig) throws {
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(config)
        try data.write(to: configURL, options: [.atomic])
    }
}
