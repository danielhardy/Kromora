---
id: KRMA-511
title: Animate crop enter/exit chrome (filmstrip and related UI)
type: task
status: ready
priority: medium
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - crop
  - ui
  - ux
created: 2026-09-21T19:09:09.427Z
updated: 2026-09-21T19:09:10.697Z
order: n
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
