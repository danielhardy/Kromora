---
id: LUMO-216
title: Masking and local adjustments (epic)
type: feature
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic
  - epic:masking
  - masking
  - local-adjustments
created: 2026-09-04T21:48:28.079Z
updated: 2026-09-07T04:02:56.077Z
depends_on:
  - LUMO-217
  - LUMO-218
  - LUMO-219
  - LUMO-220
  - LUMO-221
  - LUMO-222
  - LUMO-223
  - LUMO-224
  - LUMO-225
  - LUMO-226
order: zutdjahx
board: product
---

## Objective

Deliver a Lightroom-style masking system in which photographers can create Smart Foreground,
Smart Background, Brush, Linear Gradient, and Radial Gradient masks, apply local adjustments, and
return later to edit every mask and setting non-destructively.

## Context

LUMO-201 and LUMO-202 proved semantic mask selection and render-quality refinement, but the current
Masking sheet cannot attach a mask to `EditDocument` or affect rendered pixels. The durable product
plan is `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`.

The implementation must preserve Lumo's value-state document, single render path, source/revision
safety, on-device processing, Swift 6 concurrency guarantees, and zero-dependency policy.

## Acceptance criteria

- [ ] Foreground, Background, Brush, Linear, and Radial masks can be created from the main canvas.
- [ ] Any saved mask can be reselected and its name, geometry/refinement, amount, invert, enabled
      state, component settings, and local adjustments can be edited.
- [ ] Masks support non-destructive Add, Subtract, and Intersect components.
- [ ] Masked edits survive undo/redo, reopen, cache deletion where applicable, copy/paste, reset,
      comparison, and full-resolution export.
- [ ] Preview and export agree, while neutral/unmasked documents retain their current pixels.
- [ ] Brush and handle interaction meet the measured latency/memory budgets in the product plan.
- [ ] Accessibility, cancellation, rapid source switching, failure recovery, and performance gates
      pass without a new live-path `CIContext`, network processing, or concurrency escape hatch.

## Implementation notes

This is a tracking epic and depends on LUMO-217 through LUMO-226. The dependency graph is
authoritative; close the epic only after every required child is verified and the integrated
Definition of Done in `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md` passes.

Existing LUMO-201/LUMO-202 behavior is an input, not a second masking product. Retire or reduce the
selection-only sheet once the persistent workspace replaces it.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
