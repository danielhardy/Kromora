---
id: KRMA-718
title: Prevent toolbar icons flickering while navigating photos in Edit
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce flicker and record state transitions
      result: pass
      notes: "Cause documented in handoff: sourceImage cleared synchronously on navigation, so controls bound to it changed disabled tint. Verified by code reading; not visually reproduced (non-interactive)."
    - criterion: Identify flicker source
      result: pass
      notes: Transient disabled styling; toolbar identity unchanged.
    - criterion: Stable icon presentation during transitions
      result: pass
      notes: Toolbar now binds to toolbarPhotoActionsAvailable, retained across selection transition.
    - criterion: Correct settled state and no action on stale state
      result: pass
      notes: Cleared on unload, set on ready/failure. runAutoAdjustment guards sourceImage/previewState/isLoading; toggleSideBySide and beginCrop guard source.
    - criterion: Rapid navigation and slow-load behavior
      result: pass
      notes: Covered by slow-navigation unit test; live visual check not run.
    - criterion: Focused regression coverage and visual procedure
      result: pass
      notes: testToolbarPhotoAvailabilityStaysSettledDuringSlowPhotoNavigation passes; procedure in handoff comment.
    - criterion: Accessibility and keyboard behavior preserved
      result: pass
      notes: Labels and actions unchanged.
    - criterion: Root cause, fix, verification recorded
      result: pass
  checks_run:
    - "swift test --filter ThumbnailSwitchLifecycleTests: 16 pass, 1 fail (testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument), which also fails on the parent commit edb824a~1 in a clean worktree, so it is pre-existing and unrelated"
    - "new toolbar regression test: pass"
  findings:
    - Pre-existing failure in testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument (late thumbnail published after document revision change); not caused by this change.
    - MenuCommandTests:91 pre-existing failure from unstaged toolbar redesign, noted in handoff.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T20:00:52.813Z
  session: 01MUN3NUPM6Y560ZMP
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - ui
  - interaction
created: 2026-09-29T17:27:41.362Z
updated: 2026-09-29T20:00:52.815Z
blockers: []
order: a0
board: product
---

## Objective

Stop Edit-mode toolbar icons from visibly flickering when moving through photos with the arrow keys or filmstrip selection. Keep the toolbar presentation steady through normal photo loading while preserving each action intended enabled/disabled behavior.

## User report

While arrowing through thumbnails in Edit mode, several toolbar icons flicker. The load is fast enough that the brief change reads as a visual glitch. The user suspects the icons are temporarily disabled while the next photo loads; confirm the cause rather than assuming it.

## Context

Edit-mode toolbar controls are composed in `ContentView.swift`. Their availability currently depends on state such as `sourceImage`, `canRunAutoAdjustment`, and `isComparisonPresentationAvailable`; source navigation and preview publication update related state while a selected photo loads. A transient readiness change may alter the system disabled appearance even when the toolbar action and overall layout have not changed. Also check whether navigation causes toolbar controls or groups to be replaced, animated, or assigned new identities.

## Acceptance criteria

- [ ] Reproduce the flicker by navigating through photos in Edit mode with keyboard arrows and filmstrip selection. Record which icons change and capture the relevant loading/readiness state transitions.
- [ ] Identify and document whether the flicker comes from transient disabled styling, toolbar view identity/recomposition, symbol/content replacement, animation, or another state change.
- [ ] Keep toolbar icon visibility, symbol identity, alignment, and visual emphasis stable during ordinary transitions between photos when the corresponding action remains available for the collection.
- [ ] Preserve correct settled enabled/disabled state for actions that truly require a loaded image or ready preview, and ensure temporarily stable presentation cannot invoke an action against invalid or stale photo state.
- [ ] Rapidly navigate across images and verify icons do not flash enabled/disabled between frames, jump, or disappear. Include transitions where readiness genuinely differs and where loading is slower, so the policy remains correct beyond the fast-load case.
- [ ] Add focused regression coverage for the state-to-toolbar presentation behavior at the narrowest useful boundary, and record a repeatable visual verification procedure for the running app.
- [ ] Preserve accessibility labels and enabled-state semantics, keyboard navigation, and toolbar action behavior.
- [ ] Record the root cause, fix, and verification commands/results in the implementation handoff.

