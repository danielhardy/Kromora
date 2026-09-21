---
id: KRMA-216
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
updated: 2026-09-21T02:11:37.597Z
order: zutdjahx
board: product
---

## Objective

Deliver a Lightroom-style masking system in which photographers can create Smart Foreground,
Smart Background, Brush, Linear Gradient, and Radial Gradient masks, apply local adjustments, and
return later to edit every mask and setting non-destructively.

## Context

KRMA-201 and KRMA-202 proved semantic mask selection and render-quality refinement, but the current
Masking sheet cannot attach a mask to `EditDocument` or affect rendered pixels. The durable product
plan is `docs/ENGINEERING_GUIDE.md`.

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

This is a tracking epic and depends on KRMA-217 through KRMA-226. The dependency graph is
authoritative; close the epic only after every required child is verified and the integrated
Definition of Done in `docs/ENGINEERING_GUIDE.md` passes.

Existing KRMA-201/KRMA-202 behavior is an input, not a second masking product. Retire or reduce the
selection-only sheet once the persistent workspace replaces it.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
