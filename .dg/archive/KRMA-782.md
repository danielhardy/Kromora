---
id: KRMA-782
title: Add the Photos library usage description to the app Info.plist
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Info.plist contains non-empty NSPhotoLibraryUsageDescription naming import and export
      result: pass
    - criterion: plutil -lint passes
      result: pass
    - criterion: verify script passes with key and fails when missing or blank
      result: pass
      notes: Tested by removing and blanking the key; plist restored, tree clean.
    - criterion: build-macos-app.sh succeeds and plutil extract prints string
      result: pass
  checks_run:
    - plutil -lint Sources/Kromora/Info.plist
    - scripts/verify-library-package-metadata.sh (positive, missing, blank)
    - scripts/build-macos-app.sh
    - plutil -extract on built Info.plist
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T15:58:49.854Z
  session: 01MUU0803FZF19B95G
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - privacy
  - packaging
created: 2026-10-03T19:24:04.202Z
updated: 2026-10-04T15:58:49.858Z
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T15:57:10.898Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Make the packaged app declare why it accesses the Photos library, so a sandboxed build can request Photos authorization and App Store review does not reject the binary for a missing purpose string.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 3). `Sources/KromoraKit/Models/PhotosDelivery.swift` calls `PHPhotoLibrary.requestAuthorization(for: .readWrite)` and `performChanges` (it both imports from and delivers exports to Photos). The bundle metadata lives in `Sources/Kromora/Info.plist`, which `scripts/build-macos-app.sh` copies into the app. It currently has no `NSPhotoLibraryUsageDescription`. `scripts/verify-library-package-metadata.sh` already parses `Info.plist` with a small Python block and is run from CI.

## Scope

- Add `NSPhotoLibraryUsageDescription` to `Sources/Kromora/Info.plist` with a short, specific, user-facing sentence that covers both uses: choosing photos to import into a Kromora library, and saving exported images back to Photos.
- Add `NSPhotoLibraryAddUsageDescription` only if `PhotosDelivery.swift` or other code uses add-only authorization (`.addOnly`). If every request is `.readWrite`, do not add it.
- Extend `scripts/verify-library-package-metadata.sh` to fail when `NSPhotoLibraryUsageDescription` is missing or empty.
- Do not add any other permission strings in this ticket.

## Acceptance criteria

- [ ] `Sources/Kromora/Info.plist` contains a non-empty `NSPhotoLibraryUsageDescription` that names both import and export-to-Photos uses and does not claim anything Kromora does not do.
- [ ] `plutil -lint Sources/Kromora/Info.plist` passes.
- [ ] `scripts/verify-library-package-metadata.sh` passes with the key present and fails (verify once by temporarily removing it, then restore) when it is absent or blank.
- [ ] `scripts/build-macos-app.sh` still succeeds and `/usr/bin/plutil -extract NSPhotoLibraryUsageDescription raw .build/Kromora.app/Contents/Info.plist` prints the string.

## Verification

- Run `plutil -lint`, `scripts/verify-library-package-metadata.sh`, then `scripts/build-macos-app.sh` and the plutil extract above.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.


### Comment — codex @ 2026-10-04T15:57:07.994Z

Added the Photos library purpose string for importing photos into a Kromora library and saving exports to Photos. The metadata verifier rejects missing and blank strings. Verified plutil lint, positive and negative verifier cases, the release app build, and the packaged plist extract. Commit: 4d7ae86d.

## Agent log

- 2026-10-04T15:58:49.854Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Info.plist contains non-empty NSPhotoLibraryUsageDescription naming import and export (pass)
- [x] plutil -lint passes (pass)
- [x] verify script passes with key and fails when missing or blank (pass) — Tested by removing and blanking the key; plist restored, tree clean.
- [x] build-macos-app.sh succeeds and plutil extract prints string (pass)
Checks run:
- plutil -lint Sources/Kromora/Info.plist
- scripts/verify-library-package-metadata.sh (positive, missing, blank)
- scripts/build-macos-app.sh
- plutil -extract on built Info.plist
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUU0803FZF19B95G
Summary: Verified: Photos usage description present, verifier fails on missing/blank, app build embeds string.
