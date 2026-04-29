# Running App Rule Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `+` menu that can create rules from currently running applications while preserving the existing `.app` file picker.

**Architecture:** Keep persisted rule data unchanged. Add a pure `RunningApplicationCandidate` helper in `AutoInputCore` for filtering, de-duplicating, and sorting running app descriptors; have the AppKit target convert `NSRunningApplication` into those descriptors and present them from the settings window add button.

**Tech Stack:** Swift 6, AppKit, AutoInputCore executable tests, SwiftPM.

---

## File Structure

- Modify `Sources/AutoInputCore/AppRule.swift`: add `RunningApplicationCandidate` and its pure candidate builder.
- Modify `Tests/AutoInputCoreTests/RuleResolutionTests.swift`: add tests for filtering, duplicate collapse, self exclusion, sorting, and display-name fallback.
- Modify `Sources/AutoInput/SettingsWindowController.swift`: replace direct add button file picker action with a menu that contains running apps and the existing file picker action.
- Modify `Sources/AutoInput/AppDelegate.swift`: provide running app candidates and add rules from selected candidates.

### Task 1: Core Running App Candidate Helper

**Files:**
- Modify: `Tests/AutoInputCoreTests/RuleResolutionTests.swift`
- Modify: `Sources/AutoInputCore/AppRule.swift`

- [ ] **Step 1: Write the failing tests**

Append these test functions to `Tests/AutoInputCoreTests/RuleResolutionTests.swift` before the existing bottom-level test calls:

```swift
func testRunningApplicationCandidatesFilterSelfAndMissingBundleIDs() {
    let candidates = RunningApplicationCandidate.candidates(
        from: [
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.apple.Terminal",
                localizedName: "Terminal",
                bundleName: nil
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

func testRunningApplicationCandidatesCollapseDuplicatesAndUseBestName() {
    let candidates = RunningApplicationCandidate.candidates(
        from: [
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.Editor",
                localizedName: nil,
                bundleName: "Editor"
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.Editor",
                localizedName: "Editor Pro",
                bundleName: "Editor"
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
                bundleName: nil
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.Alpha",
                localizedName: "Alpha",
                bundleName: nil
            ),
            RunningApplicationCandidate.RawApplication(
                bundleID: "com.example.ZedA",
                localizedName: "Zed",
                bundleName: nil
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
```

Add these calls at the bottom:

```swift
testRunningApplicationCandidatesFilterSelfAndMissingBundleIDs()
testRunningApplicationCandidatesCollapseDuplicatesAndUseBestName()
testRunningApplicationCandidatesSortByNameThenBundleID()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `env SWIFTPM_CACHE_PATH=/Users/weijun/Project/auto-input/.build/swiftpm-cache CLANG_MODULE_CACHE_PATH=/Users/weijun/Project/auto-input/.build/module-cache swift run AutoInputCoreTests`

Expected: FAIL to compile with `cannot find 'RunningApplicationCandidate' in scope`.

- [ ] **Step 3: Add the minimal core implementation**

Append this type to `Sources/AutoInputCore/AppRule.swift`:

```swift
public struct RunningApplicationCandidate: Equatable, Identifiable {
    public struct RawApplication: Equatable {
        public var bundleID: String?
        public var localizedName: String?
        public var bundleName: String?

