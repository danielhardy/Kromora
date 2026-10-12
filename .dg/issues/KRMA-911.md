---
id: KRMA-911
title: Restore the main window frame through SwiftUI by keeping the root view type non-private
type: bug
status: backlog
priority: low
agent: claude
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - window
created: 2026-10-12T17:27:09.373Z
updated: 2026-10-12T17:27:23.587Z
blockers: []
order: zzzx
board: product
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
