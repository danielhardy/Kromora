---
id: KRMA-785
title: "App Sandbox audit 3/3: network, subprocesses, resources, and protected-API inventory"
type: task
status: ready
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - audit
  - sandbox
  - privacy
created: 2026-10-03T19:24:13.029Z
updated: 2026-10-03T19:25:43.154Z
depends_on:
  - KRMA-784
blockers: []
order: w
board: product
---

## Objective

Finish the audit with the non-file sandbox concerns, a protected-API and required-reason-API inventory, and a concrete recommendation table for entitlements and usage strings that later tickets act on.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstreams 0, 3, and 4). Known facts: `Process()` is used only in `Sources/KromoraKit/Presentation/UpdateInstaller.swift` (to be deleted by the direct-distribution removal tickets); network use is the GitHub updater only (`UpdateCoordinator.swift`, `ReleaseFeed.swift`); SwiftPM puts KromoraKit resources in `Kromora_KromoraKit.bundle` which `Sources/KromoraKit/Support/KromoraKitResourceBundle.swift` resolves from `Bundle.main.resourceURL`. Frameworks linked: Accelerate, Photos, PhotosUI, Vision (see `Package.swift`). Apple requires a privacy manifest (`PrivacyInfo.xcprivacy`) declaring "required reason" API use. The categories are UserDefaults, file timestamps, disk space, system boot time, and active keyboard. `grep` for `UserDefaults`, `modificationDate`, `creationDate`, `volumeAvailableCapacity`, `systemUptime` shows the current uses.

## Scope

Append section "3. Runtime, resources, and privacy inventory" to `docs/APP_STORE_SANDBOX_AUDIT.md` and end with a section "4. Recommendations" containing:

- Network: every outbound call site today and whether any will remain after the updater is removed.
- Subprocess, `dlopen`, dynamic code loading, embedded frameworks/binaries, helper processes: confirm none remain after updater removal (list what grep finds).
- Resource bundle resolution: explain how `KromoraKitResourceBundle` finds `Kromora_KromoraKit.bundle` in the SwiftPM-built `.app` and state the risk that Xcode's packaging of a local package's resource bundle lands somewhere else (to be verified by the Xcode ticket).
- Protected resources: a table of every protected API used (Photos, files, anything else) and its required Info.plist usage string, with an explicit "do not add" list for strings Kromora does not need.
- Required-reason APIs: a table of each category found, file:line, and the Apple reason code that applies, for the privacy-manifest ticket to consume.
- Recommendations table: the minimal final entitlement set with a one-line justification per entitlement, and which current entitlements to remove.

File backlog issues for any blocker or should-fix (label `appstore`); do not change product code.

## Acceptance criteria

- [ ] Sections 3 and 4 exist; sections 1 and 2 are unchanged.
- [ ] The required-reason API table cites file:line for every use and names the Apple reason code or states "needs review".
- [ ] The recommendation table lists a final entitlement set with a justification for each and names the entitlements to remove.
- [ ] Every blocker or should-fix has a linked backlog issue ID. No source, test, or script files are modified.

## Verification

- Reviewer re-runs the greps named above and confirms the tables are complete.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
