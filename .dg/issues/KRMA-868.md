---
id: KRMA-868
title: Remember the main window size and position between launches
type: task
status: backlog
priority: low
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T19:31:25.736Z
updated: 2026-10-10T19:31:26.101Z
blockers: []
order: zzzzx
board: product
---

## Objective

Remember the main window's size and position between launches. Today the window always opens at the `WindowGroup` default of 1200 x 800.

## Work done

- `Presentation/WindowFrameAutosave.swift`: an `NSViewRepresentable` anchor that reaches the hosting `NSWindow` and calls `setFrameUsingName` then `setFrameAutosaveName("KromoraMainWindow")`. AppKit then writes the frame to user defaults on every move or resize and restores it on the next launch. This is independent of SwiftUI's own restoration, which depends on the system "close windows when quitting" setting and does not apply to the SwiftPM launcher.
- `KromoraScene`: the anchor is a background of the root view. `defaultSize(1200x800)` still seeds the first launch.
- A second window gets the same name refused by AppKit and keeps its cascaded default placement.
- Tests: `WindowFrameAutosaveTests` check that a new window adopts the frame the previous one was left at, and that attaching twice is harmless.

## Acceptance criteria

- Resize and move the window, quit, relaunch: the window opens with the same size and position, in the SwiftPM launcher and the packaged app.
- First launch (no saved frame) still opens at 1200 x 800.
- An unplugged display does not leave the window off-screen (AppKit constrains a restored frame to visible screens).
- Not yet confirmed in the running app; SwiftUI could in principle reapply its own frame after the anchor attaches.