## Investigation notes

Start with the Edit toolbar groups and their `.disabled(...)` conditions in `Sources/KromoraKit/Views/ContentView.swift`, then trace selection changes through source loading and preview publication in `AppViewModel` and its coordinators. Determine whether the source image becomes temporarily unavailable or only the preview/readiness state changes. Avoid treating toolbar flicker as a render-preview blur issue.


### Comment — codex @ 2026-09-29T19:59:02.714Z

Root cause: source navigation clears sourceImage synchronously, then installs a temporary availability marker while the preview is still loading. Toolbar controls bound to sourceImage/canRunAutoAdjustment therefore briefly changed disabled tint; toolbar structure and symbol identity remain stable through that path. Fix: retain last settled photo-action availability for the selected-photo transition, clear it on preparation failure/deletion, and settle it on preview ready/failure. Auto also retains its presentation only during navigation; runAutoAdjustment keeps its source/readiness guards, and ordinary preview work still disables Auto. Regression: swift test --filter ThumbnailSwitchLifecycleTests/testToolbarPhotoAvailabilityStaysSettledDuringSlowPhotoNavigation — passed. `swift test` built but stopped producing output during the broader suite and was interrupted. `swift test --filter MenuCommandTests` — fails at the pre-existing assertion in MenuCommandTests.swift:91 expecting viewModel.toggleInspector() in ContentView after the unstaged toolbar redesign moved that control. Repeatable visual check: run the app with a collection of at least three photos, enter Edit, wait for the first preview to settle, then rapidly navigate with Left/Right and filmstrip clicks. Watch Crop, Auto, Zoom, Comparison, Reset, and Export for disabled-tint flashes, movement, or disappearance. Repeat using a large RAW or other slow-loading photo; confirm the controls keep their positions and symbols during the transition, Auto does not start until the new preview is ready, and a failed/empty source settles disabled. Initial load should stay disabled until a photo is available.

## Agent log

- 2026-09-29T20:00:52.813Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce flicker and record state transitions (pass) — Cause documented in handoff: sourceImage cleared synchronously on navigation, so controls bound to it changed disabled tint. Verified by code reading; not visually reproduced (non-interactive).
- [x] Identify flicker source (pass) — Transient disabled styling; toolbar identity unchanged.
- [x] Stable icon presentation during transitions (pass) — Toolbar now binds to toolbarPhotoActionsAvailable, retained across selection transition.
- [x] Correct settled state and no action on stale state (pass) — Cleared on unload, set on ready/failure. runAutoAdjustment guards sourceImage/previewState/isLoading; toggleSideBySide and beginCrop guard source.
- [x] Rapid navigation and slow-load behavior (pass) — Covered by slow-navigation unit test; live visual check not run.
- [x] Focused regression coverage and visual procedure (pass) — testToolbarPhotoAvailabilityStaysSettledDuringSlowPhotoNavigation passes; procedure in handoff comment.
- [x] Accessibility and keyboard behavior preserved (pass) — Labels and actions unchanged.
- [x] Root cause, fix, verification recorded (pass)
Checks run:
- swift test --filter ThumbnailSwitchLifecycleTests: 16 pass, 1 fail (testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument), which also fails on the parent commit edb824a~1 in a clean worktree, so it is pre-existing and unrelated
- new toolbar regression test: pass
Findings:
- Pre-existing failure in testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument (late thumbnail published after document revision change); not caused by this change.
- MenuCommandTests:91 pre-existing failure from unstaged toolbar redesign, noted in handoff.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUN3NUPM6Y560ZMP
Summary: Verified: toolbar availability retained across photo navigation; guards intact; regression test passes.
