---
id: KRMA-262
title: Scope load status to the photo that produced it
type: task
status: done
priority: low
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Loading a healthy photo after a corrupt one reports its own ready outcome while the corrupt record remains corrupt on its own loads
      result: pass
    - criterion: Deliberately sticky store diagnostic behavior is explicit and covered by a named regression test
      result: pass
  checks_run:
    - swift test --filter EditDocumentStoreTests (16 passed, 0 failures)
    - swift build -c release (passed)
    - git diff --check (passed)
    - dg validate (OK; pre-existing unknown pickup-runner model warning)
  findings: []
  fixes: []
  verification_commits:
    - d273581
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T17:16:29.281Z
  session: 01MTUCVMLI4XXUJMOQ
labels:
  - persistence
  - ui
created: 2026-09-07T01:10:27.053Z
updated: 2026-09-10T12:53:51.625Z
depends_on:
  - KRMA-244
order: x8
board: product
commits:
  - d273581
---

## Objective

A load result should report the status produced by *that* load, not whatever sticky status a
previous photo left behind.

## Context

`status` is store-level and sticky: `load(for:)` returns the ambient `status` in every result,
including paths that did nothing actionable. After photo A loads `.corrupt`, opening unrelated
photo B returns `.corrupt` too — the banner/checks downstream cannot tell "this photo's record
is damaged" from "some earlier photo's was". `save` resetting to `.ready` papers over part of
this, but read-only sessions (the common culling case) never save.

## Work

- Track the status transitions within a single `load` call and return that per-load status in
  `EditDocumentLoadResult`, while keeping a separate store-level "worst actionable status" only
  where the UI genuinely needs latch-until-acknowledged behavior. If the UI relies on
  stickiness, say so explicitly per status case (`.relinked` arguably wants to survive until the
  user sees it; `.corrupt` for photo A must not taint photo B).
- `restoreActionableStatus` is the current mechanism — rework or justify it as part of this.

## Acceptance criteria

- [ ] Loading a healthy photo after a corrupt one reports `.ready` (or the healthy photo's own
      outcome), while the corrupt record still reports `.corrupt` on its own loads.
- [ ] Any deliberately sticky banner behavior is covered by a test naming the case.

## Agent log

- 2026-09-09T17:16:29.281Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Loading a healthy photo after a corrupt one reports its own ready outcome while the corrupt record remains corrupt on its own loads (pass)
- [x] Deliberately sticky store diagnostic behavior is explicit and covered by a named regression test (pass)
Checks run:
- swift test --filter EditDocumentStoreTests (16 passed, 0 failures)
- swift build -c release (passed)
- git diff --check (passed)
- dg validate (OK; pre-existing unknown pickup-runner model warning)
Findings:
- None
Fixes:
- None
Verification commits:
- d273581
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTUCVMLI4XXUJMOQ
Summary: Scoped edit-store load outcomes to the active photo, documented the explicit sticky worst diagnostic policy, and named regression coverage for corrupt-photo banner isolation.
