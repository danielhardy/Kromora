---
id: KRMA-684
title: Reassess KRMA-683 now that Remove render-engine path is deleted
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Decide whether KRMA-683 should be closed/superseded (Remove stays retired) or re-scoped to the current Heal/Clone render path.
      result: pass
      notes: KRMA-683 closed as superseded by KRMA-681/04100fa; confirmed PatchMatchInpainter.swift and resolveRemoveFills are deleted and the referenced corpus test method no longer exists in the tree.
    - criterion: Clear or update KRMA-683's stale blocked_reason/blocked_action frontmatter to match its actual status.
      result: pass
      notes: "Current KRMA-683.md has no blocked_reason/blocked_action fields (verified via grep); the resolved human blocker remains recorded in the blockers: list with resolved_at populated, and status is done."
    - criterion: If re-scoped, update its acceptance criteria and referenced test/command names, since testRemoveQualityAcrossGroundTruthCorpusThroughRenderEngine no longer exists.
      result: pass
      notes: "Not applicable: issue was closed/superseded rather than re-scoped, consistent with the KRMA-668 precedent."
  checks_run:
    - git show --stat 536ce71 / 04100fa to confirm the disposition matches the actual retirement diff
    - grep for blocked_reason/blocked_action in KRMA-683.md (none found)
    - grep for testRemoveQualityAcrossGroundTruthCorpusThroughRenderEngine, resolveRemoveFills, PatchMatchInpainter across Sources/Tests (none found)
    - grep for Remove in docs/RETOUCH.md (no stale references)
    - swift build (pass)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T15:32:43.751Z
  session: 01MULEO03WXMR26VHV
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - retouch
created: 2026-09-28T13:40:40.578Z
updated: 2026-09-28T15:32:43.754Z
parent: KRMA-681
blockers: []
order: a0
board: product
---

## Objective

Decide the disposition of KRMA-683 ("Investigate Remove render-engine quality regressions") now
that KRMA-681 has retired the Remove retouch mode and deleted its render-engine integration
(commit 04100fa).

## Context

KRMA-681's acceptance criteria call for reassessing or closing obsolete Remove-only follow-up
work, naming KRMA-668 as one example. KRMA-668 was marked superseded and closed as part of
KRMA-681's implementation. KRMA-683 is the same kind of Remove-only follow-up (it targets
`RenderEngine`/`RetouchRenderer` Remove-path regressions and a corpus test method that no longer
exists) but was not reassessed by that implementation.

A human already added and resolved a blocker on KRMA-683 flagging this exact conflict
(`Current main retired Remove in 04100fa ... Decide whether to reintroduce Remove now for
KRMA-683 or keep it retired and close/re-scope this issue`, resolved 2026-09-28T13:18:52Z), and
the issue was briefly moved to `review` before returning to `ready` at 2026-09-28T13:30:39Z. Its
`blocked_reason`/`blocked_action` fields are still populated even though the blocker event shows
resolved. This ticket exists to make sure KRMA-683 does not linger in a stale, unactionable state.

## Acceptance criteria

- [ ] Decide whether KRMA-683 should be closed/superseded (Remove stays retired) or re-scoped to
      the current Heal/Clone render path.
- [ ] Clear or update KRMA-683's stale `blocked_reason`/`blocked_action` frontmatter to match its
      actual status.
- [ ] If re-scoped, update its acceptance criteria and referenced test/command names, since
      `testRemoveQualityAcrossGroundTruthCorpusThroughRenderEngine` no longer exists.

## Implementation notes

See `.dg/issues/KRMA-683.md` and `.dg/issues/KRMA-668.md` for the superseded-ticket pattern to
follow if closing.

### Comment — codex @ 2026-09-28T15:31:38.422Z

KRMA-683 is closed as superseded by KRMA-681 and commit 04100fa. Its stale blocked fields are cleared while the resolved blocker history remains; the note records that the reported regression applied only to the removed Remove pipeline. Changes committed as 536ce71.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-28T15:32:43.751Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Decide whether KRMA-683 should be closed/superseded (Remove stays retired) or re-scoped to the current Heal/Clone render path. (pass) — KRMA-683 closed as superseded by KRMA-681/04100fa; confirmed PatchMatchInpainter.swift and resolveRemoveFills are deleted and the referenced corpus test method no longer exists in the tree.
- [x] Clear or update KRMA-683's stale blocked_reason/blocked_action frontmatter to match its actual status. (pass) — Current KRMA-683.md has no blocked_reason/blocked_action fields (verified via grep); the resolved human blocker remains recorded in the blockers: list with resolved_at populated, and status is done.
- [x] If re-scoped, update its acceptance criteria and referenced test/command names, since testRemoveQualityAcrossGroundTruthCorpusThroughRenderEngine no longer exists. (pass) — Not applicable: issue was closed/superseded rather than re-scoped, consistent with the KRMA-668 precedent.
Checks run:
- git show --stat 536ce71 / 04100fa to confirm the disposition matches the actual retirement diff
- grep for blocked_reason/blocked_action in KRMA-683.md (none found)
- grep for testRemoveQualityAcrossGroundTruthCorpusThroughRenderEngine, resolveRemoveFills, PatchMatchInpainter across Sources/Tests (none found)
- grep for Remove in docs/RETOUCH.md (no stale references)
- swift build (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULEO03WXMR26VHV
Summary: Verified KRMA-683 disposition: correctly closed as superseded by KRMA-681/04100fa, stale blocker fields cleared with resolved history retained, no re-scope needed since Remove render path and its corpus test are confirmed deleted.
