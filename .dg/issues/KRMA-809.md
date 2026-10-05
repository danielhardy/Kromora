---
id: KRMA-809
title: "Epic: Remove direct distribution (updater, DMG, Developer ID)"
type: feature
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: No KROMORA_DIRECT_DISTRIBUTION flag, updater code, updater UI, or Process() use remains in the app.
      result: pass
      notes: KRMA-786 and KRMA-787 passed with removal and call-site checks.
    - criterion: scripts/release-dmg.sh and DMG/notarization docs are gone.
      result: pass
      notes: KRMA-789 passed; the DMG release path and its documentation were removed.
    - criterion: swift build, swift test lanes, and swift run behave as before.
      result: pass
      notes: KRMA-786–789 have passing verification reports covering the retained package build, test, and run behavior.
  checks_run:
    - Confirmed declared child issues KRMA-786, KRMA-787, KRMA-788, and KRMA-789 are done with verification_report.verdict=pass.
    - git merge-base --is-ancestor for each declared child commit against HEAD 59f9039f (all passed).
    - Reviewed the per-child verification reports for updater removal, package flag removal, and release documentation cleanup.
  findings: []
  fixes: []
  verification_commits:
    - 0a2bc3c9
    - cc0a42ec
    - 76735a73
    - "91e40540"
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-05T14:50:48.664Z
  session: 01MUVDABLEH14R3CJ8
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - epic
  - appstore
created: 2026-10-03T19:25:16.328Z
updated: 2026-10-05T14:50:48.668Z
depends_on:
  - KRMA-786
  - KRMA-787
  - KRMA-788
  - KRMA-789
blockers: []
order: a0
board: product
commits:
  - 0a2bc3c9
  - cc0a42ec
  - 76735a73
  - "91e40540"
---

## Completion disposition

This aggregate tracking parent is complete: each declared child dependency is done with a passing verification report, and each child implementation commit is present in repository history.

## Objective

Carry one shipping channel instead of two. Delete the GitHub updater, its flag, the DMG release script, and docs for them.

Source plan: `.context/2026-09-30-app-store-release-plan.md` (Plan Workstream 5).

## Outcome

- [x] No `KROMORA_DIRECT_DISTRIBUTION` flag, updater code, updater UI, or `Process()` use remains in the app.
- [x] `scripts/release-dmg.sh` and DMG/notarization docs are gone.
- [x] `swift build`, `swift test` lanes, and `swift run` behave as before.

## Child tickets (in execution order)

- KRMA-786 — Remove updater call sites and KROMORA_DIRECT_DISTRIBUTION conditionals from app code
- KRMA-787 — Delete the updater implementation files and their tests
- KRMA-788 — Remove the KROMORA_DIRECT_DISTRIBUTION build flag from Package.swift
- KRMA-789 — Delete the DMG release script and prune direct-distribution docs


### Comment — codex @ 2026-10-05T04:13:15.219Z

KRMA-809 is an aggregate tracking parent; implementation is split across KRMA-786–789, all already marked done with verification recorded. No parent-level code changes are scoped. Releasing this claim and restoring backlog per the issue's current disposition.

## Agent log

- 2026-10-05T14:50:48.664Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] No KROMORA_DIRECT_DISTRIBUTION flag, updater code, updater UI, or Process() use remains in the app. (pass) — KRMA-786 and KRMA-787 passed with removal and call-site checks.
- [x] scripts/release-dmg.sh and DMG/notarization docs are gone. (pass) — KRMA-789 passed; the DMG release path and its documentation were removed.
- [x] swift build, swift test lanes, and swift run behave as before. (pass) — KRMA-786–789 have passing verification reports covering the retained package build, test, and run behavior.
Checks run:
- Confirmed declared child issues KRMA-786, KRMA-787, KRMA-788, and KRMA-789 are done with verification_report.verdict=pass.
- git merge-base --is-ancestor for each declared child commit against HEAD 59f9039f (all passed).
- Reviewed the per-child verification reports for updater removal, package flag removal, and release documentation cleanup.
Findings:
- None
Fixes:
- None
Verification commits:
- 0a2bc3c9
- cc0a42ec
- 76735a73
- 91e40540
Actor: codex
Resolved model: unknown
Pickup session: 01MUVDABLEH14R3CJ8
Summary: Verified: all four direct-distribution removal tickets are done with passing reports and their commits are in repository history.
