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

public enum AppAppearanceMode: String, Codable, CaseIterable {
    case system
    case light
    case dark
}

public struct AutoInputConfig: Codable, Equatable {
    public var schemaVersion: Int
    public var defaultInputSourceID: String?
    public var defaultInputSourceName: String?
    public var isEnabled: Bool
    public var hasOpenedSettings: Bool
    public var appearanceMode: AppAppearanceMode
    public var rules: [AppInputRule]

    public init(
        schemaVersion: Int = 1,
        defaultInputSourceID: String?,
        defaultInputSourceName: String?,
        isEnabled: Bool,
        hasOpenedSettings: Bool,
        appearanceMode: AppAppearanceMode = .system,
        rules: [AppInputRule]
    ) {
        self.schemaVersion = schemaVersion
        self.defaultInputSourceID = defaultInputSourceID
        self.defaultInputSourceName = defaultInputSourceName
        self.isEnabled = isEnabled
        self.hasOpenedSettings = hasOpenedSettings
        self.appearanceMode = appearanceMode
        self.rules = rules
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case defaultInputSourceID
        case defaultInputSourceName
        case isEnabled
        case hasOpenedSettings
        case appearanceMode
        case rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        defaultInputSourceID = try container.decodeIfPresent(String.self, forKey: .defaultInputSourceID)
        defaultInputSourceName = try container.decodeIfPresent(String.self, forKey: .defaultInputSourceName)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        hasOpenedSettings = try container.decodeIfPresent(Bool.self, forKey: .hasOpenedSettings) ?? false
        appearanceMode = try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system
        rules = try container.decodeIfPresent([AppInputRule].self, forKey: .rules) ?? []
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

public struct RunningApplicationCandidate: Equatable, Identifiable {
    public struct RawApplication: Equatable {
        public var bundleID: String?
        public var localizedName: String?
        public var bundleName: String?
        public var bundlePath: String?
        public var isRegularApplication: Bool

        public init(
            bundleID: String?,
            localizedName: String?,
            bundleName: String?,
            bundlePath: String? = nil,
            isRegularApplication: Bool = true
        ) {
            self.bundleID = bundleID
            self.localizedName = localizedName
            self.bundleName = bundleName
            self.bundlePath = bundlePath
            self.isRegularApplication = isRegularApplication
        }
    }

    public var id: String { bundleID }
    public var bundleID: String
    public var appName: String

    public init(bundleID: String, appName: String) {
        self.bundleID = bundleID
        self.appName = appName
    }

    public static func candidates(
        from applications: [RawApplication],
        excludingBundleID excludedBundleID: String?
    ) -> [RunningApplicationCandidate] {
        var byBundleID: [String: (candidate: RunningApplicationCandidate, namePriority: Int)] = [:]

        for application in applications {
            guard let bundleID = clean(application.bundleID),
                  bundleID != excludedBundleID,
                  isVisibleTopLevelApplication(application) else {
                continue
            }

            let name = bestName(for: application, bundleID: bundleID)
            let candidate = RunningApplicationCandidate(bundleID: bundleID, appName: name.value)

            if let existing = byBundleID[bundleID] {
                if name.priority > existing.namePriority {
                    byBundleID[bundleID] = (candidate, name.priority)
                }
            } else {
                byBundleID[bundleID] = (candidate, name.priority)
            }
        }

        return byBundleID.values
            .map(\.candidate)
            .sorted { left, right in
                let nameComparison = left.appName.localizedCaseInsensitiveCompare(right.appName)
                if nameComparison == .orderedSame {
                    return left.bundleID.localizedCaseInsensitiveCompare(right.bundleID) == .orderedAscending
                }
                return nameComparison == .orderedAscending
        }
    }

    private static func isVisibleTopLevelApplication(_ application: RawApplication) -> Bool {
        guard application.isRegularApplication,
              let bundlePath = clean(application.bundlePath),
              bundlePath.hasSuffix(".app"),
              !bundlePath.contains(".app/Contents/") else {
            return false
        }
        return true
    }

    private static func bestName(for application: RawApplication, bundleID: String) -> (value: String, priority: Int) {
        if let localizedName = clean(application.localizedName) {
            return (localizedName, 2)
        }
        if let bundleName = clean(application.bundleName) {
            return (bundleName, 1)
        }
        return (bundleID, 0)
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
