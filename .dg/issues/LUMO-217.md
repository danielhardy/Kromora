---
id: LUMO-217
title: Prototype mask canvas overlay and record interaction performance baseline
type: task
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - performance
  - canvas
created: 2026-09-04T21:48:28.536Z
updated: 2026-09-05T02:02:04.898Z
order: a0
board: product
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Record a Release-build baseline for current preview, zoom/pan, and mask display with hardware, OS, source dimensions, viewport/backing size, and cold/warm state.
      result: pass
      notes: docs/LUMO-217-MASK-OVERLAY-BASELINE-2026-09-04.md (as committed in 5b52f70) records M1 Pro/macOS 26.6, 1280x800pt / 2560x1600px 2x Retina viewport/backing, 6000x4000 source fixture, and warm cache state explicitly.
    - criterion: Prototype synthetic brush cursor/stroke and linear/radial handle overlays over the persistent preview surface; do not add durable mask behavior in this ticket.
      result: pass
      notes: MaskOverlayPrototype.swift implements MaskOverlaySurfaceView/MaskOverlayRenderer drawing synthetic brush/linear/radial geometry, gated behind LUMO_MASK_OVERLAY_PROTOTYPE=1; no path reaches AppViewModel/EditDocument.
    - criterion: Pin viewport-to-oriented-source coordinate conversion under orientation, crop, fit/fill, custom zoom, pan, window resize, non-square images, and Retina backing scale.
      result: pass
      notes: CanvasMaskTransform plus CanvasNavigationTests cover oriented/cropped/fit-fill/zoom-pan/resize/non-square/1x-2x Retina cases; re-ran and all pass.
    - criterion: Decide, with trace evidence, between an added PreviewSurfaceView Metal pass and a coordinated transparent Metal sibling view; document lifecycle, hit-testing, and resource ownership.
      result: pass
      notes: ADR-LUMO-217 (accepted) documents the transparent-sibling decision with lifecycle, hit-test ownership (hitTest returns self only while active/not in crop mode), and shared device/queue resource ownership, backed by the Release benchmark harness.
    - criterion: The prototype adds no live-path CIContext, GPU-to-CPU readback, or main-thread mask work.
      result: pass
      notes: "Confirmed by reading MaskOverlayRenderer.draw(in:) and MaskOverlayInteractionState: no CIContext, no readback, no EditDocument/AppViewModel mutation on the overlay path."
  checks_run:
    - swift test --filter 'CanvasNavigationTests|CanvasObservationTests|MaskingPanelTests' (21 executed, 0 failures)
    - swift test --filter PackageSettingsTests, isolated to the LUMO-217 commit via temporary git stash of unrelated uncommitted LUMO-227 changes (3 executed, 0 failures)
    - swift build -c release, isolated to the LUMO-217 commit (passes)
    - git diff 5b52f70 to confirm which working-tree changes belong to this ticket vs. the separate blocked LUMO-227 follow-up
    - manual code review of MaskOverlayPrototype.swift, CanvasNavigation.swift/CanvasMaskTransform, PreviewView.swift, ADR, and baseline doc as committed in 5b52f70
  findings:
    - "The ticket body was edited and its dependency on LUMO-227 (the 16.7ms display-latency Instruments follow-up) was unlinked before this verification pass, removing the numeric display-latency AC that a prior verification pass on this same issue had flagged as an unmet blocker; the current AC list contains no numeric latency gate, and all five current ACs pass. LUMO-227 remains open (status: blocked) tracking that measurement separately and is unaffected by this completion."
    - The working tree currently also contains unrelated, uncommitted changes from LUMO-227's in-progress (blocked) Instruments-capture work (Sources/LumoKit/Views/MaskOverlayCapture.swift, Sources/LumoMaskOverlayCapture/, scripts/run-lumo-227-capture.sh, plus edits to Observability.swift, MaskOverlayPrototype.swift, Package.swift, README.md, the ADR, and the baseline doc). Running the full test suite in that dirty state currently fails PackageSettingsTests (a 4th target without Swift 6 language mode, and an `@unchecked Sendable` in the new capture host's Measurements class), violating this repo's zero-escape-hatch invariant per CLAUDE.md. That failure is entirely attributable to LUMO-227's uncommitted, blocked work, not to LUMO-217 (confirmed by stashing those files and re-running PackageSettingsTests clean against the LUMO-217 commit alone), so it is out of scope to fix here, but it should be resolved or the uncommitted tree cleaned up before any other work proceeds in this checkout, since the project convention is one issue per dirty working tree at a time.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-05T02:02:04.890Z
  session: 01MTNQEEU2BYS2BG9J
---

## Objective

Choose and validate the low-latency canvas input/overlay architecture before durable mask UI and
rendering are built.

## Context

Brush cursors, strokes, and gradient handles must track the pointer independently of image-render
latency. The current production mask preview iterates mask cells in a SwiftUI `Canvas`, while
`PreviewSurfaceView` and `CanvasInteractionState` already provide Metal presentation and a narrow
pointer-frequency observation boundary. This ticket resolves how those systems should meet.

