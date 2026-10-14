---
id: KRMA-985
title: "KRMA-944c: Document launch sequence in APP_ARCHITECTURE.md and remove init-time open from KromoraAppDelegate"
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: AppViewModel construction occurs only inside AppLaunch, and the delegate performs no package I/O.
      result: pass
      notes: "Required grep output: Sources/KromoraKit/Presentation/AppLaunch.swift:27:            AppViewModel(. Reviewed KromoraAppDelegate, KromoraScene, and AppLaunch.init; package opening is initiated by AppLaunch.open and PortablePackageOpener runs off the main actor."
    - criterion: APP_ARCHITECTURE.md documents the ordered launch sequence, error and shutdown-mid-open behavior, and names the launch types.
      result: pass
      notes: The section names AppLaunch, PortablePackageOpener, PackageOpening, LibraryOpenState, and ApplicationShellCoordinator.
    - criterion: The applicationShouldTerminate nil-model branch is documented and tested.
      result: pass
      notes: The docs explain that quit can precede the first frame task; AppLaunchTests.testDelegateTerminatesBeforeFirstFrameCreatesModel directly verifies .terminateNow.
    - criterion: No stale init-time package-open claims remain in APP_ARCHITECTURE.md, STORAGE_POLICY.md, or ENGINEERING_GUIDE.md.
      result: pass
      notes: Search found no such claim. Also corrected APP_STORE_SANDBOX_AUDIT.md to reflect the chosen-library bookmark and default Pictures fallback.
    - criterion: KRMA-944 acceptance criteria are re-checked item by item in a comment on the parent issue.
      result: pass
      notes: Added a verification comment covering deferred init, Opening library state, single error, shutdown lease release, fast tests, docs, and the KRMA-945 scope boundary.
    - criterion: swift build is warning-free and scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: swift build completed without diagnostics; the final fast lane passed all 1,884 tests.
  checks_run:
    - swift build (exit 0; no warnings or diagnostics)
    - scripts/ci-tests.sh fast (exit 0; 1,884 tests passed)
    - swift test --filter AppLaunchTests/testDelegateTerminatesBeforeFirstFrameCreatesModel (exit 0; 1 test passed)
    - git diff --check (exit 0)
    - "grep -rn 'AppViewModel(' Sources/KromoraKit/Presentation Sources/Kromora (only match: Sources/KromoraKit/Presentation/AppLaunch.swift:27)"
  findings:
    - The launch documentation did not explicitly name the LibraryOpenState type or PortablePackageOpener.
    - APP_STORE_SANDBOX_AUDIT.md still described production startup as having no saved library bookmark, despite ActiveLibrarySelection storing one for a chosen package.
  fixes:
    - Clarified the launch sequence with the explicit opener and state names, and added a direct test for the pre-first-frame delegate termination branch.
    - Corrected the sandbox audit to distinguish chosen-library bookmark access from the default Pictures entitlement fallback.
  verification_commits:
    - 73d5a92194acd846718490377498d6104633f9a1
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T01:23:09.206Z
  session: 01MV7F52E4YA2ZQGOZ
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - startup
  - package
  - needs-decomposition
created: 2026-10-13T20:38:46.211Z
updated: 2026-10-14T01:23:09.209Z
depends_on:
  - KRMA-984
blockers: []
order: zh
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T01:10:05.836Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 73d5a92194acd846718490377498d6104633f9a1
---

## Objective

Document the final launch sequence and finish removing synchronous package work from the app delegate, now that the library opens asynchronously (KRMA-984). Closes out parent KRMA-944.

## Context

Parent: KRMA-944 (read it and its decomposition comment). Review finding S4: `.context/2026-10-13-release-readiness-review.md`. Also read KRMA-557 (index load already off-main), `docs/APP_ARCHITECTURE.md`, `docs/STORAGE_POLICY.md`.

Depends on KRMA-984. Verify first, do not assume: the premise in KRMA-944 (that `KromoraAppDelegate.init` calls `AppViewModel(includeBundledLooks: true)`) is **already stale in the working tree**. KRMA-986's `AppLaunch` work (uncommitted when this ticket was written) made the delegate create `AppLaunch()` only; `AppViewModel` is built later by `AppLaunch.open()`. Re-read `Presentation/KromoraAppDelegate.swift` and `Presentation/AppLaunch.swift` as committed at that point and keep the checklist below honest about what is already done.

