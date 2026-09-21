---
id: KRMA-193
title: Masked regional statistics engine
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 918f224
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-04T15:27:31.696Z
  session: 01MTN3Y4WV9MHYL0JC
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:52.925Z
updated: 2026-09-10T12:53:46.076Z
depends_on:
  - KRMA-184
  - KRMA-186
  - KRMA-192
order: de415gxl
board: product
branch: main
commits:
  - 918f224
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/MaskedToneAnalyzer.swift`
**Depends on:** KRMA-184, KRMA-186, KRMA-192
**Epic:** KRMA-181 — see original proposal §15–16 (now generalized over `RegionMask`)

## 1. Problem

This is the ticket that makes the mask-first architecture pay off: **one** engine that computes
`ToneStatistics`/`ColorStatistics` restricted to an arbitrary `RegionMask`, callable identically
by Auto (through `.analysis`-quality masks) and, later, anything that needs "what does the
histogram look like under this selection" for a `.preview`/`.render`-quality mask. There is
exactly one implementation of "statistics through a mask" in the whole codebase after this ticket.

## 2. Requirement (acceptance criteria)

1. A `ToneAnalyzer` (extending or sitting alongside KRMA-192's `GlobalToneAnalyzer`) exposing:
   ```swift
   func statistics(
       image: AnalysisImage,
       through mask: RegionMask
   ) async throws -> (tone: ToneStatistics, color: ColorStatistics)
   ```
   matching the call shape from the architecture proposal:
   ```swift
   let stats = toneAnalyzer.statistics(image: image, through: subjectMask)
   ```
2. Internally reuses KRMA-192's percentile/histogram math with a mask parameter — **do not** fork
   a second histogram implementation. If KRMA-192's internals need a small refactor to accept an
   optional mask, do that here.
3. Respects mask geometry correctly: a masked region's statistics must reflect only pixels the
   mask actually covers (weighted by soft/feathered mask values where the mask isn't binary) —
   this is the "don't average sky pixels caught inside a person's bounding box" correctness bar
   from the original proposal §16, now expressed generically over any `RegionMask` rather than a
   bespoke `RegionGeometry` precedence enum (that precedence problem no longer exists in this
   design — masks from KRMA-188/189/190/191 are always real pixel masks, never bare bounding
   boxes, so there's nothing to prefer between).
4. Statistics computation must not re-resize or re-render the image — operates on the one
   canonical `AnalysisImage` the mask was itself computed against (mismatched-quality/mismatched-
   image inputs should be rejected with a clear error, not silently misaligned).
5. No per-pixel Swift loops over large buffers.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- This ticket does not decide *which* mask is "the subject" — that's KRMA-197. It's purely "given
  any mask, what are the stats under it," reusable by every caller.
- A synthetic `.background` region's statistics (via the `.background` mask from KRMA-190) fall
  out of this for free — no special-casing needed.

## 4. Where to look

- KRMA-192's `GlobalToneAnalyzer` — statistics math to generalize with a mask parameter.
- KRMA-184's `RegionMask`; KRMA-186's `MaskOperations` (for feathered/composed masks as input).
- Original proposal §15–16.

## 5. Testing

- `Tests/LumoKitTests/MaskedToneAnalyzerTests.swift` (new): synthetic fixture with a known bright
  foreground region and dark background — assert masked stats through the foreground mask and
  through the `.background` mask differ correctly, and both differ from the naive whole-image
  average. Soft/feathered mask test: assert a feathered mask's edge pixels are appropriately
  down-weighted rather than binary-included/excluded. Mismatched image/mask input rejected
  cleanly.

## Agent log

- 2026-09-04T15:27:31.697Z: Verification report
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
- 918f224
Actor: codex
Resolved model: unknown
Pickup session: 01MTN3Y4WV9MHYL0JC
Summary: Added shared masked regional tone/color statistics with weighted soft-mask histograms, canonical image/mask validation, renderer seam, and focused tests.
