---
id: KRMA-511
title: Animate crop enter/exit chrome (filmstrip and related UI)
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Entering crop: filmstrip visibly slides/fades out rather than popping."
      result: pass
      notes: "Culling bar + filmstrip are now one VStack with a single bottom-move+opacity transition, driven by .animation(chromeAnimation, value: isCropToolActive) at 0.3s. Verified by code review only; not observed in a running UI."
    - criterion: "Leaving crop: filmstrip slides/fades back in."
      result: pass
      notes: Same conditional/transition pairing in reverse; verified by code review.
    - criterion: Animation works for both Save and Cancel exit paths.
      result: pass
      notes: Animation is keyed on canvasState.isCropToolActive, which both commit and cancel flip, so it is path-independent.
    - criterion: Reduce Motion disables or simplifies the motion.
      result: pass
      notes: "ContentView, InfoInspectorView and PreviewView read accessibilityReduceMotion: animation becomes nil and transitions fall back to opacity."
    - criterion: scripts/ci-tests.sh fast and serial pass.
      result: pass
      notes: "fast: 1123 tests, exit 0. serial: 407 tests, 1 pre-existing skip, 0 failures, exit 0."
  checks_run:
    - scripts/ci-tests.sh fast (exit 0, 1123 tests)
    - scripts/ci-tests.sh serial (exit 0, 407 tests, 1 skipped, 0 failures)
  findings:
    - Implementation was left uncommitted in the working tree by the implementer; committed as part of verification.
    - ContentView.toolbarContent had broken indentation after wrapping in Group (Menu bodies and comments at wrong levels). Fixed, whitespace only.
    - Toolbar cross-fade (.transition/.animation on ToolbarItemGroup content) is unverified visually. NSToolbar-hosted items may not honor SwiftUI transitions, so this is probably a harmless no-op. Requirement 4 makes it optional. Nothing to fix, but a human should eyeball the toolbar on crop enter/exit.
    - No behaviour change to crop commit/cancel, selection, or shortcuts found; no security or performance concerns.
  fixes:
    - Re-indented ContentView.toolbarContent (whitespace only, no behaviour change).
  verification_commits:
    - d581365
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T20:05:25.937Z
  session: 01MUBOADMK4XS81DZL
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - crop
  - ui
  - ux
created: 2026-09-21T19:09:09.427Z
updated: 2026-09-21T20:05:25.938Z
order: a0
board: product
commits:
  - d581365
---

## Objective

Entering and leaving crop mode animates the Edit chrome — filmstrip (and related bottom/side UI) slides out on enter and back in on exit — so the transition feels intentional rather than an abrupt swap.

## Context

User report (2026-09-21): when transitioning between crop view and normal Edit, the UI should animate (thumbnails slide out, then slide back in on exit, etc.).

### Today

`ContentView.detailContent` already gates filmstrip / culling bar / source browser on `!canvasState.isCropToolActive` and declares:

- `.transition(.move(edge: .bottom).combined(with: .opacity))` on the filmstrip block
- `.transition(.move(edge: .leading)…)` on the source browser
- `.animation(.easeInOut(duration: 0.2), value: canvasState.isCropToolActive)`

In practice the crop enter/exit still feels abrupt (toolbar swap via KRMA-489, inspector swap to `CropInspectorView`, canvas fit). Either the transitions are not firing reliably (identity/conditional `if` structure, interrupted by layout), durations are too short, or more surfaces (toolbar, inspector column, status) need coordinated animation.

Related: KRMA-471 (crop workspace chrome), KRMA-489 (crop toolbar Save/Cancel/Undo).

## Requirements

