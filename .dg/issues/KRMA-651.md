---
id: KRMA-651
title: Add automatic pupil/face detection for red-eye and pet-eye correction
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - professional-polish
created: 2026-09-27T07:14:01.683Z
updated: 2026-09-27T07:14:01.683Z
parent: KRMA-599
blockers: []
order: zzzzh
board: product
---

## Objective

Add automatic pupil/face detection so an eye correction can be placed and sized without the
user manually positioning every eye, matching the acceptance criteria in KRMA-599 (parent).

## Context

KRMA-599's acceptance criteria call for "red-eye and pet-eye correction with adjustable pupil
detection, size, and darkening." The shipped `EyeCorrection` model
(`Sources/KromoraKit/Models/RetouchModels.swift`) and `RetouchInspectorView` let a user add an
eye correction and adjust its center, width/height, pupil size, and darkening — but center
placement is entirely manual; there is no automatic pupil or face/eye detection anywhere in the
feature. `docs/RETOUCH.md` explicitly discloses this: "It does not perform automatic face/pupil
detection; eye centers are recipe values." `EyeCorrection` has no field recording whether a
center came from detection vs. manual placement (contrast with `RetouchSpot.sourceWasAutoPicked`,
which exists on spots but is likewise never set by any auto-pick logic today).

## Acceptance criteria

- [ ] Detect likely human pupils (and, where feasible, pet eyes) in the current preview/photo
      and offer them as starting points for a new `EyeCorrection`, using an on-device framework
      already available on macOS 14 (e.g. Vision face/landmark detection) — no new third-party
      dependency.
- [ ] Detected placement remains fully editable afterward (center, size, pupil size, darkening),
      preserving the existing manual-placement path as a fallback when detection finds nothing.
- [ ] Regression coverage for the detection-to-recipe path (detected point maps to a valid,
      editable `EyeCorrection` in source-normalized coordinates) and for the no-detection
      fallback.

## Implementation notes

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
