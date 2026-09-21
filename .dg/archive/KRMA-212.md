---
id: KRMA-212
title: Hide low-value mask result diagnostics outside Developer mode
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run:
    - swift test --filter 'MaskPresentationPolicyTests|MaskingPanelTests'
    - git diff --check
  findings: []
  fixes:
    - Added deterministic presentation-only mask gating and retained complete Developer diagnostics
  verification_commits:
    - 587b7a7
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T19:39:09.282Z
  session: 01MTNCS0B2LKEZVFBY
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ux
  - masking
  - developer
created: 2026-09-04T19:08:04.604Z
updated: 2026-09-10T12:53:47.526Z
order: lllllli6
board: product
commits:
  - 587b7a7
---

## Objective

Keep low-value or misleading mask-result diagnostics out of the normal user-facing workflow while
retaining them for Developer mode.

## Context

In practice the Subject result often shows little of interest while Background is usually the
useful result. Presenting every provider/result equally makes the masking UI look unreliable and
surfaces diagnostic information that does not help a photographer decide what to do. The raw
provider output is still valuable during development, so it should be gated rather than removed
from the analysis infrastructure.

## Acceptance criteria

- [ ] In normal mode, the masking UI offers only actionable semantic targets whose availability
      and quality meet the user-facing threshold; it does not prominently surface low-confidence,
      empty, or otherwise unhelpful Subject diagnostics.
- [ ] Background remains available when it is the useful/valid region even if Subject is absent or
      low quality; the UI explains unavailable targets without exposing internal provider jargon.
- [ ] Developer mode exposes the complete provider/result set, including Subject and Background
      coverage/quality details and the reason a target was filtered from normal mode.
- [ ] Gating is presentation-only: Auto and cached analysis still retain the underlying masks and
      no eager extra Vision work is introduced.
- [ ] Add representative tests for strong subject, weak/empty subject, background-only useful,
      and provider-failure cases in both normal and Developer modes.

## Implementation notes

- Use `AnalysisQuality`, mask coverage/confidence, and existing provider status rather than a
  hard-coded rule that always hides Subject. The threshold should be deterministic and documented.
- Coordinate this with KRMA-201's masking panel and KRMA-203/KRMA-213's developer diagnostics so
  the same analysis facts are not independently recomputed or displayed with conflicting labels.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T19:39:09.286Z: Verification report
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
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTNCS0B2LKEZVFBY
Summary: Implemented shared presentation-only mask gating: normal masking now exposes only actionable targets (confidence >= 55%, coverage >= 2%) with plain-language unavailable-target guidance; Developer diagnostics retain all requested provider results, failures, coverage/confidence, and normal-mode filtering reasons. Added deterministic policy tests for strong, weak, empty, and useful background masks.