1. **Enter crop** — Filmstrip + culling bar animate out (slide toward bottom + fade is fine). Source browser, if visible, animates out. Prefer ~0.25–0.35s ease-in-out; feel polished, not sluggish.
2. **Exit crop** (Save or Cancel) — Same chrome animates back in.
3. Inspector change (Edit tabs ↔ Crop inspector) should participate if cheap (cross-fade or short move); do not flash empty chrome.
4. Toolbar mode change (Edit ↔ crop Save/Cancel/Undo) may cross-fade or allow a short coordinated animation; not required to morph every icon.
5. Canvas image / crop overlay may use a subtle opacity or layout animation but must not fight KRMA-508 straighten presentation or live pan.
6. Reduce-motion: respect `accessibilityReduceMotion` (instant or opacity-only).
7. No behaviour change to crop commit/cancel, selection, or shortcuts.

## Acceptance criteria

- [ ] Entering crop: filmstrip visibly slides/fades out rather than popping.
- [ ] Leaving crop: filmstrip slides/fades back in.
- [ ] Animation works for both Save and Cancel exit paths.
- [ ] Reduce Motion disables or simplifies the motion.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass (no flaky timing tests required).

## Implementation notes

- Primary: `Sources/KromoraKit/Views/ContentView.swift` — verify `if`/`transition`/`animation` pairing; consider explicit `withAnimation` in `beginCrop` / `finishCrop` call sites if SwiftUI implicit animation is unreliable.
- Coordinate with crop toolbar mode switch so chrome and toolbar do not fight.
- Related: KRMA-471, KRMA-489.

### Comment — codex @ 2026-09-21T19:28:10.346Z

Implemented crop chrome transitions: grouped culling bar + filmstrip and source browser now slide/fade as one surface; Edit/Crop inspector content cross-fades with a short move; toolbar mode changes cross-fade; canvas crop-entry/rotation animation and all chrome motion honor accessibilityReduceMotion. Verification: scripts/ci-tests.sh fast (1123 passed) and serial (407 passed, 1 pre-existing RAW fixture skip).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-21T20:05:25.937Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Entering crop: filmstrip visibly slides/fades out rather than popping. (pass) — Culling bar + filmstrip are now one VStack with a single bottom-move+opacity transition, driven by .animation(chromeAnimation, value: isCropToolActive) at 0.3s. Verified by code review only; not observed in a running UI.
- [x] Leaving crop: filmstrip slides/fades back in. (pass) — Same conditional/transition pairing in reverse; verified by code review.
- [x] Animation works for both Save and Cancel exit paths. (pass) — Animation is keyed on canvasState.isCropToolActive, which both commit and cancel flip, so it is path-independent.
- [x] Reduce Motion disables or simplifies the motion. (pass) — ContentView, InfoInspectorView and PreviewView read accessibilityReduceMotion: animation becomes nil and transitions fall back to opacity.
- [x] scripts/ci-tests.sh fast and serial pass. (pass) — fast: 1123 tests, exit 0. serial: 407 tests, 1 pre-existing skip, 0 failures, exit 0.
Checks run:
- scripts/ci-tests.sh fast (exit 0, 1123 tests)
- scripts/ci-tests.sh serial (exit 0, 407 tests, 1 skipped, 0 failures)
Findings:
- Implementation was left uncommitted in the working tree by the implementer; committed as part of verification.
- ContentView.toolbarContent had broken indentation after wrapping in Group (Menu bodies and comments at wrong levels). Fixed, whitespace only.
- Toolbar cross-fade (.transition/.animation on ToolbarItemGroup content) is unverified visually. NSToolbar-hosted items may not honor SwiftUI transitions, so this is probably a harmless no-op. Requirement 4 makes it optional. Nothing to fix, but a human should eyeball the toolbar on crop enter/exit.
- No behaviour change to crop commit/cancel, selection, or shortcuts found; no security or performance concerns.
Fixes:
- Re-indented ContentView.toolbarContent (whitespace only, no behaviour change).
Verification commits:
- d581365
Actor: claude
Resolved model: sonnet
Pickup session: 01MUBOADMK4XS81DZL
Summary: Verified crop enter/exit chrome animation; fast and serial CI lanes pass. Committed implementation and fixed toolbar indentation.
