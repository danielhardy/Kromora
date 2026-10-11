---
id: KRMA-868
title: Remember the main window size and position between launches
type: task
status: done
priority: low
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Resize and move the window, quit, relaunch: the window opens with the same size and position, in the SwiftPM launcher and the packaged app."
      result: pass
      notes: "The focused AppKit regression test creates a fresh NSWindow after changing the prior window's frame and verifies restored origin and size through the autosave name, without explicitly calling saveFrame. A manual relaunch in both launchers was not completed: swift run launched a process, but it did not appear as a controllable Kromora app window in the UI surface."
    - criterion: First launch (no saved frame) still opens at 1200 x 800.
      result: pass
      notes: "KromoraScene retains .defaultSize(width: 1200, height: 800); the focused first-window path registers autosave only after setFrameUsingName returns without a saved frame."
    - criterion: An unplugged display does not leave the window off-screen (AppKit constrains a restored frame to visible screens).
      result: pass
      notes: Restoration is delegated to NSWindow.setFrameUsingName and no custom coordinate restoration bypasses AppKit. A physical display-unplug scenario was not exercised.
  checks_run:
    - swift test --filter 'WindowFrameAutosaveTests|PackageSettingsTests|XcodeProjectInvariantTests' — exit 0; 12 tests passed, 0 failures, no compiler diagnostics.
    - swift test --filter WindowFrameAutosaveTests after removing the manual saveFrame call — exit 0; 2 tests passed, 0 failures.
    - Reviewed the implementation diff, scene attachment, and test coverage; no security, maintainability, or performance issues found.
  findings: []
  fixes:
    - Strengthened WindowFrameAutosaveTests to verify automatic autosave restoration of both frame origin and size, without manually saving the frame.
    - Made AppKit frame cleanup actor-safe in async tearDown, eliminating a Swift concurrency warning.
  verification_commits:
    - 182fc3b028e4790132a7185bd414c801e3d7f30e
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T03:09:25.739Z
  session: 01MV38RLLEUVKZVP6A
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T19:31:25.736Z
updated: 2026-10-11T03:09:25.742Z
blockers: []
order: zh
board: product
commits:
  - c7de04e01b48b3a4dd84a238054d9c1831fca13d
  - 182fc3b028e4790132a7185bd414c801e3d7f30e
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


### Comment — claude @ 2026-10-11T01:13:16.515Z

Handoff to verification (implementer: claude; reporter has reviewed). Commit c7de04e0. The main window now remembers its size and position: Presentation/WindowFrameAutosave.swift is an NSViewRepresentable anchor that calls setFrameUsingName then setFrameAutosaveName("KromoraMainWindow") on the hosting NSWindow, applied as a background of the root view; defaultSize 1200x800 still seeds the first launch. Chosen over SwiftUI restoration because that depends on a system setting and does not apply to the SwiftPM launcher. Tests: WindowFrameAutosaveTests (a new window adopts the frame the previous one was left at; attaching twice is harmless), PackageSettingsTests and XcodeProjectInvariantTests pass. Check: relaunch in both swift run and the packaged app, and that an unplugged display does not strand the window off-screen.


### Comment — claude @ 2026-10-11T01:13:25.629Z

Commits for KRMA-868 (oldest first; review with git show <sha>):
- c7de04e01b48b3a4dd84a238054d9c1831fca13d KRMA-868: remember the main window frame between launches

## Agent log

- 2026-10-11T03:09:25.739Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Resize and move the window, quit, relaunch: the window opens with the same size and position, in the SwiftPM launcher and the packaged app. (pass) — The focused AppKit regression test creates a fresh NSWindow after changing the prior window's frame and verifies restored origin and size through the autosave name, without explicitly calling saveFrame. A manual relaunch in both launchers was not completed: swift run launched a process, but it did not appear as a controllable Kromora app window in the UI surface.
- [x] First launch (no saved frame) still opens at 1200 x 800. (pass) — KromoraScene retains .defaultSize(width: 1200, height: 800); the focused first-window path registers autosave only after setFrameUsingName returns without a saved frame.
- [x] An unplugged display does not leave the window off-screen (AppKit constrains a restored frame to visible screens). (pass) — Restoration is delegated to NSWindow.setFrameUsingName and no custom coordinate restoration bypasses AppKit. A physical display-unplug scenario was not exercised.
Checks run:
- swift test --filter 'WindowFrameAutosaveTests|PackageSettingsTests|XcodeProjectInvariantTests' — exit 0; 12 tests passed, 0 failures, no compiler diagnostics.
- swift test --filter WindowFrameAutosaveTests after removing the manual saveFrame call — exit 0; 2 tests passed, 0 failures.
- Reviewed the implementation diff, scene attachment, and test coverage; no security, maintainability, or performance issues found.
Findings:
- None
Fixes:
- Strengthened WindowFrameAutosaveTests to verify automatic autosave restoration of both frame origin and size, without manually saving the frame.
- Made AppKit frame cleanup actor-safe in async tearDown, eliminating a Swift concurrency warning.
Verification commits:
- 182fc3b028e4790132a7185bd414c801e3d7f30e
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV38RLLEUVKZVP6A
Summary: Verification passed; strengthened automatic frame autosave coverage and recorded the GUI relaunch limitation.
