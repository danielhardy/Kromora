---
id: KRMA-798
title: Add a PrivacyInfo.xcprivacy manifest declaring required-reason API use
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
  - privacy
  - xcode
created: 2026-10-03T19:24:32.332Z
updated: 2026-10-03T19:25:50.518Z
depends_on:
  - KRMA-785
  - KRMA-796
blockers: []
order: zzy
board: product
---

## Objective

Ship a privacy manifest so the app passes App Store Connect's required-reason API checks and states that Kromora collects no data and does no tracking.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 3). Apple requires `PrivacyInfo.xcprivacy` declaring use of "required reason" APIs: UserDefaults (`NSPrivacyAccessedAPICategoryUserDefaults`), file timestamp APIs, disk-space APIs, system boot time, and active keyboard. The sandbox audit's section 3 `docs/APP_STORE_SANDBOX_AUDIT.md` has a required-reason table with file:line evidence and candidate reason codes; use it, and re-verify with `grep -rnE "UserDefaults|modificationDate|creationDate|contentModificationDateKey|creationDateKey|volumeAvailableCapacity|systemUptime" Sources`. Kromora has no analytics, no network after the updater removal, and no accounts.

## Scope

- Create `App/PrivacyInfo.xcprivacy` (plist) with `NSPrivacyTracking = false`, empty `NSPrivacyTrackingDomains`, empty `NSPrivacyCollectedDataTypes`, and an `NSPrivacyAccessedAPITypes` entry for each category the audit found, each with the correct Apple reason code (for example UserDefaults reading/writing only the app's own settings is `CA92.1`; verify each code against Apple's published list rather than guessing, and if uncertain note it in the handoff).
- Add the manifest to the Xcode target's resources.
- Extend the Info.plist/bundle verification script (`scripts/verify-library-package-metadata.sh` or a new `scripts/verify-privacy-manifest.sh` wired into the same places) to check the manifest exists, parses, declares no tracking, and covers every category found by the grep.

## Acceptance criteria

- [ ] `plutil -lint App/PrivacyInfo.xcprivacy` passes and the Xcode-built app contains `Contents/Resources/PrivacyInfo.xcprivacy`.
- [ ] Each required-reason category used in `Sources/` appears with a documented reason code, and no category is declared that the code does not use.
- [ ] The verification script fails if the manifest is missing or tracking is true (check once, then revert).
- [ ] `scripts/ci-tests.sh fast` passes.

## Verification

- Build the Xcode target, list the app's Resources, run the verification script, and re-run the grep to compare categories.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