Remaining delegate concerns after KRMA-984:
- `applicationShouldTerminate` has `guard let viewModel else { return .terminateNow }`; confirm the final lifecycle makes that branch correct (the model exists from first frame, and a mid-open quit is handled by 984's shutdown). Remove the nil branch if it can no longer occur, or document why it can.
- `init` still calls `NSApplication.shared.setActivationPolicy(.regular)` and `NSApp.activate(ignoringOtherApps:)`; that is KRMA-945's scope, so leave it unless 945 has landed, and note the dependency instead of duplicating it.
- No package, lease or recovery call may run from the delegate, `KromoraScene` or `AppLaunch.init`.

Docs: `docs/APP_ARCHITECTURE.md` has a launch/lifecycle section near L356 (shutdown ordering); add the startup half next to it.

## Acceptance criteria

- [ ] `grep -rn "AppViewModel(" Sources/KromoraKit/Presentation Sources/Kromora` shows construction only inside `AppLaunch` (default `makeViewModel`), and nothing in the delegate performs package I/O (state this check in the review comment with the grep output).
- [ ] `docs/APP_ARCHITECTURE.md` documents the launch sequence in order: process start, delegate init (no I/O), first window with the library shell, lease-recovery prompt (when needed), async package open, bind, collection/index load, ready; plus error and shutdown-mid-open behavior, with file/type names (`AppLaunch`, the opener, the open state, `ApplicationShellCoordinator`).
- [ ] `applicationShouldTerminate`'s nil-model branch is removed or its remaining case is documented and tested (`TerminationGuardTests` or a delegate test).
- [ ] No stale statements remain in `docs/APP_ARCHITECTURE.md`, `docs/STORAGE_POLICY.md` or `docs/ENGINEERING_GUIDE.md` that say the model opens the package in `init`.
- [ ] KRMA-944's acceptance criteria are re-checked against the shipped behavior item by item in a comment on KRMA-944 (init does not open; "Opening library…" state; single error; shutdown mid-open; fast-lane tests; docs).
- [ ] `swift build` warning-free; `scripts/ci-tests.sh fast` exits 0.

## Verification

```
swift build
scripts/ci-tests.sh fast
```

### Comment — claude @ 2026-10-14T01:10:02.546Z

grep AppViewModel( in Presentation/Kromora: Sources/KromoraKit/Presentation/AppLaunch.swift:27:            AppViewModel( -- construction only in AppLaunch default makeViewModel; delegate does no package I/O. Nil-model branch in applicationShouldTerminate kept (quit before first frame's .task) and documented; added AppLaunchTests.testNoModelExistsUntilOpenIsRequested. Fixed stale init-open claim in APP_STORE_SANDBOX_AUDIT.md (STORAGE_POLICY/ENGINEERING_GUIDE had none). swift build clean; ci-tests.sh fast passed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-14T01:23:09.206Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] AppViewModel construction occurs only inside AppLaunch, and the delegate performs no package I/O. (pass) — Required grep output: Sources/KromoraKit/Presentation/AppLaunch.swift:27:            AppViewModel(. Reviewed KromoraAppDelegate, KromoraScene, and AppLaunch.init; package opening is initiated by AppLaunch.open and PortablePackageOpener runs off the main actor.
- [x] APP_ARCHITECTURE.md documents the ordered launch sequence, error and shutdown-mid-open behavior, and names the launch types. (pass) — The section names AppLaunch, PortablePackageOpener, PackageOpening, LibraryOpenState, and ApplicationShellCoordinator.
- [x] The applicationShouldTerminate nil-model branch is documented and tested. (pass) — The docs explain that quit can precede the first frame task; AppLaunchTests.testDelegateTerminatesBeforeFirstFrameCreatesModel directly verifies .terminateNow.
- [x] No stale init-time package-open claims remain in APP_ARCHITECTURE.md, STORAGE_POLICY.md, or ENGINEERING_GUIDE.md. (pass) — Search found no such claim. Also corrected APP_STORE_SANDBOX_AUDIT.md to reflect the chosen-library bookmark and default Pictures fallback.
- [x] KRMA-944 acceptance criteria are re-checked item by item in a comment on the parent issue. (pass) — Added a verification comment covering deferred init, Opening library state, single error, shutdown lease release, fast tests, docs, and the KRMA-945 scope boundary.
- [x] swift build is warning-free and scripts/ci-tests.sh fast exits 0. (pass) — swift build completed without diagnostics; the final fast lane passed all 1,884 tests.
Checks run:
- swift build (exit 0; no warnings or diagnostics)
- scripts/ci-tests.sh fast (exit 0; 1,884 tests passed)
- swift test --filter AppLaunchTests/testDelegateTerminatesBeforeFirstFrameCreatesModel (exit 0; 1 test passed)
- git diff --check (exit 0)
- grep -rn 'AppViewModel(' Sources/KromoraKit/Presentation Sources/Kromora (only match: Sources/KromoraKit/Presentation/AppLaunch.swift:27)
Findings:
- The launch documentation did not explicitly name the LibraryOpenState type or PortablePackageOpener.
- APP_STORE_SANDBOX_AUDIT.md still described production startup as having no saved library bookmark, despite ActiveLibrarySelection storing one for a chosen package.
Fixes:
- Clarified the launch sequence with the explicit opener and state names, and added a direct test for the pre-first-frame delegate termination branch.
- Corrected the sandbox audit to distinguish chosen-library bookmark access from the default Pictures entitlement fallback.
Verification commits:
- 73d5a92194acd846718490377498d6104633f9a1
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7F52E4YA2ZQGOZ
Summary: Independent verification passed; corrected launch documentation, added a direct early-quit test, and verified build and fast lane.
