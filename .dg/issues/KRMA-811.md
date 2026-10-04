---
id: KRMA-811
title: "Epic: Production build verification, CI, and documentation"
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
created: 2026-10-03T19:25:24.781Z
updated: 2026-10-03T19:25:30.945Z
depends_on:
  - KRMA-800
  - KRMA-801
  - KRMA-802
  - KRMA-803
  - KRMA-804
  - KRMA-805
blockers: []
order: zzzzzzy
board: product
---

## Current disposition

This is a **tracking parent**. Keep it in `backlog`. Do not claim it, do not `dg issue prepare` it, and do not implement several child tickets in one session. Its dependencies encode the aggregate completion condition.

## Objective

Make the production build repeatable and guarded: release script, CI job, one packaging path, an invariant test, and agent and packaging docs.

Source plan: `.context/2026-09-30-app-store-release-plan.md` (Plan Workstreams 6, 7, 8).

## Outcome

- [ ] `scripts/app-store-build.sh` verifies the production app locally and archives on request, with no upload step.
- [ ] CI builds and verifies the Xcode app on `main`.
- [ ] Only one packaging path remains; an invariant test protects the thin-Xcode-layer rule.
- [ ] CLAUDE.md and docs/PACKAGING.md describe the new model.

## Child tickets (in execution order)

- KRMA-800 — Add scripts/app-store-build.sh to verify and archive the production target
- KRMA-801 — Add an Xcode production-build CI job and verify the app it builds
- KRMA-802 — Retire scripts/build-macos-app.sh: package and smoke CI use the Xcode-built app
- KRMA-803 — Add a structural test that the Xcode project stays a thin packaging layer
- KRMA-804 — Document the build architecture invariant for agents in CLAUDE.md and AGENTS.md
- KRMA-805 — Rewrite docs/PACKAGING.md and README distribution notes for App Store, TestFlight, and source
