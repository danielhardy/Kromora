---
id: KRMA-808
title: "Epic: App Store compatibility, privacy, and entitlements"
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
created: 2026-10-03T19:25:12.534Z
updated: 2026-10-03T19:25:15.819Z
depends_on:
  - KRMA-782
  - KRMA-783
  - KRMA-784
  - KRMA-785
  - KRMA-790
  - KRMA-798
blockers: []
order: zzzzzzq
board: product
---

## Current disposition

This is a **tracking parent**. Keep it in `backlog`. Do not claim it, do not `dg issue prepare` it, and do not implement several child tickets in one session. Its dependencies encode the aggregate completion condition.

## Objective

Establish by audit and then by minimal configuration that Kromora can run inside the App Sandbox with only the capabilities and purpose strings it truly uses, and declare its privacy posture.

Source plan: `.context/2026-09-30-app-store-release-plan.md` (Plan Workstreams 0, 3, 4).

## Outcome

- [ ] The sandbox audit document is complete and every blocker has a ticket.
- [ ] The Photos usage string is present; no unneeded permission strings exist.
- [ ] Entitlements are the minimal audited set and are asserted by verification scripts.
- [ ] A privacy manifest declares required-reason API use and no tracking.

## Child tickets (in execution order)

- KRMA-782 — Add the Photos library usage description to the app Info.plist
- KRMA-783 — App Sandbox audit 1/3: import, open, drag-drop, and security-scoped access
- KRMA-784 — App Sandbox audit 2/3: export, Photos, storage, caches, and temp files
- KRMA-785 — App Sandbox audit 3/3: network, subprocesses, resources, and protected-API inventory
- KRMA-790 — Trim entitlements to the capabilities Kromora actually uses
- KRMA-798 — Add a PrivacyInfo.xcprivacy manifest declaring required-reason API use
