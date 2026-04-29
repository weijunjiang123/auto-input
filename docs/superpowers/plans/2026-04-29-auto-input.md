# AutoInput Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that switches input sources by foreground application.

**Architecture:** Use a Swift Package with a pure `AutoInputCore` library for config, rule resolution, and input source descriptors, plus an `AutoInput` executable target for AppKit status item, settings window, and Carbon input source switching. Package the executable into `dist/AutoInput.app` with a shell script.

**Tech Stack:** Swift 6.3, Swift Package Manager, AppKit, Carbon Text Input Source Services, XCTest.

---

## File Structure

- `Package.swift`: Swift package definition.
- `Sources/AutoInputCore/AppRule.swift`: Codable rule, app metadata, config, and resolver types.
- `Sources/AutoInputCore/ConfigStore.swift`: JSON load/save under Application Support.
- `Sources/AutoInput/InputSourceManager.swift`: Carbon input source discovery and switching.
- `Sources/AutoInput/AppMonitor.swift`: Foreground app notification handling.
- `Sources/AutoInput/AppDelegate.swift`: Status item, first-launch behavior, and coordinator wiring.
- `Sources/AutoInput/SettingsWindowController.swift`: Native AppKit settings UI.
- `Sources/AutoInput/main.swift`: App entry point.
- `Tests/AutoInputCoreTests/RuleResolutionTests.swift`: Rule resolution and persistence tests.
- `Scripts/build_app.sh`: Build and assemble `dist/AutoInput.app`.

## Tasks

### Task 1: Core Rule Model

**Files:**
- Create: `Package.swift`
- Create: `Tests/AutoInputCoreTests/RuleResolutionTests.swift`
- Create: `Sources/AutoInputCore/AppRule.swift`
- Create: `Sources/AutoInputCore/ConfigStore.swift`

- [ ] Write failing tests for rule lookup, default fallback, and JSON round trip.
- [ ] Run `swift test --filter AutoInputCoreTests` and confirm the missing module/type failures.
- [ ] Implement the Codable model and config store.
- [ ] Re-run `swift test --filter AutoInputCoreTests` and confirm tests pass.

### Task 2: macOS Integration Layer

**Files:**
- Create: `Sources/AutoInput/InputSourceManager.swift`
- Create: `Sources/AutoInput/AppMonitor.swift`

- [ ] Implement enabled input source listing through Carbon.
- [ ] Implement target input source selection by identifier.
- [ ] Implement foreground application monitoring with `NSWorkspace.didActivateApplicationNotification`.
- [ ] Compile with `swift build`.

### Task 3: Menu Bar App and Settings UI

**Files:**
- Create: `Sources/AutoInput/main.swift`
- Create: `Sources/AutoInput/AppDelegate.swift`
- Create: `Sources/AutoInput/SettingsWindowController.swift`

- [ ] Implement a menu bar status item with settings, pause/resume, apply-now, and quit actions.
- [ ] Implement first-launch settings window behavior.
- [ ] Implement a dark AppKit settings window with rule rows, source popups, toggles, add-current-app, remove-selected, and default source picker.
- [ ] Persist UI changes immediately through `ConfigStore`.
- [ ] Compile with `swift build`.

### Task 4: Packaging and Verification

**Files:**
- Create: `Scripts/build_app.sh`

- [ ] Build release executable with SwiftPM.
- [ ] Assemble `dist/AutoInput.app` with `Info.plist`, `MacOS/AutoInput`, and `Resources`.
- [ ] Run `swift test`.
- [ ] Run `Scripts/build_app.sh`.
- [ ] Confirm `dist/AutoInput.app/Contents/MacOS/AutoInput` exists and is executable.
