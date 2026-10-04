---
id: KRMA-809
title: "Epic: Remove direct distribution (updater, DMG, Developer ID)"
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
created: 2026-10-03T19:25:16.328Z
updated: 2026-10-03T19:25:18.726Z
depends_on:
  - KRMA-786
  - KRMA-787
  - KRMA-788
  - KRMA-789
blockers: []
order: zzzzzzv
board: product
---

## Current disposition

This is a **tracking parent**. Keep it in `backlog`. Do not claim it, do not `dg issue prepare` it, and do not implement several child tickets in one session. Its dependencies encode the aggregate completion condition.

## Objective

Carry one shipping channel instead of two. Delete the GitHub updater, its flag, the DMG release script, and docs for them.

Source plan: `.context/2026-09-30-app-store-release-plan.md` (Plan Workstream 5).

## Outcome

- [ ] No `KROMORA_DIRECT_DISTRIBUTION` flag, updater code, updater UI, or `Process()` use remains in the app.
- [ ] `scripts/release-dmg.sh` and DMG/notarization docs are gone.
- [ ] `swift build`, `swift test` lanes, and `swift run` behave as before.

## Child tickets (in execution order)

- KRMA-786 — Remove updater call sites and KROMORA_DIRECT_DISTRIBUTION conditionals from app code
- KRMA-787 — Delete the updater implementation files and their tests
- KRMA-788 — Remove the KROMORA_DIRECT_DISTRIBUTION build flag from Package.swift
- KRMA-789 — Delete the DMG release script and prune direct-distribution docs
