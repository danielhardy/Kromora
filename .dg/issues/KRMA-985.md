---
id: KRMA-985
title: "KRMA-944c: Document launch sequence in APP_ARCHITECTURE.md and remove init-time open from KromoraAppDelegate"
type: task
status: ready
priority: high
human_review_required: false
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
updated: 2026-10-13T22:12:32.804Z
depends_on:
  - KRMA-984
blockers: []
order: zrq
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
