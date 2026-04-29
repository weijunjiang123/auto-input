# Running App Rule Picker Design

## Goal

AutoInput should keep the saved rule list as the source of truth, while making it easier to add rules for applications that are currently running. The existing file picker remains available for adding applications that are not running.

## User Experience

The rules table continues to show only saved rules. The `+` button opens a compact add menu instead of opening the file picker immediately.

The menu contains:

- A sorted list of currently running applications that can be configured.
- A separator.
- A `Choose Application File...` item that opens the current `.app` picker.

Choosing a running application creates or updates a saved rule for that application, then selects it in the rules list. Choosing the file item uses the existing `.app` selection flow.

## Running Application List

AutoInput builds the running application list from `NSWorkspace.shared.runningApplications`.

The list includes applications that:

- Have a non-empty bundle identifier.
- Are not AutoInput itself.
- Have a user-facing name from `localizedName`, bundle metadata, or bundle id fallback.

The list is sorted by localized app name, then bundle id. Duplicate bundle ids are collapsed into one item.

## Rule Creation

Adding a running application uses the same defaults as adding a file:

- Prefer the configured default input source when it still exists.
- Otherwise prefer the first English or ASCII input source.
- Otherwise use the first available input source.

Rules remain keyed by bundle id. If a rule already exists, AutoInput updates the display name and keeps the rule unique instead of adding a duplicate row. The selected rule changes to the added or updated bundle id.

## Architecture

The persisted `AutoInputConfig` schema does not change.

`AutoInputCore` receives a small pure helper for turning raw running app descriptors into menu-ready candidates. This helper can be tested without AppKit:

- Filter entries with missing bundle ids.
- Exclude AutoInput.
- Collapse duplicate bundle ids.
- Sort the remaining applications consistently.

The AppKit target converts `NSRunningApplication` values into those raw descriptors, displays them in the add menu, and reuses AppDelegate's rule creation path.

## Error Handling

If no input source is available, AutoInput shows the existing status message path and does not add a rule.

If no running applications are available after filtering, the menu shows a disabled `No Running Applications` item and still offers `Choose Application File...`.

## Testing

Core tests cover the candidate-building helper:

- Missing bundle ids are ignored.
- AutoInput's own bundle id is excluded.
- Duplicate bundle ids collapse to one candidate.
- Results are sorted by name and bundle id.

Existing rule tests continue to cover upsert behavior and JSON persistence. The app target is verified by building the Swift package.
