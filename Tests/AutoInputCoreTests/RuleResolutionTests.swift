import Foundation
import AutoInputCore

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

func expectNil<T>(_ actual: T?, _ message: String) {
    if actual != nil {
        fatalError("\(message): expected nil, got \(String(describing: actual))")
    }
}

func testExactBundleRuleWinsOverDefaultInputSource() {
    let config = AutoInputConfig(
        defaultInputSourceID: "com.apple.keylayout.US",
        defaultInputSourceName: "ABC",
        isEnabled: true,
        hasOpenedSettings: false,
        rules: [
            AppInputRule(
                bundleID: "com.microsoft.VSCode",
                appName: "Code",
                inputSourceID: "com.apple.inputmethod.SCIM.ITABC",
                inputSourceName: "简体拼音",
                forceEnglishPunctuation: false
            )
        ]
    )

    let target = config.targetInputSourceID(for: "com.microsoft.VSCode")

    expectEqual(target, "com.apple.inputmethod.SCIM.ITABC", "exact rule should win")
}

func testDefaultInputSourceIsUsedWhenNoRuleMatches() {
    let config = AutoInputConfig(
        defaultInputSourceID: "com.apple.keylayout.US",
        defaultInputSourceName: "ABC",
        isEnabled: true,
        hasOpenedSettings: false,
        rules: []
    )

    let target = config.targetInputSourceID(for: "com.apple.Terminal")

    expectEqual(target, "com.apple.keylayout.US", "default source should be used")
}

func testDisabledConfigDoesNotReturnATarget() {
    let config = AutoInputConfig(
        defaultInputSourceID: "com.apple.keylayout.US",
        defaultInputSourceName: "ABC",
        isEnabled: false,
        hasOpenedSettings: true,
        rules: [
            AppInputRule(
                bundleID: "com.apple.Terminal",
                appName: "Terminal",
                inputSourceID: "com.apple.keylayout.US",
                inputSourceName: "ABC",
                forceEnglishPunctuation: true
            )
        ]
    )

    let target = config.targetInputSourceID(for: "com.apple.Terminal")

    expectNil(target, "disabled config should not switch")
}

func testConfigStoreRoundTripsJSON() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = ConfigStore(configDirectory: directory)
    let config = AutoInputConfig(
        defaultInputSourceID: "com.apple.keylayout.US",
        defaultInputSourceName: "ABC",
        isEnabled: true,
        hasOpenedSettings: true,
        rules: [
            AppInputRule(
                bundleID: "com.googlecode.iterm2",
                appName: "iTerm2",
                inputSourceID: "com.apple.keylayout.US",
                inputSourceName: "ABC",
                forceEnglishPunctuation: true
            )
        ]
    )

    try store.save(config)
    let loaded = try store.load()

    expectEqual(loaded, config, "config should round trip through JSON")
}

func testLegacyConfigDefaultsToSystemAppearance() throws {
    let json = """
    {
      "schemaVersion": 1,
      "defaultInputSourceID": null,
      "defaultInputSourceName": null,
      "isEnabled": true,
      "hasOpenedSettings": true,
      "rules": []
    }
    """

    let data = Data(json.utf8)
    let config = try JSONDecoder().decode(AutoInputConfig.self, from: data)

    expectEqual(config.appearanceMode, .system, "missing appearance mode should default to system")
}

func testConfigStoreRoundTripsAppearanceMode() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = ConfigStore(configDirectory: directory)
    let config = AutoInputConfig(
        defaultInputSourceID: nil,
        defaultInputSourceName: nil,
        isEnabled: true,
        hasOpenedSettings: true,
        appearanceMode: .light,
        rules: []
    )

    try store.save(config)
    let loaded = try store.load()

    expectEqual(loaded.appearanceMode, .light, "appearance mode should round trip through JSON")
    expectEqual(loaded, config, "config should round trip with appearance mode")
}

func testUpsertingRuleReplacesExistingBundleRule() {
    var config = AutoInputConfig(
        defaultInputSourceID: nil,
        defaultInputSourceName: nil,
        isEnabled: true,
        hasOpenedSettings: true,
        rules: [
            AppInputRule(
                bundleID: "com.apple.Terminal",
                appName: "Terminal",
                inputSourceID: "old",
                inputSourceName: "Old",
                forceEnglishPunctuation: false
            )
        ]
    )

    config.upsertRule(AppInputRule(
        bundleID: "com.apple.Terminal",
        appName: "Terminal",
        inputSourceID: "new",
        inputSourceName: "New",
        forceEnglishPunctuation: true
    ))

    expectEqual(config.rules.count, 1, "upsert should not duplicate bundle rules")
    expectEqual(config.rules[0].inputSourceID, "new", "upsert should replace input source")
    expectEqual(config.rules[0].forceEnglishPunctuation, true, "upsert should replace punctuation flag")
}

