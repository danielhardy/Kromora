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
updated: 2026-10-05T13:27:01.197Z
depends_on:
  - KRMA-782
  - KRMA-783
  - KRMA-784
  - KRMA-785
  - KRMA-790
  - KRMA-798
blockers: []
order: zzzzzzzq
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
- [ ] The App Store Connect privacy posture is documented from the app's and partners' actual data practices.
- [ ] The required-reason manifest scope is documented accurately: Kromora's native macOS target does not need required-reason entries solely for its API calls; mandatory third-party SDK manifests or future covered platforms are handled separately.

## Child tickets (in execution order)

- KRMA-782 — Add the Photos library usage description to the app Info.plist
- KRMA-783 — App Sandbox audit 1/3: import, open, drag-drop, and security-scoped access
- KRMA-784 — App Sandbox audit 2/3: export, Photos, storage, caches, and temp files
- KRMA-785 — App Sandbox audit 3/3: network, subprocesses, resources, and protected-API inventory
- KRMA-790 — Trim entitlements to the capabilities Kromora actually uses
- KRMA-798 — Document native macOS required-reason privacy scope


### Comment — codex @ 2026-10-05T04:16:02.556Z

Reviewed the tracking parent and its outcomes. The six listed dependencies are done, with the sandbox audit, Photos usage description, minimal asserted entitlements, submission privacy worksheet, and native macOS required-reason scope documented. Per this issue's current disposition, no child implementation belongs in this session; releasing the claim and keeping KRMA-808 in backlog.


### Comment — codex @ 2026-10-05T13:18:53.392Z

codex pickup review: this parent is explicitly tracking-only, and all six declared child dependencies are already done with passing verification reports. The scoped work is complete; no additional implementation belongs in this session.
