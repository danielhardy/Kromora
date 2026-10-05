---
id: KRMA-810
title: "Epic: One app, two tiny launchers (KromoraKit scene plus Xcode target)"
type: feature
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Both @main launchers are tiny and share KromoraAppDelegate and KromoraScene.
      result: pass
      notes: KRMA-791 and KRMA-792 passed; the launchers delegate to the shared KromoraKit app lifecycle.
    - criterion: Xcode/Kromora.xcodeproj builds a signed-capable, sandboxed Kromora.app linking only KromoraKit.
      result: pass
      notes: KRMA-794, KRMA-795, and KRMA-796 passed; the project, configuration, sandbox, and signing inputs are present.
    - criterion: Bundle metadata, icon, entitlements, and resource bundle are verified on the Xcode-built app.
      result: pass
      notes: KRMA-793, KRMA-797, and KRMA-799 passed; the metadata/assets were wired and the built app verification script was added.
  checks_run:
    - Confirmed declared child issues KRMA-791, KRMA-792, KRMA-793, KRMA-794, KRMA-795, KRMA-796, KRMA-797, and KRMA-799 are done with verification_report.verdict=pass.
    - git merge-base --is-ancestor for each declared child commit against HEAD 59f9039f (all passed).
    - Confirmed Xcode/Kromora.xcodeproj, App/Kromora.entitlements, and scripts/verify-xcode-app.sh are present.
    - Reviewed child reports for shared launchers, Xcode target configuration, resources, and produced-app checks.
  findings: []
  fixes: []
  verification_commits:
    - 0a599347
    - 5aeb69ec
    - b3b46111
    - 3d347ff8
    - b050ded2
    - 752a93b5
    - "90464039"
    - fd3963a0
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-05T14:50:50.161Z
  session: 01MUVDACR2KMNWAE9C
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - epic
  - appstore
created: 2026-10-03T19:25:19.249Z
updated: 2026-10-05T14:50:50.164Z
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
order: a0
board: product
commits:
  - 0a599347
  - 5aeb69ec
  - b3b46111
  - 3d347ff8
  - b050ded2
  - 752a93b5
  - "90464039"
  - fd3963a0
---

## Completion disposition

This aggregate tracking parent is complete: each declared child dependency is done with a passing verification report, and each child implementation commit is present in repository history.

## Objective

Move all app wiring into KromoraKit and add the Xcode project as a thin packaging layer around it.

Source plan: `.context/2026-09-30-app-store-release-plan.md` (Plan Workstreams 1, 2, and the target layout).

## Outcome

- [x] Both `@main` launchers are tiny and share `KromoraAppDelegate` and `KromoraScene`.
- [x] `Xcode/Kromora.xcodeproj` builds a signed-capable, sandboxed `Kromora.app` linking only KromoraKit.
- [x] Bundle metadata, icon, entitlements, and resource bundle are verified on the Xcode-built app.

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

## Agent log

- 2026-10-05T14:50:50.161Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Both @main launchers are tiny and share KromoraAppDelegate and KromoraScene. (pass) — KRMA-791 and KRMA-792 passed; the launchers delegate to the shared KromoraKit app lifecycle.
- [x] Xcode/Kromora.xcodeproj builds a signed-capable, sandboxed Kromora.app linking only KromoraKit. (pass) — KRMA-794, KRMA-795, and KRMA-796 passed; the project, configuration, sandbox, and signing inputs are present.
- [x] Bundle metadata, icon, entitlements, and resource bundle are verified on the Xcode-built app. (pass) — KRMA-793, KRMA-797, and KRMA-799 passed; the metadata/assets were wired and the built app verification script was added.
Checks run:
- Confirmed declared child issues KRMA-791, KRMA-792, KRMA-793, KRMA-794, KRMA-795, KRMA-796, KRMA-797, and KRMA-799 are done with verification_report.verdict=pass.
- git merge-base --is-ancestor for each declared child commit against HEAD 59f9039f (all passed).
- Confirmed Xcode/Kromora.xcodeproj, App/Kromora.entitlements, and scripts/verify-xcode-app.sh are present.
- Reviewed child reports for shared launchers, Xcode target configuration, resources, and produced-app checks.
Findings:
- None
Fixes:
- None
Verification commits:
- 0a599347
- 5aeb69ec
- b3b46111
- 3d347ff8
- b050ded2
- 752a93b5
- 90464039
- fd3963a0
Actor: codex
Resolved model: unknown
Pickup session: 01MUVDACR2KMNWAE9C
Summary: Verified: all eight launcher and Xcode packaging tickets are done with passing reports and their commits are in repository history.