func testRuleSearchMatchesNameBundleIDAndEmptyQuery() {
    let rule = AppInputRule(
        bundleID: "com.microsoft.VSCode",
        appName: "Code",
        inputSourceID: "abc",
        inputSourceName: "ABC",
        forceEnglishPunctuation: true
    )

    expectEqual(rule.matchesSearch("code"), true, "search should match app name case-insensitively")
    expectEqual(rule.matchesSearch("microsoft"), true, "search should match bundle id")
    expectEqual(rule.matchesSearch("  "), true, "empty search should match every rule")
    expectEqual(rule.matchesSearch("terminal"), false, "unrelated search should not match")
}

func testRunningApplicationCandidatesFilterSelfAndMissingBundleIDs() {
    let candidates = RunningApplicationCandidate.candidates(
        from: [
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.apple.Terminal",
                localizedName: "Terminal",
                bundleName: nil,
                bundlePath: "/System/Applications/Utilities/Terminal.app",
                isRegularApplication: true
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "",
                localizedName: "No Bundle",
                bundleName: nil
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: nil,
                localizedName: "Nil Bundle",
                bundleName: nil
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.AutoInput",
                localizedName: "AutoInput",
                bundleName: nil
            )
        ],
        excludingBundleID: "com.example.AutoInput"
    )

    expectEqual(candidates.count, 1, "only configurable external apps should remain")
    expectEqual(candidates[0].bundleID, "com.apple.Terminal", "terminal should remain")
}

func testRunningApplicationCandidatesOnlyIncludeTopLevelRegularApps() {
    let candidates = RunningApplicationCandidate.candidates(
        from: [
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.googlecode.iterm2",
                localizedName: "iTerm2",
                bundleName: nil,
                bundlePath: "/Applications/iTerm.app",
                isRegularApplication: true
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.raycast.macos.Renderer",
                localizedName: "Raycast Web Content",
                bundleName: nil,
                bundlePath: "/Applications/Raycast.app/Contents/Frameworks/Raycast Helper (Renderer).app",
                isRegularApplication: true
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.apple.LocalAuthenticationRemoteService",
                localizedName: "LocalAuthenticationRemoteService",
                bundleName: nil,
                bundlePath: "/System/Library/CoreServices/LocalAuthenticationRemoteService.app",
                isRegularApplication: false
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.NoBundlePath",
                localizedName: "No Bundle Path",
                bundleName: nil,
                bundlePath: nil,
                isRegularApplication: true
            )
        ],
        excludingBundleID: nil
    )

    expectEqual(candidates.map(\.bundleID), ["com.googlecode.iterm2"], "only top-level regular apps should remain")
}

func testRunningApplicationCandidatesCollapseDuplicatesAndUseBestName() {
    let candidates = RunningApplicationCandidate.candidates(
        from: [
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.Editor",
                localizedName: nil,
                bundleName: "Editor",
                bundlePath: "/Applications/Editor.app",
                isRegularApplication: true
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.Editor",
                localizedName: "Editor Pro",
                bundleName: "Editor",
                bundlePath: "/Applications/Editor.app",
                isRegularApplication: true
            )
        ],
        excludingBundleID: nil
    )

    expectEqual(candidates.count, 1, "duplicate bundle ids should collapse")
    expectEqual(candidates[0].appName, "Editor Pro", "localized names should replace weaker names")
}

func testRunningApplicationCandidatesSortByNameThenBundleID() {
    let candidates = RunningApplicationCandidate.candidates(
        from: [
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.ZedB",
                localizedName: "Zed",
                bundleName: nil,
                bundlePath: "/Applications/ZedB.app",
                isRegularApplication: true
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.Alpha",
                localizedName: "Alpha",
                bundleName: nil,
                bundlePath: "/Applications/Alpha.app",
                isRegularApplication: true
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.ZedA",
                localizedName: "Zed",
                bundleName: nil,
                bundlePath: "/Applications/ZedA.app",
                isRegularApplication: true
            )
        ],
        excludingBundleID: nil
    )

    expectEqual(candidates.map(\.bundleID), [
        "com.example.Alpha",
        "com.example.ZedA",
        "com.example.ZedB"
    ], "candidates should sort by display name then bundle id")
}

testExactBundleRuleWinsOverDefaultInputSource()
testDefaultInputSourceIsUsedWhenNoRuleMatches()
testDisabledConfigDoesNotReturnATarget()
try testConfigStoreRoundTripsJSON()
try testLegacyConfigDefaultsToSystemAppearance()
try testConfigStoreRoundTripsAppearanceMode()
testUpsertingRuleReplacesExistingBundleRule()
testRuleSearchMatchesNameBundleIDAndEmptyQuery()
testRunningApplicationCandidatesFilterSelfAndMissingBundleIDs()
testRunningApplicationCandidatesOnlyIncludeTopLevelRegularApps()
testRunningApplicationCandidatesCollapseDuplicatesAndUseBestName()
testRunningApplicationCandidatesSortByNameThenBundleID()
print("AutoInputCoreTests passed")
