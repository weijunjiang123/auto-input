import Foundation

public struct AppInputRule: Codable, Equatable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var appName: String
    public var inputSourceID: String
    public var inputSourceName: String
    public var forceEnglishPunctuation: Bool

    public init(
        bundleID: String,
        appName: String,
        inputSourceID: String,
        inputSourceName: String,
        forceEnglishPunctuation: Bool
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.inputSourceID = inputSourceID
        self.inputSourceName = inputSourceName
        self.forceEnglishPunctuation = forceEnglishPunctuation
    }

    public func matchesSearch(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return appName.localizedCaseInsensitiveContains(normalized)
            || bundleID.localizedCaseInsensitiveContains(normalized)
    }
}

public struct AutoInputConfig: Codable, Equatable {
    public var schemaVersion: Int
    public var defaultInputSourceID: String?
    public var defaultInputSourceName: String?
    public var isEnabled: Bool
    public var hasOpenedSettings: Bool
    public var rules: [AppInputRule]

    public init(
        schemaVersion: Int = 1,
        defaultInputSourceID: String?,
        defaultInputSourceName: String?,
        isEnabled: Bool,
        hasOpenedSettings: Bool,
        rules: [AppInputRule]
    ) {
        self.schemaVersion = schemaVersion
        self.defaultInputSourceID = defaultInputSourceID
        self.defaultInputSourceName = defaultInputSourceName
        self.isEnabled = isEnabled
        self.hasOpenedSettings = hasOpenedSettings
        self.rules = rules
    }

    public static var empty: AutoInputConfig {
        AutoInputConfig(
            defaultInputSourceID: nil,
            defaultInputSourceName: nil,
            isEnabled: true,
            hasOpenedSettings: false,
            rules: []
        )
    }

    public func targetInputSourceID(for bundleID: String?) -> String? {
        guard isEnabled else { return nil }
        guard let bundleID else { return defaultInputSourceID }
        return rules.first { $0.bundleID == bundleID }?.inputSourceID ?? defaultInputSourceID
    }

    public mutating func upsertRule(_ rule: AppInputRule) {
        if let index = rules.firstIndex(where: { $0.bundleID == rule.bundleID }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }
}

public struct InputSourceDescriptor: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var isASCII: Bool

    public init(id: String, name: String, isASCII: Bool) {
        self.id = id
        self.name = name
        self.isASCII = isASCII
    }
}
