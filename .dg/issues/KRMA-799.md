---
id: KRMA-799
title: Add scripts/verify-xcode-app.sh and prove the SwiftPM resource bundle is embedded
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
  - xcode
  - verification
  - packaging
created: 2026-10-03T19:24:34.361Z
updated: 2026-10-03T19:25:51.068Z
depends_on:
  - KRMA-797
  - KRMA-798
blockers: []
order: zzz
board: product
---

## Objective

Add one script that verifies an Xcode-built `Kromora.app` end to end, and fix `KromoraKitResourceBundle` if the SwiftPM resource bundle does not resolve inside the Xcode-built app.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstreams 0 and 6). `Sources/KromoraKit/Support/KromoraKitResourceBundle.swift` looks for `Kromora_KromoraKit.bundle` under `Bundle.main.resourceURL`; `scripts/build-macos-app.sh` copies it there explicitly. Xcode may place a local package's resource bundle elsewhere or merge it. If starter Looks (`Sources/KromoraKit/Resources/StarterLooks`, loaded by `BundledLookLibrary`) or Metal libraries are missing at runtime, the app launches but silently has no bundled Looks. Existing checks: `scripts/verify-app-icon.sh`, `scripts/verify-app-signature.sh`, `scripts/verify-library-package-metadata.sh`.

## Scope

- Create `scripts/verify-xcode-app.sh [path/to/Kromora.app]` (zsh, `set -euo pipefail`, same style as the sibling scripts) that checks: bundle exists; `Contents/Resources/Kromora_KromoraKit.bundle` (or wherever the app resolves it) exists and contains `StarterLooks/manifest.json`; Info.plist has the identifier, category, encryption flag, usage string, and `LSMinimumSystemVersion = 26.0`; the privacy manifest is present; the binary has no GitHub-updater remnants (`strings` finds no `api.github.com`); the signature and entitlements pass `verify-app-signature.sh`; icon passes `verify-app-icon.sh`. Default path is the DerivedData path used by `scripts/app-store-build.sh` if it exists, otherwise require the argument.
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
