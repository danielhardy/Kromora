---
id: KRMA-472
title: "Crop geometry tools: straighten, flip, and expanded aspect catalog"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Crop UI exposes Original, Freeform, Square, 16:9, 4:5, 5:7, 4:3, 3:5, 3:2, and Custom aspect choices
      result: pass
      notes: Crop inspector presents the expanded catalog with orientation controls where applicable.
    - criterion: Straighten supports a continuous -45 to +45 degree adjustment
      result: pass
      notes: Draft slider state is clamped, previewed live, and persisted on Done.
    - criterion: Horizontal and vertical flips compose with crop rotation
      result: pass
      notes: Geometry flags are modeled, composed in the render graph, and remapped across quarter turns.
    - criterion: Crop edits remain transient until Done and cancel restores committed state
      result: pass
      notes: Canvas draft state, AppViewModel workflow, and regression coverage verify Done/Cancel behavior.
    - criterion: Geometry survives Codable, undo/redo, copy/paste, preview, and export
      result: pass
      notes: Schema migrations, clipboard categories, render engine/pipeline integration, and focused tests cover persistence and parity.
    - criterion: Build and tests pass
      result: pass
      notes: swift build passed; full swift test passed 1519 tests with 54 expected skips and 0 failures; git diff --check and dg validate pass.
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-20T02:57:14.076Z
  session: 01MU979F6MBZ7IQLTA
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - crop
  - editor
created: 2026-09-19T22:18:54.081Z
updated: 2026-09-20T02:57:14.078Z
depends_on:
  - KRMA-471
order: t
board: product
---

Parent: KRMA-470. Depends on KRMA-471 (inspector must exist before these controls).

## Objective

Give the crop inspector the framing tools photographers expect after 90° rotate: **continuous straighten**, **flip**, and a **Photos-like aspect list**. These are durable, non-destructive edits, drafted in crop mode and committed with Done.

## Context

`ImageRotation` is quarter-turns only by design (no accumulated float error). Straighten must be a **separate** value — do not stuff degrees into `ImageRotation`.

`CropAdjustments` today is `normalizedRect` + `aspectRatio` + `orientation`. KRMA-101 removed a dead clipboard `angle` field because nothing rendered it. This ticket is the real geometry, explicitly scoped.

Apple Photos crop inspector (see KRMA-470 screenshot): Straighten slider in degrees, Flip, Aspect (Original, Freeform, Square, 16:9, 4:5, 5:7, 4:3, 3:5, 3:2, Custom). Vertical/Horizontal perspective and Auto are KRMA-473.

## Scope

1. **Straighten** — Continuous angle (suggested range ±45°, display in °). Live preview while cropping; persist on Done; discard on Cancel. Compose in `RenderPipeline` with crop/rotation (document the order in code; typical: quarter-turn rotation → straighten → crop, or equivalent that keeps overlay coordinates honest). Use Core Image (`CIStraightenFilter` or affine). Overlay/crop-rect math must stay in the same oriented space as the preview.

2. **Flip** — Horizontal and/or vertical mirrors as durable flags (or a small enum). Draft in crop mode; commit with Done. Render via affine scale. Overlay remaps so handles still match pixels.

3. **Aspect catalog** — Expand `CropAspectRatio` (or a sibling list) to at least: Original, Freeform, Square, 16:9, 4:5, 5:7, 4:3, 3:5, 3:2, Custom. Original = source pixel aspect (identity ratio, not “reset crop”). Custom may be the current freeform size or a numeric pair if cheap; do not block the ticket on a Custom dialog. Keep portrait/landscape orientation where a preset is not square. Inspector shows a **list**, not only a menu buried in overlay chrome.

4. **Draft contract** — Same as crop rect / in-crop 90° rotate: transient until Done; Cancel/Escape restores committed geometry including previous straighten/flip/aspect.

5. **Persistence** — Codable on `EditDocument` / `CropAdjustments` (or a small `ImageGeometry` value if cleaner). Undo/redo, copy/paste, preview/export parity. Legacy documents default to 0° / no flip.

## Acceptance criteria

- [ ] Crop inspector includes a Straighten control; dragging it rotates the photo continuously in preview without leaving crop mode.
- [ ] Done persists straighten; Cancel/Escape reverts to the last committed angle (0° if none).
- [ ] Flip horizontal/vertical is available in the crop inspector, drafted then committed the same way.
- [ ] Aspect list includes Original, Freeform, Square, 16:9, 4:5, 5:7, 4:3, 3:5, 3:2 (Custom if implemented); choosing a preset reframes the draft without committing.
- [ ] Preview, side-by-side comparison, and export share the same straighten/flip/crop result. Quarter-turn `ImageRotation` still works and composes with straighten (no double-rotate, no axis-swap bug).
- [ ] Model + pipeline tests for identity defaults, undo/redo, cancel-discards, commit-persists, and rotation+straighten+crop composition. `swift build`, focused tests, `dg validate`, `git diff --check`.

## Out of scope

- Vertical/horizontal perspective and Auto (KRMA-473).
- Changing KRMA-471 chrome (inspector list vs overlay is assumed landed).
- Overloading `ImageRotation` with arbitrary degrees.

## Implementation notes

- `Sources/KromoraKit/Models/CropAdjustments.swift` — new fields; keep `normalizedRect` in oriented source space and document how straighten/flip change that space.
- `Sources/KromoraKit/Models/ImageRotation.swift` — leave as quarter-turns.
- `Sources/KromoraKit/Models/RenderPipeline.swift` — new stage(s); bump pipeline version; crop overlay must request the matching uncropped-but-straightened preview (today crop already asks for uncropped adjusted pixels).
- `Sources/KromoraKit/Models/CanvasNavigation.swift` — draft straighten/flip alongside `cropDraft` / `cropRotation`.
- `Sources/KromoraKit/ViewModels/AppViewModel.swift` — `commitCrop` / `cancelCrop` fold or discard the new drafts.
- Clipboard: if `EditClipboard` crop category exists, persist the new fields; do not add unused angle keys.

Related: KRMA-470, KRMA-471, KRMA-101, KRMA-463.

## Agent log

- 2026-09-20T02:57:14.076Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Crop UI exposes Original, Freeform, Square, 16:9, 4:5, 5:7, 4:3, 3:5, 3:2, and Custom aspect choices (pass) — Crop inspector presents the expanded catalog with orientation controls where applicable.
- [x] Straighten supports a continuous -45 to +45 degree adjustment (pass) — Draft slider state is clamped, previewed live, and persisted on Done.
- [x] Horizontal and vertical flips compose with crop rotation (pass) — Geometry flags are modeled, composed in the render graph, and remapped across quarter turns.
- [x] Crop edits remain transient until Done and cancel restores committed state (pass) — Canvas draft state, AppViewModel workflow, and regression coverage verify Done/Cancel behavior.
- [x] Geometry survives Codable, undo/redo, copy/paste, preview, and export (pass) — Schema migrations, clipboard categories, render engine/pipeline integration, and focused tests cover persistence and parity.
- [x] Build and tests pass (pass) — swift build passed; full swift test passed 1519 tests with 54 expected skips and 0 failures; git diff --check and dg validate pass.
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU979F6MBZ7IQLTA
Summary: Implemented continuous straighten, horizontal/vertical flip, expanded crop aspect catalog, transient crop drafting, persistence, clipboard transfer, quarter-turn composition, and preview/export pipeline parity.
