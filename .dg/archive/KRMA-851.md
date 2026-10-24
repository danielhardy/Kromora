---
id: KRMA-851
title: Add mask-resolution diagnostics and stop swallowing overlay render errors
type: task
status: done
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: With the stream running, adding or editing a smart mask logs a loading → ready/unavailable/cancelled sequence and per-resolve timings.
      result: pass
      notes: Reviewed MaskCanvasOverlay task lifecycle and CoordinatorLocalMaskResolver timing events. Semantic requests log loading and a terminal state; successful semantic resolves emit lookup/apply/resize timing details; cancellation is logged.
    - criterion: A failed overlay render logs its actual error.
      result: pass
      notes: RenderEngine routes thrown overlay errors to mask-resolution logging. The full error description is retained in the private unified-log field, while the public event exposes the NSError code.
    - criterion: ObservabilityTests pass.
      result: pass
      notes: "swift test --filter ObservabilityTests passed: 7 tests, 0 failures."
  checks_run:
    - "swift test --filter ObservabilityTests: exit 0; 7 tests passed, 0 failures."
    - "git diff --check: exit 0."
    - Reviewed committed KRMA-851 implementation and current mask diagnostics call sites for correctness, maintainability, security, and performance. No manual UI stream session was run.
  findings:
    - "Found a privacy issue during verification: overlay error descriptions were interpolated as public log data and can contain file or user details. Fixed locally by retaining the full NSError domain and description in private log fields; public output keeps the error code."
  fixes:
    - Changed overlay error logging to preserve the actual error in private unified-log fields and emit only its numeric code as public event detail.
  verification_commits:
    - 26f998e7
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-10T14:36:54.718Z
  session: 01MV2HXSN3P0U0TT6J
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:27.128Z
updated: 2026-10-10T14:36:54.722Z
blockers: []
order: l
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T13:03:51.398Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 94933933a4dad20f5d6ac34df836bf79cd9c3652
  - 26f998e7
---

## Objective

Make a stuck "Analyzing mask…" diagnosable. Previously the render engine swallowed every mask-overlay error (`catch { return nil }`) and nothing recorded why or how long mask resolution took.

## Work done

- `Observability.swift`: new stages `MaskOverlayResolve`, `MaskSemanticResolve`, `MaskSemanticApply`; new events `MaskResolutionState` and `MaskResolveTiming`; `KromoraObservability.maskDiagnostic` mirrors those events to a regular `Logger` (category `mask-resolution`) because signposts are invisible to a plain `log stream`.
- `LocalMaskRendering.swift`: `CoordinatorLocalMaskResolver` emits resolve/apply intervals and one `MaskResolveTiming` event (target, source/target size, softness, lookup/resize/apply ms).
- `MaskingWorkspace.swift`: overlay task wraps an interval and logs `loading`, `ready`, `unavailable`, `cancelled`.
- `RenderEngine.swift`: `makeMaskOverlayImage` logs `overlayError=<error>` or `overlayNoMask` instead of silently returning nil.
- `ObservabilityTests` vocabulary updated; `docs/TESTING.md` documents the stream commands (`log stream --predicate 'subsystem == "com.kromora.app" AND category == "mask-resolution"'`; `--signpost` for the signposts) and how to read them.

Note: the subsystem is still `com.kromora.app` while the bundle id is `com.last8.kromora.photo`; aligning them is out of scope here.

## Acceptance criteria

- With the stream running, adding or editing a smart mask logs a loading → ready/unavailable/cancelled sequence and per-resolve timings.
- A failed overlay render logs its actual error.
- ObservabilityTests pass.


### Comment — claude @ 2026-10-10T13:03:50.927Z

Implemented in 94933933. ObservabilityTests vocabulary updated and passing; log stream commands documented in docs/TESTING.md. Subsystem remains com.kromora.app (bundle id is com.last8.kromora.photo); not changed here.


### Comment — claude @ 2026-10-10T13:11:13.139Z

Verifier note: implementation commit(s) 94933933 are now recorded in the ticket's commits field. Review with: git show 94933933. Verifier is codex (verification_agent). Acceptance criteria and known gaps are in the ticket body.

## Agent log

- 2026-10-10T14:36:54.718Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] With the stream running, adding or editing a smart mask logs a loading → ready/unavailable/cancelled sequence and per-resolve timings. (pass) — Reviewed MaskCanvasOverlay task lifecycle and CoordinatorLocalMaskResolver timing events. Semantic requests log loading and a terminal state; successful semantic resolves emit lookup/apply/resize timing details; cancellation is logged.
- [x] A failed overlay render logs its actual error. (pass) — RenderEngine routes thrown overlay errors to mask-resolution logging. The full error description is retained in the private unified-log field, while the public event exposes the NSError code.
- [x] ObservabilityTests pass. (pass) — swift test --filter ObservabilityTests passed: 7 tests, 0 failures.
Checks run:
- swift test --filter ObservabilityTests: exit 0; 7 tests passed, 0 failures.
- git diff --check: exit 0.
- Reviewed committed KRMA-851 implementation and current mask diagnostics call sites for correctness, maintainability, security, and performance. No manual UI stream session was run.
Findings:
- Found a privacy issue during verification: overlay error descriptions were interpolated as public log data and can contain file or user details. Fixed locally by retaining the full NSError domain and description in private log fields; public output keeps the error code.
Fixes:
- Changed overlay error logging to preserve the actual error in private unified-log fields and emit only its numeric code as public event detail.
Verification commits:
- 26f998e7
Actor: codex
Resolved model: unknown
Pickup session: 01MV2HXSN3P0U0TT6J
Summary: Verification passed; ObservabilityTests passed. Updated overlay error logging to keep diagnostic text private in unified logs.