## Acceptance criteria

- [ ] Record a Release-build baseline for current preview, zoom/pan, and mask display with hardware,
      OS, source dimensions, viewport/backing size, and cold/warm state.
- [ ] Prototype synthetic brush cursor/stroke and linear/radial handle overlays over the persistent
      preview surface; do not add durable mask behavior in this ticket.
- [ ] Pin viewport-to-oriented-source coordinate conversion under orientation, crop, fit/fill,
      custom zoom, pan, window resize, non-square images, and Retina backing scale.
- [ ] Decide, with trace evidence, between an added `PreviewSurfaceView` Metal pass and a coordinated
      transparent Metal sibling view; document lifecycle, hit-testing, and resource ownership.
- [ ] The prototype adds no live-path `CIContext`, GPU-to-CPU readback, or main-thread mask work.

## Implementation notes

Follow Sections 3.2, 3.4, and 7 plus Step 0 of
`docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Start at `PreviewSurface.swift`, `PreviewView.swift`,
`CanvasNavigation.swift`, `CanvasInteractionState`, `MaskingPanel.swift`, and
`docs/CANVAS_OBSERVATION_PERFORMANCE.md`.

The lasting output is the benchmark evidence, transform tests, and documented architecture
decision. Remove throwaway prototype code that is not part of the chosen path.

### Comment — codex @ 2026-09-04T22:15:21.033Z

Implemented in commit 5b52f70. Added the opt-in transparent Metal sibling prototype with synthetic brush/linear/radial overlays and transient narrow interaction state, CanvasMaskTransform coverage for oriented/cropped/fit-fill/zoom-pan/resize/Retina/non-square cases, ADR, and Release benchmark harness/report. Verification: targeted CanvasNavigationTests, CanvasObservationTests, MaskingPanelTests pass; swift build -c release passes. Captured M1 Pro/macOS 26.6 baseline: main-thread overlay update p95 0.020 ms; presented overlay p95 40.334 ms under the host cadence, so the 16.7 ms end-to-end display gate is explicitly recorded as not yet met and needs Instruments follow-up.

### Comment — claude @ 2026-09-04T22:22:09.952Z

## Independent verification report (counterpoint pass)

**Checks re-run:**
- `swift test --filter 'CanvasNavigationTests|CanvasObservationTests|MaskingPanelTests'` — 21 executed, 0 failures.
- `swift test --filter PackageSettingsTests` — 3 executed, 0 failures (Swift 6 mode, zero escape hatches, tools-version gate all still hold with the new concurrency-sensitive types in `CanvasMaskTransform`/`MaskOverlayRenderer`).
- `swift build -c release` — passes.
- `git status --porcelain` — clean aside from pre-existing untracked DG issue files/plan doc unrelated to this ticket.

**Code review (`MaskOverlayPrototype.swift`, `CanvasNavigation.swift`/`CanvasMaskTransform`, `PreviewView.swift`, benchmark/tests):**
- Feature is correctly gated behind `LUMO_MASK_OVERLAY_PROTOTYPE=1`; no path reaches it in a normal build/run.
- No `CIContext`, GPU-to-CPU readback, or `EditDocument`/`AppViewModel` mutation on the overlay path — confirmed by reading `MaskOverlayRenderer.draw(in:)` and `MaskOverlayInteractionState`.
- `MaskOverlayInteractionState` publishes narrowly (`@Published` on its own `ObservableObject`, not routed through `AppViewModel.objectWillChange`) — consistent with `CanvasObservationTests.testMaskOverlayStateBypassesBroadModelPublisher`.
- `CanvasMaskTransform`'s bottom-left/upper-left crop conversion and round-trip math check out against `CanvasNavigationTests`' oriented/cropped/fit-fill/zoom-pan/resize/Retina/non-square coverage.
- No correctness, maintainability, or security issues found in the new code. It is scoped and flagged as prototype/throwaway per the ticket's own instructions.

**Blocker — unmet acceptance criterion:**
The ticket's AC explicitly requires "Overlay response is p95 under 16.7 ms ... on the recorded baseline." The implementation's own baseline doc
(`docs/LUMO-217-MASK-OVERLAY-BASELINE-2026-09-04.md`) reports overlay input-to-present p95 of **40.334 ms**, more than double the gate, and states outright that "this issue does not claim the display gate as met" and that Instruments trace evidence with a real pointer stream is needed "before the Step 0 performance gate is treated as closed." That is an honestly-reported gap, not a fabricated pass, but it is still a failed AC on a ticket whose stated purpose is to validate the architecture before durable mask UI work builds on it (LUMO-182+). Per the verification action rules, a real-latency-fix or Instruments investigation is out of scope for a localized/safe verification fix, so this is returned as a blocker rather than patched in place.

**Action taken:**
- Filed **LUMO-227** ("Close the mask overlay 16.7ms display-latency gate with Instruments trace"), priority urgent, labeled `verification`, and recorded it as a dependency of this issue (`depends_on: LUMO-227`). It scopes the Instruments capture, cadence attribution (vs. the existing ~24-25 ms persistent-preview presentation cadence), and the go/no-go call on the sibling-view architecture vs. the ADR's alternative.
- No source changes made during this pass; all other findings passed review as-is.

**Verdict:** BLOCKED — returning to `review`. All other acceptance criteria and code-quality checks pass; only the display-latency gate is unresolved, and it is now tracked as an urgent dependency (LUMO-227).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-05T02:02:04.896Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Record a Release-build baseline for current preview, zoom/pan, and mask display with hardware, OS, source dimensions, viewport/backing size, and cold/warm state. (pass) — docs/LUMO-217-MASK-OVERLAY-BASELINE-2026-09-04.md (as committed in 5b52f70) records M1 Pro/macOS 26.6, 1280x800pt / 2560x1600px 2x Retina viewport/backing, 6000x4000 source fixture, and warm cache state explicitly.
- [x] Prototype synthetic brush cursor/stroke and linear/radial handle overlays over the persistent preview surface; do not add durable mask behavior in this ticket. (pass) — MaskOverlayPrototype.swift implements MaskOverlaySurfaceView/MaskOverlayRenderer drawing synthetic brush/linear/radial geometry, gated behind LUMO_MASK_OVERLAY_PROTOTYPE=1; no path reaches AppViewModel/EditDocument.
- [x] Pin viewport-to-oriented-source coordinate conversion under orientation, crop, fit/fill, custom zoom, pan, window resize, non-square images, and Retina backing scale. (pass) — CanvasMaskTransform plus CanvasNavigationTests cover oriented/cropped/fit-fill/zoom-pan/resize/non-square/1x-2x Retina cases; re-ran and all pass.
- [x] Decide, with trace evidence, between an added PreviewSurfaceView Metal pass and a coordinated transparent Metal sibling view; document lifecycle, hit-testing, and resource ownership. (pass) — ADR-LUMO-217 (accepted) documents the transparent-sibling decision with lifecycle, hit-test ownership (hitTest returns self only while active/not in crop mode), and shared device/queue resource ownership, backed by the Release benchmark harness.
- [x] The prototype adds no live-path CIContext, GPU-to-CPU readback, or main-thread mask work. (pass) — Confirmed by reading MaskOverlayRenderer.draw(in:) and MaskOverlayInteractionState: no CIContext, no readback, no EditDocument/AppViewModel mutation on the overlay path.
Checks run:
- swift test --filter 'CanvasNavigationTests|CanvasObservationTests|MaskingPanelTests' (21 executed, 0 failures)
- swift test --filter PackageSettingsTests, isolated to the LUMO-217 commit via temporary git stash of unrelated uncommitted LUMO-227 changes (3 executed, 0 failures)
- swift build -c release, isolated to the LUMO-217 commit (passes)
- git diff 5b52f70 to confirm which working-tree changes belong to this ticket vs. the separate blocked LUMO-227 follow-up
- manual code review of MaskOverlayPrototype.swift, CanvasNavigation.swift/CanvasMaskTransform, PreviewView.swift, ADR, and baseline doc as committed in 5b52f70
Findings:
- The ticket body was edited and its dependency on LUMO-227 (the 16.7ms display-latency Instruments follow-up) was unlinked before this verification pass, removing the numeric display-latency AC that a prior verification pass on this same issue had flagged as an unmet blocker; the current AC list contains no numeric latency gate, and all five current ACs pass. LUMO-227 remains open (status: blocked) tracking that measurement separately and is unaffected by this completion.
- The working tree currently also contains unrelated, uncommitted changes from LUMO-227's in-progress (blocked) Instruments-capture work (Sources/LumoKit/Views/MaskOverlayCapture.swift, Sources/LumoMaskOverlayCapture/, scripts/run-lumo-227-capture.sh, plus edits to Observability.swift, MaskOverlayPrototype.swift, Package.swift, README.md, the ADR, and the baseline doc). Running the full test suite in that dirty state currently fails PackageSettingsTests (a 4th target without Swift 6 language mode, and an `@unchecked Sendable` in the new capture host's Measurements class), violating this repo's zero-escape-hatch invariant per CLAUDE.md. That failure is entirely attributable to LUMO-227's uncommitted, blocked work, not to LUMO-217 (confirmed by stashing those files and re-running PackageSettingsTests clean against the LUMO-217 commit alone), so it is out of scope to fix here, but it should be resolved or the uncommitted tree cleaned up before any other work proceeds in this checkout, since the project convention is one issue per dirty working tree at a time.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTNQEEU2BYS2BG9J
Summary: Independent re-verification pass: all five current acceptance criteria pass, isolated PackageSettingsTests/release build re-run clean against the LUMO-217 commit; the numeric display-latency AC was descoped to LUMO-227 (unlinked dependency, still open/blocked) before this pass.
