---
id: KRMA-694
title: Raise deployment floor to macOS 26 (manifest, bundle, scripts, docs)
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Package.swift declares Tahoe-only (.macOS(.v26) or toolchain-equivalent); swift build succeeds with zero warnings
      result: pass
      notes: "Package.swift:1 swift-tools-version bumped to 6.2 (was 6.0, since .v26 literal required it); Package.swift:125 platforms: [.macOS(.v26)]. swift build succeeds, no warnings."
    - criterion: Sources/Kromora/Info.plist sets LSMinimumSystemVersion to 26.0; packaged app Info.plist verified after scripts/build-macos-app.sh
      result: pass
      notes: Verified source plist and re-ran scripts/build-macos-app.sh; packaged .build/Kromora.app/Contents/Info.plist LSMinimumSystemVersion=26.0 via PlistBuddy.
    - criterion: scripts/build-macos-app.sh passes --minimum-deployment-target 26.0 to actool; distributable bundle builds
      result: pass
      notes: Confirmed flag at scripts/build-macos-app.sh:74 and swiftpm --triple ...macosx26.0. Full production build succeeded and app bundle verified (codesign).
    - criterion: CLAUDE.md, docs/PACKAGING.md, docs/ENGINEERING_GUIDE.md, docs/REPOSITORY_IMPROVEMENT_PLAN.md describe Tahoe-only (SDK == floor); no stale guard language; AUTO_PERFORMANCE.md macOS 14 note updated or pointed
      result: pass
      notes: "All four docs plus README.md and docs/AUTO_PERFORMANCE.md updated consistently to macOS 26 (Tahoe) floor language; AUTO_PERFORMANCE.md:63-64 updated in place to note the #available(macOS 15,*) guard is now always satisfied rather than moved to a child ticket, which is within the acceptance criterion's stated flexibility."
    - criterion: grep -rn "14\.0" Package.swift Sources/Kromora/Info.plist scripts/build-macos-app.sh shows no product floor remnants
      result: pass
      notes: Ran exact grep from the issue; zero matches.
    - criterion: scripts/ci-tests.sh fast passes; PackageSettingsTests still passes
      result: pass
      notes: First run hit one intermittent ThumbnailSwitchLifecycleTests/testFilmstripAndGridPublishCropAwareSettledThumbnails failure (parallel-execution flake, pre-existing and previously addressed in fc3bb17/ba24b36, unrelated to this diff); isolated rerun passed, and a full ci-tests.sh fast rerun passed with exit 0. PackageSettingsTests (4/4, including Swift 6 mode and no-escape-hatch checks) passed.
  checks_run:
    - swift build (clean, zero warnings)
    - swift test --filter PackageSettingsTests (4/4 pass)
    - scripts/ci-tests.sh fast (rerun, exit 0)
    - swift test --filter ThumbnailSwitchLifecycleTests/testFilmstripAndGridPublishCropAwareSettledThumbnails (isolated rerun to confirm flake)
    - grep -rn "14\.0" Package.swift Sources/Kromora/Info.plist scripts/build-macos-app.sh (no matches)
    - scripts/build-macos-app.sh (production build + PlistBuddy check of packaged Info.plist LSMinimumSystemVersion)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T22:37:48.311Z
  session: 01MULTKX1NMMY47SLO
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - app-shell
  - tahoe
  - build
  - docs
created: 2026-09-28T22:18:52.491Z
updated: 2026-09-28T22:37:48.313Z
blockers: []
order: a0
board: product
---

## Objective

Raise the product floor from macOS 14 to macOS 26 (Tahoe) so Tahoe-only SwiftUI/AppKit APIs can be used unconditionally. Manifest, bundle metadata, packaging script, and user-facing docs must agree; no 14.0 floor may remain.

## Context

Today the floor is declared in three places and documented in four more, while the compiler enforces guards because of it:

- `Package.swift:125` — `platforms: [.macOS(.v14)]`
- `Sources/Kromora/Info.plist:40-41` — `LSMinimumSystemVersion 14.0`
- `scripts/build-macos-app.sh:74` — `actool --minimum-deployment-target 14.0`
- Docs: `CLAUDE.md` ("SDK and deployment target are different things", "Requires Xcode 26 or newer to build" section), `docs/PACKAGING.md:92-93`, `docs/ENGINEERING_GUIDE.md:175`, `docs/REPOSITORY_IMPROVEMENT_PLAN.md:373`

`swift-tools-version: 6.0` predates the `.v26` platform literal; if the toolchain rejects `.macOS(.v26)`, bump the tools version to the Xcode 26 toolchain's version (6.2) as part of this ticket rather than working around it.

Parent: KRMA-693.

## Acceptance criteria

