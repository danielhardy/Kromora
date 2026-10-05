---
id: KRMA-785
title: "App Sandbox audit 3/3: network, subprocesses, resources, and protected-API inventory"
type: task
status: done
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Sections 3 and 4 exist; sections 1 and 2 unchanged
      result: pass
      notes: Commit diff is 100 insertions, 0 deletions, docs only.
    - criterion: Required-reason API table cites file:line for every use with reason code or needs review
      result: pass
      notes: Re-ran greps; UserDefaults, timestamp, systemUptime uses covered. Extra attributesOfItem uses read only size or inode, so are outside the category. No disk-space or keyboard uses.
    - criterion: Recommendation table lists final entitlement set with justification and entitlements to remove
      result: pass
      notes: Five kept entitlements, network.client removed; matches Kromora.entitlements.
    - criterion: Every blocker/should-fix has linked backlog ID; no source/test/script modified
      result: pass
      notes: Follow-ups link KRMA-786/787/798/813; no code changed.
  checks_run:
    - grep for required-reason APIs, Process, URLSession, dlopen in Sources
    - git diff --check HEAD~1 HEAD
    - entitlements file compared to recommendations
    - Package.swift updater flag verified
  findings: []
  fixes: []
  verification_commits:
    - 5d7e4eb0
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T17:00:19.184Z
  session: 01MUU2GIUC7DTW3H2G
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
updated: 2026-10-04T17:00:19.188Z
depends_on:
  - KRMA-784
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T16:59:30.969Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 5d7e4eb0
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


### Comment — codex @ 2026-10-04T16:59:26.099Z

Appended sections 3–4 to docs/APP_STORE_SANDBOX_AUDIT.md; sections 1–2 are unchanged and no source, test, or script files were modified. Recorded that current in-process network and Process() calls belong to the direct-distribution updater (removed by KRMA-786/787), and documented PhotosPicker/PhotoKit usage, resource-bundle packaging risk for KRMA-813, required-reason API evidence, entitlement recommendations, and usage strings. UserDefaults maps to CA92.1, systemUptime to 35F9.1, file-timestamp reason needs scope review in KRMA-798; no disk-space or active-keyboard API calls found. Recommended keeping five sandbox entitlements and removing network.client after updater deletion. Checks: targeted required-reason grep, git diff --check, dg validate (OK; existing model-name warnings). Commit: 5d7e4eb0.

## Agent log

- 2026-10-04T17:00:19.184Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Sections 3 and 4 exist; sections 1 and 2 unchanged (pass) — Commit diff is 100 insertions, 0 deletions, docs only.
- [x] Required-reason API table cites file:line for every use with reason code or needs review (pass) — Re-ran greps; UserDefaults, timestamp, systemUptime uses covered. Extra attributesOfItem uses read only size or inode, so are outside the category. No disk-space or keyboard uses.
- [x] Recommendation table lists final entitlement set with justification and entitlements to remove (pass) — Five kept entitlements, network.client removed; matches Kromora.entitlements.
- [x] Every blocker/should-fix has linked backlog ID; no source/test/script modified (pass) — Follow-ups link KRMA-786/787/798/813; no code changed.
Checks run:
- grep for required-reason APIs, Process, URLSession, dlopen in Sources
- git diff --check HEAD~1 HEAD
- entitlements file compared to recommendations
- Package.swift updater flag verified
Findings:
- None
Fixes:
- None
Verification commits:
- 5d7e4eb0
Actor: claude
Resolved model: sonnet
Pickup session: 01MUU2GIUC7DTW3H2G
Summary: Verified sections 3-4 of APP_STORE_SANDBOX_AUDIT.md: accurate, complete, docs-only.
