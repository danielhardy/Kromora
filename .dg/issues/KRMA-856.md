---
id: KRMA-856
title: Test that mask overlay task identity ignores adjustments but tracks mask changes
type: task
status: done
priority: low
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Changing any LocalAdjustments value leaves overlayIdentity equal.
      result: pass
      notes: Coverage includes all 16 adjustment properties; the full fast lane passed.
    - criterion: Changing name or autoProvenance leaves overlayIdentity equal.
      result: pass
    - criterion: Changing layer membership/identity, components, geometry, mode, inversion, enabled state, or amount changes overlayIdentity.
      result: pass
      notes: Regression tests cover component add, remove, reorder, geometry, mode, inversion, layer id, isEnabled, isInverted, and amount.
    - criterion: A guard test enumerates LocalAdjustmentLayer stored and Codable keys and clearly flags new fields for overlay identity review.
      result: pass
      notes: The test compares reflected stored fields and encoded JSON keys against the reviewed set with explicit failure messages.
    - criterion: The projection changes no rendered behavior and runs in the fast lane.
      result: pass
      notes: Ownership only governs Auto replacement and is not read by overlay rendering. It is now normalized out of the task identity; the full fast lane passed.
  checks_run:
    - "scripts/ci-tests.sh fast (passed: 1,711 required tests, exit 0)"
    - git diff --check (passed, exit 0)
    - Independent source review confirmed ownership is used for Auto replacement policy and not overlay rendering.
  findings:
    - LocalAdjustmentLayer.ownership was retained by overlayIdentity although it does not affect coverage, causing avoidable task restarts when Auto ownership changes.
  fixes:
    - Normalized ownership in overlayIdentity and added a regression assertion that Auto-to-user ownership changes preserve overlay identity.
  verification_commits:
    - f04b8d75
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T21:42:30.775Z
  session: 01MV4CGCRXLEZ1S3HC
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:08:34.032Z
updated: 2026-10-11T21:42:30.779Z
depends_on:
  - KRMA-848
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T21:37:20.455Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - f04b8d75
---

## Objective

KRMA-848 keys the mask overlay `.task(id:)` on a projection of each layer (`LocalAdjustmentLayer.overlayIdentity`, a private extension in Sources/KromoraKit/Views/MaskingWorkspace.swift) so adjustment-slider ticks stop restarting overlay resolution. The fix was verified only by a manual log capture; a future field added to the layer or the task id could silently bring the restarts back or, worse, stop the overlay from refreshing.

## Work

Make the projection testable without widening production API more than needed (internal rather than private, with a one-line doc stating why), then cover it.

## Acceptance criteria

1. Changing any `LocalAdjustments` value (exposure, contrast, ... ) leaves `overlayIdentity` equal.
2. Changing `name` or `autoProvenance` leaves it equal.
3. Changing components (add, remove, reorder, edit geometry, mode, invert), `isEnabled`, `isInverted` or `amount` makes it differ.
4. A guard test enumerates `LocalAdjustmentLayer`'s Codable keys and fails with a clear message when a new field appears, forcing the author to decide whether it belongs in the overlay identity.
5. Runs in the `fast` lane. No behavior change.

Related: KRMA-848.


### Comment — codex @ 2026-10-11T21:37:19.986Z

Implemented internal testable mask overlay identity with regression coverage for every LocalAdjustments value, ignored name/auto provenance, mask recipe and layer identity changes, and Codable field/key review. Verification: scripts/ci-tests.sh fast passed (1,711 tests); focused MaskOverlayIdentityTests passed (4 tests). Commit: 7ff18c42.

## Agent log

- 2026-10-11T21:42:30.775Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Changing any LocalAdjustments value leaves overlayIdentity equal. (pass) — Coverage includes all 16 adjustment properties; the full fast lane passed.
- [x] Changing name or autoProvenance leaves overlayIdentity equal. (pass)
- [x] Changing layer membership/identity, components, geometry, mode, inversion, enabled state, or amount changes overlayIdentity. (pass) — Regression tests cover component add, remove, reorder, geometry, mode, inversion, layer id, isEnabled, isInverted, and amount.
- [x] A guard test enumerates LocalAdjustmentLayer stored and Codable keys and clearly flags new fields for overlay identity review. (pass) — The test compares reflected stored fields and encoded JSON keys against the reviewed set with explicit failure messages.
- [x] The projection changes no rendered behavior and runs in the fast lane. (pass) — Ownership only governs Auto replacement and is not read by overlay rendering. It is now normalized out of the task identity; the full fast lane passed.
Checks run:
- scripts/ci-tests.sh fast (passed: 1,711 required tests, exit 0)
- git diff --check (passed, exit 0)
- Independent source review confirmed ownership is used for Auto replacement policy and not overlay rendering.
Findings:
- LocalAdjustmentLayer.ownership was retained by overlayIdentity although it does not affect coverage, causing avoidable task restarts when Auto ownership changes.
Fixes:
- Normalized ownership in overlayIdentity and added a regression assertion that Auto-to-user ownership changes preserve overlay identity.
Verification commits:
- f04b8d75
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV4CGCRXLEZ1S3HC
Summary: Counterpoint verification passed; ownership metadata no longer restarts mask overlay resolution.
