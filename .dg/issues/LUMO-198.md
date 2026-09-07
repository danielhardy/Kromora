---
id: LUMO-198
title: Region relationships (subject/background/face deltas)
type: feature
status: done
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:55.042Z
updated: 2026-09-07T04:02:50.519Z
depends_on:
  - LUMO-197
order: o1q7hkcb
board: product
commits:
  - e839d4c
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/RegionRelationships.swift` (populator)
**Depends on:** LUMO-197
**Epic:** LUMO-181 — see original proposal §20

## 1. Problem

Raw per-region statistics are useful, but almost every downstream consumer will immediately need
the *relationship* ("subject is 0.31 darker than background"). Compute it once here.

## 2. Requirement (acceptance criteria)

1. `struct RegionRelationships: Sendable, Codable, Equatable` — `subjectToGlobalLuminanceDelta`,
   `subjectToBackgroundLuminanceDelta`, `faceToSubjectLuminanceDelta`,
   `faceToBackgroundLuminanceDelta`, `subjectContrast`, `backgroundContrast` — all `Float?`.
2. Populated from `PhotoAnalysis.regions` + `globalTone` + the primary-subject pick (LUMO-197).
3. Fields are `nil` when inputs aren't available (no face → face-relative fields nil) — never a
   fabricated value.
4. Deltas use the `perceptual` luminance variant (LUMO-182) — document why.
5. Pure function, no Vision, no actors.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Not the place for aesthetic judgments ("subject is too dark") — states a signed delta only.
  Judgment happens in LUMO-199/200.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §3, original proposal §20.
- LUMO-197 (primary subject), LUMO-194 (region stats), LUMO-192 (global stats) — the three inputs.

## 5. Testing

- `Tests/LumoKitTests/RegionRelationshipsTests.swift` (new): dark subject/bright background →
  correct-sign, correct-magnitude delta. No subject → subject-relative fields nil. No face →
  face-relative fields nil, subject-relative fields still populated.

## Agent log

- 2026-09-04T16:11:18.731Z: Added pure RegionRelationships derivation with signed perceptual deltas, optional missing evidence, and PhotoAnalysis assembly wiring.
