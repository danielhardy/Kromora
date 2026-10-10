---
id: KRMA-851
title: Add mask-resolution diagnostics and stop swallowing overlay render errors
type: task
status: backlog
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:27.128Z
updated: 2026-10-10T13:02:40.468Z
blockers: []
order: zz
board: product
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
