---
id: KRMA-812
title: "Epic: Submission readiness and sandboxed acceptance"
type: feature
status: backlog
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - epic
  - appstore
created: 2026-10-03T19:25:31.498Z
updated: 2026-10-03T19:25:33.706Z
depends_on:
  - KRMA-806
  - KRMA-807
blockers: []
order: zzzzzzz
board: product
---

## Current disposition

This is a **tracking parent**. Keep it in `backlog`. Do not claim it, do not `dg issue prepare` it, and do not implement several child tickets in one session. Its dependencies encode the aggregate completion condition.

## Objective

Prepare the material and the checklist that the human submitter needs to validate the sandboxed build and file the App Store Connect record.

Source plan: `.context/2026-09-30-app-store-release-plan.md` (Plan success criteria).

## Outcome

- [ ] A sandboxed-build acceptance checklist exists and KRMA-059 points to it.
- [ ] Submission answers, review notes, and metadata drafts exist with evidence.
- [ ] Human-only steps are listed explicitly.

## Child tickets (in execution order)

- KRMA-806 — Write the sandboxed-build acceptance checklist and fold it into KRMA-059
- KRMA-807 — Prepare App Store Connect submission material: privacy answers, review notes, metadata