        public init(bundleID: String?, localizedName: String?, bundleName: String?) {
            self.bundleID = bundleID
            self.localizedName = localizedName
            self.bundleName = bundleName
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
        var byBundleID: [String: RunningApplicationCandidate] = [:]

        for application in applications {
            guard let bundleID = clean(application.bundleID), bundleID != excludedBundleID else {
                continue
            }

            let appName = clean(application.localizedName)
                ?? clean(application.bundleName)
                ?? bundleID
            let candidate = RunningApplicationCandidate(bundleID: bundleID, appName: appName)

            if let existing = byBundleID[bundleID] {
                byBundleID[bundleID] = strongest(existing, candidate)
            } else {
                byBundleID[bundleID] = candidate
            }
        }

        return byBundleID.values.sorted { left, right in
            let nameComparison = left.appName.localizedCaseInsensitiveCompare(right.appName)
            if nameComparison == .orderedSame {
                return left.bundleID.localizedCaseInsensitiveCompare(right.bundleID) == .orderedAscending
            }
            return nameComparison == .orderedAscending
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func strongest(
        _ existing: RunningApplicationCandidate,
        _ candidate: RunningApplicationCandidate
    ) -> RunningApplicationCandidate {
        if existing.appName == existing.bundleID, candidate.appName != candidate.bundleID {
            return candidate
        }
        return existing
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `env SWIFTPM_CACHE_PATH=/Users/weijun/Project/auto-input/.build/swiftpm-cache CLANG_MODULE_CACHE_PATH=/Users/weijun/Project/auto-input/.build/module-cache swift run AutoInputCoreTests`

Expected: PASS with `AutoInputCoreTests passed`.

### Task 2: Settings Add Menu

**Files:**
- Modify: `Sources/AutoInput/SettingsWindowController.swift`

- [ ] **Step 1: Update the settings controller initializer contract**

Change stored callbacks to:

```swift
private let runningApplications: () -> [RunningApplicationCandidate]
private let onAddRunningApplication: (RunningApplicationCandidate) -> Void
private let onAddApplication: (URL) -> Void
```

Change the initializer parameters to include the new callbacks:

```swift
runningApplications: @escaping () -> [RunningApplicationCandidate],
onAddRunningApplication: @escaping (RunningApplicationCandidate) -> Void,
onAddApplication: @escaping (URL) -> Void
```

Assign them in `init`:

```swift
self.runningApplications = runningApplications
self.onAddRunningApplication = onAddRunningApplication
self.onAddApplication = onAddApplication
```

- [ ] **Step 2: Replace the add button action**

In `makeRulesToolbar()`, change:

```swift
let addButton = NSButton(title: "", target: self, action: #selector(chooseApplication))
```

to:

```swift
let addButton = NSButton(title: "", target: self, action: #selector(showAddApplicationMenu(_:)))
```

Change the tooltip to:

```swift
addButton.toolTip = "从正在运行的应用或应用文件添加输入法规则"
```

- [ ] **Step 3: Add the running app menu action**

Add this method near the existing `chooseApplication()` method:

```swift
@objc private func showAddApplicationMenu(_ sender: NSButton) {
    let menu = NSMenu()
    let applications = runningApplications()

    if applications.isEmpty {
        let emptyItem = NSMenuItem(title: "没有正在运行的应用", action: nil, keyEquivalent: "")
        emptyItem.isEnabled = false
        menu.addItem(emptyItem)
    } else {
        for application in applications {
            let item = NSMenuItem(
                title: application.appName,
                action: #selector(addRunningApplicationFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = application.bundleID
            item.toolTip = application.bundleID
            item.image = NSWorkspace.shared.icon(forFile: appPathForBundleID(application.bundleID) ?? "")
            menu.addItem(item)
        }
    }

    menu.addItem(.separator())

    let chooseFile = NSMenuItem(
        title: "选择应用文件...",
        action: #selector(chooseApplication),
        keyEquivalent: ""
    )
    chooseFile.target = self
    chooseFile.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "选择应用文件")
    menu.addItem(chooseFile)

    NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: sender)
}
```

- [ ] **Step 4: Add the menu selection handler and shared app path helper**

Add this method near `showAddApplicationMenu(_:)`:

```swift
@objc private func addRunningApplicationFromMenu(_ sender: NSMenuItem) {
    guard let bundleID = sender.representedObject as? String,
          let application = runningApplications().first(where: { $0.bundleID == bundleID }) else {
        return
    }
    onAddRunningApplication(application)
}
```

Add this file-level helper before `RuleRowView`:

```swift
private func appPathForBundleID(_ bundleID: String) -> String? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
}
```

Remove the private `appPathForBundleID(_:)` method from inside `RuleRowView`.

### Task 3: AppDelegate Wiring

**Files:**
- Modify: `Sources/AutoInput/AppDelegate.swift`

- [ ] **Step 1: Pass running app callbacks into settings**

In `openSettings(_:)`, change the controller initialization to include:

```swift
runningApplications: { [weak self] in self?.runningApplicationCandidates() ?? [] },
onAddRunningApplication: { [weak self] application in self?.addRunningApplicationRule(application) },
```

between `onChange` and `onAddApplication`.

- [ ] **Step 2: Add running app candidate conversion**

Add this method near `addApplicationRule(at:)`:

```swift
private func runningApplicationCandidates() -> [RunningApplicationCandidate] {
    let rawApplications = NSWorkspace.shared.runningApplications.map { application in
        RunningApplicationCandidate.RawApplication(
            bundleID: application.bundleIdentifier,
            localizedName: application.localizedName,
            bundleName: application.bundleURL.flatMap { Bundle(url: $0) }?.object(forInfoDictionaryKey: "CFBundleName") as? String
        )
    }

    return RunningApplicationCandidate.candidates(
        from: rawApplications,
        excludingBundleID: Bundle.main.bundleIdentifier
    )
}
```

- [ ] **Step 3: Extract shared rule creation**

Add this method near `addApplicationRule(at:)`:

```swift
private func addRule(bundleID: String, appName: String, forceEnglishPunctuation: Bool) {
    let fallback = inputSources.first { $0.id == config.defaultInputSourceID }
        ?? inputSourceManager.preferredEnglishSource(from: inputSources)
        ?? inputSources.first

    guard let source = fallback else {
        statusMessage = "没有找到可用输入法。"
        settingsWindowController?.statusMessage = statusMessage
        return
    }

    config.upsertRule(AppInputRule(
        bundleID: bundleID,
        appName: appName,
        inputSourceID: source.id,
        inputSourceName: source.name,
        forceEnglishPunctuation: forceEnglishPunctuation
    ))
    statusMessage = "已添加：\(appName)"
    saveConfig()
    settingsWindowController?.selectRule(bundleID: bundleID)
    settingsWindowController?.reload(config: config)
}
```

Update `addApplicationRule(at:)` to call:

```swift
addRule(bundleID: bundleID, appName: appName, forceEnglishPunctuation: false)
```

instead of duplicating fallback and upsert logic.

Add this running-app entry point:

```swift
private func addRunningApplicationRule(_ application: RunningApplicationCandidate) {
    addRule(
        bundleID: application.bundleID,
        appName: application.appName,
        forceEnglishPunctuation: false
    )
}
```

- [ ] **Step 4: Add selection API to settings controller**

In `Sources/AutoInput/SettingsWindowController.swift`, add:

```swift
func selectRule(bundleID: String) {
    selectedBundleID = bundleID
}
```

near `reload(config:)`.

### Task 4: Verification

**Files:**
- No source changes expected.

- [ ] **Step 1: Run core tests**

Run: `env SWIFTPM_CACHE_PATH=/Users/weijun/Project/auto-input/.build/swiftpm-cache CLANG_MODULE_CACHE_PATH=/Users/weijun/Project/auto-input/.build/module-cache swift run AutoInputCoreTests`

Expected: PASS with `AutoInputCoreTests passed`.

- [ ] **Step 2: Build package**

Run: `env SWIFTPM_CACHE_PATH=/Users/weijun/Project/auto-input/.build/swiftpm-cache CLANG_MODULE_CACHE_PATH=/Users/weijun/Project/auto-input/.build/module-cache swift build`

Expected: PASS with no Swift compiler errors.

- [ ] **Step 3: Build app bundle**

Run: `Scripts/build_app.sh`

Expected: PASS and produce `dist/AutoInput.app`.
