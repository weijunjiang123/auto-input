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

testExactBundleRuleWinsOverDefaultInputSource()
testDefaultInputSourceIsUsedWhenNoRuleMatches()
testDisabledConfigDoesNotReturnATarget()
try testConfigStoreRoundTripsJSON()
testUpsertingRuleReplacesExistingBundleRule()
testRuleSearchMatchesNameBundleIDAndEmptyQuery()
print("AutoInputCoreTests passed")
