---
id: KRMA-810
title: "Epic: One app, two tiny launchers (KromoraKit scene plus Xcode target)"
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
created: 2026-10-03T19:25:19.249Z
updated: 2026-10-05T13:27:02.376Z
depends_on:
  - KRMA-791
  - KRMA-792
  - KRMA-793
  - KRMA-794
  - KRMA-795
  - KRMA-796
  - KRMA-797
  - KRMA-799
blockers: []
order: zzzzzzzx
board: product
---

## Current disposition

This is a **tracking parent**. Keep it in `backlog`. Do not claim it, do not `dg issue prepare` it, and do not implement several child tickets in one session. Its dependencies encode the aggregate completion condition.

## Objective

Move all app wiring into KromoraKit and add the Xcode project as a thin packaging layer around it.

Source plan: `.context/2026-09-30-app-store-release-plan.md` (Plan Workstreams 1, 2, and the target layout).

## Outcome

- [ ] Both `@main` launchers are tiny and share `KromoraAppDelegate` and `KromoraScene`.
- [ ] `Xcode/Kromora.xcodeproj` builds a signed-capable, sandboxed `Kromora.app` linking only KromoraKit.
- [ ] Bundle metadata, icon, entitlements, and resource bundle are verified on the Xcode-built app.

## Child tickets (in execution order)

- KRMA-791 — Move AppDelegate into KromoraKit as a public KromoraAppDelegate
- KRMA-792 — Add a public KromoraScene and reduce the SwiftPM launcher to a tiny shim
- KRMA-793 — Move Info.plist, entitlements, assets, and branding into a top-level App/ folder
- KRMA-794 — Create Xcode/Kromora.xcodeproj: app target linking the local KromoraKit package
- KRMA-795 — Add Base/Debug/Release xcconfig files and attach them to the Xcode project
- KRMA-796 — Wire Info.plist, App Sandbox, hardened runtime, and entitlements into the Xcode target
- KRMA-797 — Wire the app icon and asset catalog into the Xcode target
- KRMA-799 — Add scripts/verify-xcode-app.sh and prove the SwiftPM resource bundle is embedded


### Comment — codex @ 2026-10-05T13:14:53.779Z

KRMA-810 is a tracking parent. Its listed dependencies KRMA-791, KRMA-792, KRMA-793, KRMA-794, KRMA-795, KRMA-796, KRMA-797, and KRMA-799 are all done, and the aggregate launcher/Xcode packaging outcome is already present. Per the issue's Current disposition, no child implementation is being repeated here and the parent should remain in backlog. Releasing this claim.
