---
id: KRMA-812
title: "Epic: Submission readiness and sandboxed acceptance"
type: feature
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A sandboxed-build acceptance checklist exists and KRMA-059 points to it.
      result: pass
      notes: KRMA-806 passed; the acceptance checklist exists and KRMA-059 links to it.
    - criterion: Submission answers, review notes, and metadata drafts exist with evidence.
      result: pass
      notes: KRMA-807 passed; the submission material is documented in docs/APP_STORE_SUBMISSION.md.
    - criterion: Human-only steps are listed explicitly.
      result: pass
      notes: KRMA-806 and KRMA-807 passed; the acceptance checklist and submission notes identify human-only actions.
  checks_run:
    - Confirmed declared child issues KRMA-806 and KRMA-807 are done with verification_report.verdict=pass.
    - git merge-base --is-ancestor for each declared child commit against HEAD 59f9039f (all passed).
    - Confirmed docs/APP_STORE_ACCEPTANCE.md and docs/APP_STORE_SUBMISSION.md are present.
    - Reviewed the child reports and their references from KRMA-059.
  findings: []
  fixes: []
  verification_commits:
    - 415e031f
    - d770d7d1
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-05T14:50:53.213Z
  session: 01MUVDAF2H9M4KFB9D
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - epic
  - appstore
created: 2026-10-03T19:25:31.498Z
updated: 2026-10-05T14:50:53.217Z
depends_on:
  - KRMA-806
  - KRMA-807
blockers: []
order: a0
board: product
commits:
  - 415e031f
  - d770d7d1
---

## Completion disposition

This aggregate tracking parent is complete: each declared child dependency is done with a passing verification report, and each child implementation commit is present in repository history.

## Objective

Prepare the material and the checklist that the human submitter needs to validate the sandboxed build and file the App Store Connect record.

Source plan: `.context/2026-09-30-app-store-release-plan.md` (Plan success criteria).

## Outcome

- [x] A sandboxed-build acceptance checklist exists and KRMA-059 points to it.
- [x] Submission answers, review notes, and metadata drafts exist with evidence.
- [x] Human-only steps are listed explicitly.

## Child tickets (in execution order)

- KRMA-806 — Write the sandboxed-build acceptance checklist and fold it into KRMA-059
- KRMA-807 — Prepare App Store Connect submission material: privacy answers, review notes, metadata

## Agent log

- 2026-10-05T14:50:53.213Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A sandboxed-build acceptance checklist exists and KRMA-059 points to it. (pass) — KRMA-806 passed; the acceptance checklist exists and KRMA-059 links to it.
- [x] Submission answers, review notes, and metadata drafts exist with evidence. (pass) — KRMA-807 passed; the submission material is documented in docs/APP_STORE_SUBMISSION.md.
- [x] Human-only steps are listed explicitly. (pass) — KRMA-806 and KRMA-807 passed; the acceptance checklist and submission notes identify human-only actions.
Checks run:
- Confirmed declared child issues KRMA-806 and KRMA-807 are done with verification_report.verdict=pass.
- git merge-base --is-ancestor for each declared child commit against HEAD 59f9039f (all passed).
- Confirmed docs/APP_STORE_ACCEPTANCE.md and docs/APP_STORE_SUBMISSION.md are present.
- Reviewed the child reports and their references from KRMA-059.
Findings:
- None
Fixes:
- None
Verification commits:
- 415e031f
- d770d7d1
Actor: codex
Resolved model: unknown
Pickup session: 01MUVDAF2H9M4KFB9D
Summary: Verified: both submission readiness tickets are done with passing reports and their commits are in repository history.
