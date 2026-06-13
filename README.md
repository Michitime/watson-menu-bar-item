# WatsonMenuBar

A standalone native macOS menu bar companion for the Watson CLI time tracker.
It does not replace Watson or recreate reporting screens. It keeps the common
daily actions close at hand: check status, start a frame, stop a frame, and
refresh.

## Features

- Menu bar only app built with `NSStatusItem`, a transient `NSPopover`, and SwiftUI content
- Native macOS agent app with no Dock icon
- Uses `Process` and `Pipe` to call the Watson CLI
- Detects `watson` in PATH, `/opt/homebrew/bin/watson`, and `/usr/local/bin/watson`
- Supports `watson status`, `watson start <project> [tags...]`, `watson stop`, current-day log summary, and current work-week summaries
- Shows running or idle state, current project, tags, and elapsed text
- Shows the active project and a live elapsed counter in the menu bar by default
- Offers a dropdown switch to hide or show the menu bar timer
- Offers a dropdown switch to hide or show the active project in the menu bar
- Offers an `Auto Stop` setting to stop the active Watson frame at a chosen time today
- Shows a compact `Today` list from the current day's Watson log
- Shows a collapsible `Work Week` list from Monday through today, capped at Friday
- Persists the last project and tags with `AppStorage`
- Offers a dropdown switch to launch the app at login
- Detects when a Homebrew-installed app bundle has changed on disk and offers a restart
- Refreshes on launch, after start/stop actions, on manual refresh, and every 1 minute

## Build

1. Install Watson separately, for example with `brew install watson`.
2. Open `WatsonMenuBar.xcodeproj` in Xcode.
3. Run the `WatsonMenuBar` scheme.

The app targets macOS 15.0 or later and runs as a menu bar utility via
`LSUIElement`.

## File Structure

- `WatsonMenuBar/WatsonMenuBarApp.swift`: App entry, AppKit status item, and transient SwiftUI popover
- `WatsonMenuBar/Models/WatsonStatus.swift`: Running, idle, unavailable, and error state model
- `WatsonMenuBar/Services/WatsonService.swift`: Watson executable discovery and CLI command execution
- `WatsonMenuBar/ViewModels/MenuBarViewModel.swift`: Refresh loop, menu bar label state, and actions
- `WatsonMenuBar/Views/MenuBarContentView.swift`: Compact SwiftUI companion UI

## Notes

- The UI is intentionally small and focused on quick daily use.
- Watson stays the source of truth. This app only talks to it through the CLI.
