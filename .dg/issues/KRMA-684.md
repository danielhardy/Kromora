---
id: KRMA-684
title: Reassess KRMA-683 now that Remove render-engine path is deleted
type: task
status: claimed
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - retouch
created: 2026-09-28T13:40:40.578Z
updated: 2026-09-28T15:28:36.290Z
parent: KRMA-681
blockers: []
order: zzz
board: product
claim:
  actor: codex
  session: 01MULEJYYPT3QG46M5
  claimed_at: 2026-09-28T15:28:36.289Z
  expires_at: 2026-09-28T16:28:36.289Z
  model: gpt-6-luna
  stage: implementation
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
