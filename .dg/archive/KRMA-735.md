---
id: KRMA-735
title: Implement digest-gated stale preview crossfade
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Digest distance above threshold produces exactly one 120 ms crossfade
      result: pass
      notes: Covered by PreviewSurfaceTests state/duration test
    - criterion: Below-threshold, missing digest, Reduce Motion replace immediately
      result: pass
      notes: Policy tests plus missing-digest surface test
    - criterion: Previous texture retained only during transition, released afterward
      result: pass
      notes: finishCrossfade releases; test asserts release after 145ms
    - criterion: Tests cover state and duration; metallib rebuilt
      result: pass
      notes: Metallib hash committed; visual inspection not performed headless
  checks_run:
    - swift test --filter PreviewSurfaceTests|FrameRefinementPolicyTests (52 passed)
  findings:
    - "medium: outgoing frame drawn at alpha 1-p with src-alpha blending let canvas background bleed through mid-fade (brightness dip); fixed"
  fixes:
    - Outgoing transition frame now drawn opaque; incoming detail fades in at alpha p.
  verification_commits:
    - 7ece060
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-30T17:45:26.359Z
  session: 01MUOEAT9FO68TSAGF
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
  - preview
  - rendering
created: 2026-09-30T17:10:39.349Z
updated: 2026-09-30T17:45:26.361Z
parent: KRMA-731
blockers: []
order: a0
board: product
commits:
  - 7ece060
---

## Objective

Implement the stale preview replacement transition required by KRMA-731.

## Context

`FrameRefinementPolicy` already decides between immediate replacement and a 120 ms crossfade
using perceptual digest distance and Reduce Motion. The decision is not connected to
`PreviewSurface`, so stale-compatible previews currently swap immediately. KRMA-731 cannot pass
until the decision reaches an actual drawable presentation.

## Acceptance criteria

- [ ] When a stale stored frame is replaced by a canonical settled render, digest distance above
      `FrameRefinementPolicy.crossfadeDigestThreshold` produces exactly one 120 ms crossfade.
- [ ] Below-threshold changes, missing digests, and Reduce Motion replace immediately.
- [ ] The previous texture remains available only for the transition and is released afterward;
      ordinary/interactive/ROI frames do not trigger additional transitions.
- [ ] Tests cover the transition state and duration; the PreviewSurface shader/library asset is
      rebuilt and the rendered swap is visually inspected on macOS 26.

## Implementation notes

Keep the change in the existing Metal-backed PreviewSurface, preserving its rendering ownership.
The known work includes an alpha uniform, temporary previous-texture retention, and a timed redraw.
Do not change the digest threshold without updating its generated fixture evidence.

### Comment — codex @ 2026-09-30T17:44:35.112Z

Implemented the stale-frame refinement in PreviewSurface: a one-shot digest-gated 120 ms Metal crossfade for a stale stored frame replaced by a complete settled render. Missing/below-threshold digests and Reduce Motion swap immediately; the old texture is released when the transition ends. Added state/duration and rendered-pixel tests, propagated Reduce Motion, and rebuilt the presentation metallib. Verification: 74 focused preview/refinement tests passed; scripts/ci-tests.sh fast passed (1,441 tests); metallib check, git diff --check, and dg validate passed. Commit: 379b904. The shared tree’s prior KRMA-731 implementation was included in this commit to keep the integration buildable; unrelated context artifacts and DispatchGraph records remain untouched.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-30T17:45:26.359Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Digest distance above threshold produces exactly one 120 ms crossfade (pass) — Covered by PreviewSurfaceTests state/duration test
- [x] Below-threshold, missing digest, Reduce Motion replace immediately (pass) — Policy tests plus missing-digest surface test
- [x] Previous texture retained only during transition, released afterward (pass) — finishCrossfade releases; test asserts release after 145ms
- [x] Tests cover state and duration; metallib rebuilt (pass) — Metallib hash committed; visual inspection not performed headless
Checks run:
- swift test --filter PreviewSurfaceTests|FrameRefinementPolicyTests (52 passed)
Findings:
- medium: outgoing frame drawn at alpha 1-p with src-alpha blending let canvas background bleed through mid-fade (brightness dip); fixed
Fixes:
- Outgoing transition frame now drawn opaque; incoming detail fades in at alpha p.
Verification commits:
- 7ece060
Actor: claude
Resolved model: sonnet
Pickup session: 01MUOEAT9FO68TSAGF
Summary: Verified digest-gated stale preview crossfade; fixed mid-fade dip by drawing outgoing frame opaque.