- [ ] `Package.swift` declares Tahoe-only (`platforms: [.macOS(.v26)]` or toolchain-equivalent); `swift build` succeeds on Xcode 26 with zero warnings.
- [ ] `Sources/Kromora/Info.plist` sets `LSMinimumSystemVersion` to `26.0`; packaged app `Info.plist` verified after `scripts/build-macos-app.sh`.
- [ ] `scripts/build-macos-app.sh` passes `--minimum-deployment-target 26.0` to `actool`; distributable bundle builds.
- [ ] `CLAUDE.md`, `docs/PACKAGING.md`, `docs/ENGINEERING_GUIDE.md`, `docs/REPOSITORY_IMPROVEMENT_PLAN.md` describe Tahoe-only (SDK == floor); no "deploys to 14, guard 26" language remains in product docs. `docs/AUTO_PERFORMANCE.md:63-64` macOS 14 nil-path note updated or moved to the guard-cleanup child if preferred, with a pointer.
- [ ] `grep -rn "14\.0" Package.swift Sources/Kromora/Info.plist scripts/build-macos-app.sh` shows no product floor remnants (test fixtures and historical comments excluded with justification).
- [ ] `scripts/ci-tests.sh fast` passes; `PackageSettingsTests` (Swift 6 mode, no escape hatches) still passes.

## Implementation notes

Do not touch availability guards or toolbar code here — those are the dedicated children. Keep this diff to floor + docs so it reverts cleanly. If `.v26` literal is unavailable under tools 6.0, prefer the tools bump over a stringly-typed workaround; record the toolchain version in the log.


### Comment — codex @ 2026-09-28T22:29:06.637Z

Implemented and committed as 7ca9f25. Raised SwiftPM, app bundle, asset catalog, and Metal library deployment to macOS 26; updated Tahoe requirements across docs and README. Verification: swift build clean; scripts/build-macos-app.sh succeeded and packaged LSMinimumSystemVersion=26.0; PackageSettingsTests passed; scripts/ci-tests.sh fast passed all 1,333 tests on rerun. The first fast run had one intermittent thumbnail assertion failure; isolated rerun and full rerun passed. No 14.0 floor remains in Package.swift, Info.plist, or build-macos-app.sh.

## Agent log

- 2026-09-28T22:37:48.311Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Package.swift declares Tahoe-only (.macOS(.v26) or toolchain-equivalent); swift build succeeds with zero warnings (pass) — Package.swift:1 swift-tools-version bumped to 6.2 (was 6.0, since .v26 literal required it); Package.swift:125 platforms: [.macOS(.v26)]. swift build succeeds, no warnings.
- [x] Sources/Kromora/Info.plist sets LSMinimumSystemVersion to 26.0; packaged app Info.plist verified after scripts/build-macos-app.sh (pass) — Verified source plist and re-ran scripts/build-macos-app.sh; packaged .build/Kromora.app/Contents/Info.plist LSMinimumSystemVersion=26.0 via PlistBuddy.
- [x] scripts/build-macos-app.sh passes --minimum-deployment-target 26.0 to actool; distributable bundle builds (pass) — Confirmed flag at scripts/build-macos-app.sh:74 and swiftpm --triple ...macosx26.0. Full production build succeeded and app bundle verified (codesign).
- [x] CLAUDE.md, docs/PACKAGING.md, docs/ENGINEERING_GUIDE.md, docs/REPOSITORY_IMPROVEMENT_PLAN.md describe Tahoe-only (SDK == floor); no stale guard language; AUTO_PERFORMANCE.md macOS 14 note updated or pointed (pass) — All four docs plus README.md and docs/AUTO_PERFORMANCE.md updated consistently to macOS 26 (Tahoe) floor language; AUTO_PERFORMANCE.md:63-64 updated in place to note the #available(macOS 15,*) guard is now always satisfied rather than moved to a child ticket, which is within the acceptance criterion's stated flexibility.
- [x] grep -rn "14\.0" Package.swift Sources/Kromora/Info.plist scripts/build-macos-app.sh shows no product floor remnants (pass) — Ran exact grep from the issue; zero matches.
- [x] scripts/ci-tests.sh fast passes; PackageSettingsTests still passes (pass) — First run hit one intermittent ThumbnailSwitchLifecycleTests/testFilmstripAndGridPublishCropAwareSettledThumbnails failure (parallel-execution flake, pre-existing and previously addressed in fc3bb17/ba24b36, unrelated to this diff); isolated rerun passed, and a full ci-tests.sh fast rerun passed with exit 0. PackageSettingsTests (4/4, including Swift 6 mode and no-escape-hatch checks) passed.
Checks run:
- swift build (clean, zero warnings)
- swift test --filter PackageSettingsTests (4/4 pass)
- scripts/ci-tests.sh fast (rerun, exit 0)
- swift test --filter ThumbnailSwitchLifecycleTests/testFilmstripAndGridPublishCropAwareSettledThumbnails (isolated rerun to confirm flake)
- grep -rn "14\.0" Package.swift Sources/Kromora/Info.plist scripts/build-macos-app.sh (no matches)
- scripts/build-macos-app.sh (production build + PlistBuddy check of packaged Info.plist LSMinimumSystemVersion)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULTKX1NMMY47SLO
Summary: Verified macOS 26 floor raise: Package.swift/.v26+tools 6.2, Info.plist LSMinimumSystemVersion=26.0 (confirmed in packaged bundle), build-macos-app.sh/build-metal-libraries.sh minimum-deployment-target 26.0, docs consistent, no 14.0 product-floor remnants. swift build clean, PackageSettingsTests pass, ci-tests.sh fast passes (one intermittent pre-existing thumbnail-lifecycle flake confirmed by isolated rerun, unrelated to this change).
