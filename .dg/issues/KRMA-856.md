---
id: KRMA-856
title: Test that mask overlay task identity ignores adjustments but tracks mask changes
type: task
status: backlog
priority: low
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:08:34.032Z
updated: 2026-10-10T13:08:42.097Z
depends_on:
  - KRMA-848
blockers: []
order: zzy
board: product
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
