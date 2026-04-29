# AutoInput Design

## Goal

AutoInput is a lightweight macOS menu bar app that switches the active input source when the foreground application changes. Its first version focuses on the common developer pain point: terminals, editors, and coding tools should open in English input without requiring manual Chinese/English toggling.

## Product Shape

The app runs as a menu bar utility. On first launch it opens a settings window; afterward it stays in the menu bar and works silently. The status menu exposes:

- Open Settings
- Enable or pause automatic switching
- Apply current app rule now
- Quit

## Rule Model

Rules are stored by application bundle identifier, not by display name. A rule contains:

- App bundle identifier
- App display name
- Optional app icon path metadata for display only
- Target input source identifier
- Human-readable input source name
- Force English punctuation flag, stored for future extension

If the foreground app has no rule, AutoInput applies the configured default input source when one is set. If neither a rule nor a default exists, AutoInput leaves the current input source unchanged.

## Input Source Switching

AutoInput reads enabled macOS keyboard input sources through Carbon Text Input Source Services and switches sources with `TISSelectInputSource`. The first version supports keyboard input sources that are already enabled in System Settings.

## UI

The settings window uses a dark, native AppKit interface inspired by the reference image:

- A focused "按应用切换" title. Position-based switching is not shown in this version because it is out of scope and would require an accessibility-permission workflow.
- Table-like rows showing icon, application name, input source picker, and force English punctuation toggle.
- Add button that opens a system picker for selecting any `.app`, including apps that are not currently running.
- Remove button that deletes the selected rule.
- Default input source picker at the bottom.
- A compact status line for permission or switching errors.

The UI favors direct controls over explanatory text. It should feel like a focused macOS utility rather than a marketing page.

## Defaults

On first launch, AutoInput seeds rules for common developer apps when they are installed or running:

- Terminal
- iTerm2
- Visual Studio Code
- Cursor
- Codex

These rules default to the first English/ABC-like input source found on the machine.

## Persistence

Configuration is stored as JSON under Application Support:

`~/Library/Application Support/AutoInput/config.json`

The file is human-readable and versioned with a schema integer so future migrations are straightforward.

## Testing

The core rule resolution and configuration persistence are tested independently from AppKit. The app target is verified by compiling the Swift package and building a `.app` bundle with a local script.

## Delivery

The deliverable is:

- A source tree that can be built with Swift command line tools.
- `Scripts/build_app.sh` to produce `dist/AutoInput.app`.
- A ready-to-open `.app` bundle after verification.
