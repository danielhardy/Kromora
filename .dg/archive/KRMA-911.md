---
id: KRMA-911
title: Restore the main window frame through SwiftUI by keeping the root view type non-private
type: bug
status: done
priority: low
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Resize and move the window, press Command-Q, relaunch from Xcode, and restore the previous frame.
      result: pass
      notes: Reporter confirmed manually; review verified the root view type is stable and non-private.
    - criterion: Restore the previous frame under swift run.
      result: pass
      notes: Reporter confirmed manually; SwiftUI uses the same stable internal root view type.
    - criterion: A first launch with no saved frame opens at 1200 x 800.
      result: pass
      notes: "WindowGroup retains .defaultSize(width: 1200, height: 800)."
    - criterion: No AppKit frame-autosave code remains; PackageSettingsTests and XcodeProjectInvariantTests pass.
      result: pass
      notes: No frame-autosave implementation references remain. All 11 focused tests passed.
  checks_run:
    - swift build (exit 0)
    - swift test filtered to PackageSettingsTests and XcodeProjectInvariantTests (11 tests, 0 failures, exit 0)
    - Structural search for frame-autosave implementation references in Sources, Tests, and Xcode returned none.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T21:43:46.742Z
  session: 01MV5S2SL2EBWFFXSJ
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - window
created: 2026-10-12T17:27:09.373Z
updated: 2026-10-12T21:43:46.746Z
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-12T17:28:25.503Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Make the main window reopen at the size and position it was left at, in the packaged app and under `swift run`. Supersedes the AppKit anchor approach from KRMA-868.

## Context

KRMA-868 added `WindowFrameAutosave`, an AppKit anchor that restored the frame by autosave name. It did not work in the Xcode-run app: the window reopened at 1200 x 800 after a clean ⌘Q. SwiftUI already autosaves the frame itself, under a key built from the scene's root view type name (`NSWindow Frame SwiftUI.WindowGroup<…KromoraRootView…>-1-AppWindow-1`). `KromoraRootView` was `private`, and a private type's name embeds a per-build context address (`Kromora.(unknown context at $104c35b24).KromoraRootView`), so each build looked for a different key and never found the saved frame. The preferences container of the Xcode build showed both the stale unstable key and the older stable `KromoraKit.ContentView` key.

## Work done

- `KromoraScene.swift`: `KromoraRootView` is no longer `private`, with a comment explaining why it must stay non-private. The scene is a plain `WindowGroup` with `.defaultSize(1200x800)` seeding the first launch.
- Removed `Presentation/WindowFrameAutosave.swift` and `WindowFrameAutosaveTests.swift`.
- Intermediate attempts that were tried and discarded: late restore passes, explicit save on move/resize/close/quit, a custom preference key, and `defaultWindowPlacement`. `NSWindow.saveFrame(usingName:)` did not change the stored value under `swift run`.
- The key is now `…KromoraKit.KromoraRootView…` and is identical across two separate rebuilds.

## Acceptance criteria

- Resize and move the window, press ⌘Q, relaunch from Xcode: the window opens at the same size and position. (Confirmed manually by the reporter.)
- The same under `swift run`. (Confirmed manually by the reporter.)
- First launch with no saved frame opens at 1200 x 800.
- No AppKit frame-autosave code remains; `PackageSettingsTests` and `XcodeProjectInvariantTests` pass.

## Verification notes

- Check that `KromoraRootView` stays non-private, or that the saved key is otherwise stable across builds (`defaults read` the app's domain for `NSWindow Frame SwiftUI.WindowGroup`).
- Checks run by the implementer: `swift build`; `swift test --filter 'PackageSettingsTests|XcodeProjectInvariantTests'` (11 tests, 0 failures). The full suite was not run.


### Comment — claude @ 2026-10-12T17:28:24.990Z

Implemented in 71e71447. Root cause: private KromoraRootView gave SwiftUI an unstable autosave key. Confirmed manually by the reporter in Xcode and swift run. Checks: swift build; PackageSettingsTests + XcodeProjectInvariantTests pass.

## Agent log

- 2026-10-12T21:43:46.742Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Resize and move the window, press Command-Q, relaunch from Xcode, and restore the previous frame. (pass) — Reporter confirmed manually; review verified the root view type is stable and non-private.
- [x] Restore the previous frame under swift run. (pass) — Reporter confirmed manually; SwiftUI uses the same stable internal root view type.
- [x] A first launch with no saved frame opens at 1200 x 800. (pass) — WindowGroup retains .defaultSize(width: 1200, height: 800).
- [x] No AppKit frame-autosave code remains; PackageSettingsTests and XcodeProjectInvariantTests pass. (pass) — No frame-autosave implementation references remain. All 11 focused tests passed.
Checks run:
- swift build (exit 0)
- swift test filtered to PackageSettingsTests and XcodeProjectInvariantTests (11 tests, 0 failures, exit 0)
- Structural search for frame-autosave implementation references in Sources, Tests, and Xcode returned none.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5S2SL2EBWFFXSJ
Summary: Independent verification passed: stable non-private SwiftUI root and default window size confirmed; build and 11 focused invariant tests passed.
