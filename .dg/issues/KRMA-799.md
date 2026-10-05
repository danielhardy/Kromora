---
id: KRMA-799
title: Add scripts/verify-xcode-app.sh and prove the SwiftPM resource bundle is embedded
type: task
status: done
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: scripts/verify-xcode-app.sh <Xcode-built Kromora.app> passes on an ad-hoc-signed Release build
      result: pass
      notes: Rebuilt via xcodebuild -target Kromora Release, ad-hoc; all checks passed.
    - criterion: Test or script assertion proves starter Looks resolve from Xcode-built app
      result: pass
      notes: Foundation Bundle lookup resolves manifest.json and all 13 LUTs from Contents/Resources/Kromora_KromoraKit.bundle.
    - criterion: Handoff lists sandbox denials or states none
      result: pass
      notes: Handoff states no Kromora denials; not independently re-run.
    - criterion: scripts/ci-tests.sh fast passes
      result: pass
      notes: Reported by implementer (1522 tests); new script only, no Swift touched. Not re-run.
  checks_run:
    - zsh -n scripts/verify-xcode-app.sh
    - xcodebuild Release ad-hoc build of Xcode target Kromora
    - scripts/verify-xcode-app.sh on built app (exit 0)
  findings:
    - "Low: default path branch checks for scripts/app-store-build.sh, which does not yet exist, so the argument is always required for now; matches spec."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T23:16:30.895Z
  session: 01MUUFS3V04ELWUDRJ
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - xcode
  - verification
  - packaging
created: 2026-10-03T19:24:34.361Z
updated: 2026-10-04T23:16:30.899Z
depends_on:
  - KRMA-797
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T22:32:21.246Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Add one script that verifies an Xcode-built `Kromora.app` end to end, and fix `KromoraKitResourceBundle` if the SwiftPM resource bundle does not resolve inside the Xcode-built app.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstreams 0 and 6). `Sources/KromoraKit/Support/KromoraKitResourceBundle.swift` looks for `Kromora_KromoraKit.bundle` under `Bundle.main.resourceURL`; `scripts/build-macos-app.sh` copies it there explicitly. Xcode may place a local package's resource bundle elsewhere or merge it. If starter Looks (`Sources/KromoraKit/Resources/StarterLooks`, loaded by `BundledLookLibrary`) or Metal libraries are missing at runtime, the app launches but silently has no bundled Looks. Existing checks: `scripts/verify-app-icon.sh`, `scripts/verify-app-signature.sh`, `scripts/verify-library-package-metadata.sh`. Kromora's native macOS target does not require a privacy manifest solely for required-reason APIs; see the platform-specific inventory in `docs/APP_STORE_SANDBOX_AUDIT.md` and Apple's [privacy-manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files). Do not make the bundle verifier fail because `PrivacyInfo.xcprivacy` is absent unless a separate current platform or SDK requirement applies.

## Scope

- Create `scripts/verify-xcode-app.sh [path/to/Kromora.app]` (zsh, `set -euo pipefail`, same style as the sibling scripts) that checks: bundle exists; `Contents/Resources/Kromora_KromoraKit.bundle` (or wherever the app resolves it) exists and contains `StarterLooks/manifest.json`; Info.plist has the identifier, category, encryption flag, usage string, and `LSMinimumSystemVersion = 26.0`; the binary has no GitHub-updater remnants (`strings` finds no `api.github.com`); the signature and entitlements pass `verify-app-signature.sh`; icon passes `verify-app-icon.sh`. Do not require `PrivacyInfo.xcprivacy` for this native macOS-only target solely because it uses required-reason APIs. Default path is the DerivedData path used by `scripts/app-store-build.sh` if it exists, otherwise require the argument.
- Build the Xcode target Release (ad-hoc signed) and run the script. If the resource bundle is missing or at a different location, make `KromoraKitResourceBundle` resolve both locations (SwiftPM build and Xcode build), with a test, or adjust the Xcode target so the bundle lands where the code expects. State which and why in the handoff.
- Launch the built app once from the terminal (`open`, then quit it) and confirm it starts (the sandbox may block `swift run`-only paths; record any console sandbox denials from `log show --last 2m --predicate 'sender == "Sandbox"'` in the handoff comment).

## Acceptance criteria

- [ ] `scripts/verify-xcode-app.sh <Xcode-built Kromora.app>` passes on an ad-hoc-signed Release build.
- [ ] A test or script assertion proves the bundled starter Looks resolve from the Xcode-built app (not just the SwiftPM bundle).
- [ ] The handoff comment lists any sandbox denials seen at launch (or states none) and files a backlog issue (label `appstore`) for each real denial.
- [ ] `scripts/ci-tests.sh fast` passes.

## Verification

- Build Release, run the script, and read the sandbox log excerpt.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.


### Comment — codex @ 2026-10-04T22:32:20.765Z

Added scripts/verify-xcode-app.sh. It checks required Xcode Info.plist metadata, rejects api.github.com remnants, runs the signature/entitlement and icon verifiers, and uses Foundation Bundle lookup against the built app to resolve StarterLooks/manifest.json plus all 13 .cube files. The ad-hoc signed arm64 Release build and verifier passed; the package bundle is at Contents/Resources/Kromora_KromoraKit.bundle, which matches the existing resolver, so no runtime change was needed. Opened the app and quit it cleanly. The system-wide Sandbox query showed unrelated background process/tool denials; no Kromora denials occurred (Kromora-filtered entries were ContextStoreAgent allow reads), so no appstore backlog issue was filed. scripts/ci-tests.sh fast passed all 1,522 tests; zsh -n and git diff --check passed. Commit fd3963a0.

## Agent log

- 2026-10-04T23:16:30.895Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] scripts/verify-xcode-app.sh <Xcode-built Kromora.app> passes on an ad-hoc-signed Release build (pass) — Rebuilt via xcodebuild -target Kromora Release, ad-hoc; all checks passed.
- [x] Test or script assertion proves starter Looks resolve from Xcode-built app (pass) — Foundation Bundle lookup resolves manifest.json and all 13 LUTs from Contents/Resources/Kromora_KromoraKit.bundle.
- [x] Handoff lists sandbox denials or states none (pass) — Handoff states no Kromora denials; not independently re-run.
- [x] scripts/ci-tests.sh fast passes (pass) — Reported by implementer (1522 tests); new script only, no Swift touched. Not re-run.
Checks run:
- zsh -n scripts/verify-xcode-app.sh
- xcodebuild Release ad-hoc build of Xcode target Kromora
- scripts/verify-xcode-app.sh on built app (exit 0)
Findings:
- Low: default path branch checks for scripts/app-store-build.sh, which does not yet exist, so the argument is always required for now; matches spec.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUUFS3V04ELWUDRJ
Summary: Independent verification passed: Xcode Release ad-hoc build passes verify-xcode-app.sh.
