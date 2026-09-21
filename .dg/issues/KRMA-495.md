---
id: KRMA-495
title: "Regression: Edit canvas zoom/pan broken (double-click, live pan, Y-axis flip)"
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 36ae15f45f97d78b2a15963353340834251c2cab
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-20T23:54:16.643Z
  session: 01MUAGQ8P09GUAJR5G
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - preview
  - zoom
  - regression
  - ui
created: 2026-09-20T23:33:06.656Z
updated: 2026-09-20T23:54:30.744Z
order: a0
board: product
commits:
  - 36ae15f45f97d78b2a15963353340834251c2cab
---

## Objective

Restore trustworthy Edit-canvas navigation: double-click toggles fit ↔ zoom, panning while zoomed follows the pointer **live** (not only on mouse-up), and vertical pan direction matches macOS / Photos again.

## Context

User report (2026-09-20, frustrated regression): zoom/pan is broken **again**.

1. **Double-click to zoom / unzoom still does not work** — supposedly fixed in **KRMA-483** (`done`). Fix was meant to stop `MaskCanvasOverlay` from shielding `PreviewMTKView` in selection mode (`.allowsHitTesting(maskingState.activeTool != .selection)`). That change may still be **uncommitted** on the main tree, or the real hit-test winner is still the SwiftUI `DragGesture` / another overlay. Either way the product behaviour is still wrong in the running app the user is on.

2. **Panning when zoomed only refreshes on drop** — image does not track the drag; content jumps/updates when the gesture ends. Terrible for detail work. Closely related to **KRMA-482** (ROI pan gaps). Verification on that ticket already noted a likely trade-off: *“while a partial ROI is held at its published navigation, the image does not follow the drag until the new ROI lands, so pan can feel steppy.”* That is not acceptable as the permanent UX. Live pan must move the presented frame with the pointer (Metal transform / retained texture) every tick; ROI/detail refresh can trail without freezing the photo until mouse-up.

3. **Up/down pan is flipped again** — same class of bug as **KRMA-439** (`done`), which removed a `height: -delta.height` negation in `panCanvas` and documented CanvasNavigation origin as **y-down** (aligned with `PreviewSurface.metal`). Something in the presentation / ROI / transform path has inverted vertical drag relative to horizontal again. Do not “fix” by blindly negating in one layer without tracing the full pipeline.

### Likely code surfaces

- `PreviewView.canvasSurface` — `onDoubleClick` → `toggleCanvasZoom()`; `DragGesture` → `panCanvas`; `MaskCanvasOverlay` hit testing; crop `ignoresHits`.
- `PreviewMTKView.mouseDown` (`PreviewSurface.swift`) — `clickCount == 2`.
- `AppViewModel.panCanvas` / `beginCanvasInteraction` / `endCanvasInteraction` / `scheduleInteractivePreview` — display-revision fencing and ROI submits during drag.
- `PreviewSurface` retained-frame presentation vs `presentationNavigation` / partial ROI hold (KRMA-482).
- `CanvasNavigation.pan` + Metal vertex transform (KRMA-439 coordinate contract).

Working tree note at ticket filing: uncommitted `PreviewView.swift` / `PreviewSurface.swift` / `PreviewSurfaceTests.swift` edits related to KRMA-483 may or may not be what the user is running — reproduce on the binary they have, then on clean `main`.

## Requirements

- **Double-click:** fit → remembered zoom (fallback 2×); zoomed → fit. Works with masking overlay visible in selection mode; crop mode may keep owning clicks. Must not start a pan. Regression test on the real click path must keep failing if hit-testing regresses again (strengthen KRMA-483 coverage if it was insufficient or not landed).
- **Live pan:** while dragging at any zoom (including 800%), the photo moves with the pointer on every `onChanged` / pointer sample. Settled / interactive ROI may refine detail asynchronously; never wait for mouse-up to show motion. No blank gaps inside the photo (KRMA-482 contract remains).
- **Pan direction:** drag down → content moves down (Photos/Preview/Figma); horizontal unchanged. Re-assert KRMA-439 tests (`testPanMovesTheImageInTheDirectionOfTheViewportDelta`, `testPanCanvasPreservesPointerDirectionOnBothAxes`) against the **presented** frame, not only `transform.origin` math, if presentation reintroduced an independent flip.
- Name the introducing commit(s) for each regression in the ticket when found.

## Acceptance criteria

- [ ] Double-click zoom/unzoom works in the running Edit canvas (with and without mask selection overlay); root cause vs KRMA-483 documented.
- [ ] Zoomed pan tracks the pointer continuously during drag; mouse-up is not required for the image to move.
- [ ] Vertical pan direction matches horizontal (macOS convention); no reintroduction of a silent sign flip.
- [ ] KRMA-482 “no blank ROI gaps” still holds during and after pan.
- [ ] Automated regressions cover double-click hit path, live pan presentation (or navigation+publish contract that implies it), and Y-axis sign; `scripts/ci-tests.sh fast` and `serial` pass.

## Implementation notes

- Status intentionally **backlog** (not ready) until prioritized.
- Related: KRMA-483 (double-click), KRMA-482 (ROI pan / steppy trade-off), KRMA-439 (Y flip), KRMA-368 (double-click zoom feature).
- Prefer one coherent navigation pass over three drive-by sign/hit-test patches that fight each other.

### Comment — codex @ 2026-09-20T23:54:30.743Z

Verification: scripts/ci-tests.sh fast passed 1101/1101 required tests; scripts/ci-tests.sh serial passed 397/397 with 1 documented RAW-fixture skip; focused PreviewSurfaceTests and CanvasObservationTests passed; dg validate --json passed with only existing unknown-model warnings; git diff --check passed. Commit: 36ae15f45f97d78b2a15963353340834251c2cab.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-20T23:54:16.643Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- 36ae15f45f97d78b2a15963353340834251c2cab
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUAGQ8P09GUAJR5G
Summary: Implemented live Edit-canvas navigation. Double-click now reaches PreviewMTKView through selection-mode mask overlays and toggles fit with remembered/fallback 2x zoom without starting a pan. Partial ROI publications now fall back to the last confirmed complete retained texture while pointer navigation changes, then hand back to the ROI at its published navigation; this preserves coverage without waiting for mouse-up or introducing blank gaps. The existing y-down CanvasNavigation/Metal presentation contract remains intact and is covered by presentation orientation tests. Regression causes: KRMA-482 commit 3c942c8 introduced the partial-ROI publish-navigation hold that made pan feel stepped; KRMA-483 hit-testing work was present as uncommitted working-tree changes at pickup, with no introducing commit found for this ticket; no new y-axis sign-flip commit was found—the presented-frame tests confirm the existing KRMA-439 contract.
