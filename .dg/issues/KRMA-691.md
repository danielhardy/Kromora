---
id: KRMA-691
title: Prevent dramatic library reflow when returning from Edit mode
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce the layout shift by entering Edit mode and returning to Library without changing the window size or library contents; record which layout elements move or resize.
      result: pass
      notes: "Implementer reproduced and documented: the mosaic grid resizes because the editor inspector was still presented for one frame when the workspace switched back to grid, then animated closed, causing the grid to lay out beside the inspector before its final width."
    - criterion: Identify the state or measurement change that triggers the unnecessary reflow, such as available space, toolbar/inspector visibility, scroll geometry, or a stale layout measurement.
      result: pass
      notes: "Root cause: ContentView's onChange(of: viewModel.navigation.mode) closed the inspector with withAnimation only after the mode already flipped to .grid, so SwiftUI rendered the grid at the inspector-constrained width first."
    - criterion: Preserve the Library layout across the transition when its actual inputs have not changed, without suppressing legitimate reflow after window or content changes.
      result: pass
      notes: "AppViewModel.navigate(to:) now sets inspectorState.isPresented = false before navigation.move(to: .grid), so the grid never renders at the transient inspector-constrained width. Verified via LibraryChromeLayoutTests.testReturningFromEditRestoresTheSameLibraryViewportWidth (viewport width matches pre-edit width mid-transition and after settling)."
    - criterion: Preserve useful scroll position and selection across the transition where currently expected.
      result: pass
      notes: WorkspaceNavigationTests.testReturningToLibraryClosesInspectorBeforeSwitchingWorkspace and testReturningFromEditRestoresTheSameLibraryViewportWidth both assert selection.activeID is retained across the edit->grid transition.
    - criterion: Add regression coverage for the navigation/layout condition and record verification commands and results.
      result: pass
      notes: "New tests: LibraryChromeLayoutTests.testReturningFromEditRestoresTheSameLibraryViewportWidth, WorkspaceNavigationTests.testReturningToLibraryClosesInspectorBeforeSwitchingWorkspace. Both pass; see checks_run."
  checks_run:
    - swift build
    - swift test --filter 'LibraryChromeLayoutTests|WorkspaceNavigationTests|NavigationStateTests' (14 tests, 0 failures)
    - scripts/ci-tests.sh fast (pass on second run; first run had one unrelated flaky parallel-execution failure in ThumbnailSwitchLifecycleTests that did not reproduce in isolation or on rerun)
    - scripts/ci-tests.sh serial (13 pre-existing KeyMonitorTests failures, confirmed unrelated to KRMA-691 by reproducing identically with ContentView.swift reverted to the committed 18cb3a0 baseline; filed as child KRMA-698)
    - dg validate
  findings:
    - "ContentView.swift:237 — the onChange(of: viewModel.navigation.mode) animated inspector-dismissal handler (added by 91c485c) became dead code once AppViewModel.navigate(to:) started closing the inspector synchronously before the mode change: every navigate(to: .grid) call path now sets inspectorState.isPresented = false before navigation.move(to: .grid), so the handler's guard (mode == .grid && inspectorState.isPresented) is never true. Fixed by removing it in this pass."
    - KeyMonitorTests.swift:547 — 13 pre-existing, deterministic (non-flaky) failures in testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime and testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps in the render-ui-serial lane, confirmed unrelated to KRMA-691 by reproducing identically with ContentView.swift reverted to the committed 18cb3a0 baseline. Filed as child KRMA-698.
  fixes:
    - "Removed the now-unreachable onChange(of: viewModel.navigation.mode) animated inspector-dismissal handler in Sources/KromoraKit/Views/ContentView.swift, since AppViewModel.navigate(to:) already closes the inspector synchronously before the mode change on every call path."
  verification_commits:
    - fa56cf41d00cf2f9e81c6b4159d81c00434314f9
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T22:21:27.384Z
  session: 01MULSTJG5U2C2NABW
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - bug
  - library
created: 2026-09-28T20:55:05.820Z
updated: 2026-09-28T22:21:27.387Z
blockers: []
order: a0
board: product
commits:
  - fa56cf41d00cf2f9e81c6b4159d81c00434314f9
---

## Objective

Keep the Library layout visually stable when returning from Edit mode if the library content and window shape have not changed.

## User report

After being in Edit mode, returning to the Library causes a dramatic reflow even when nothing changed shape. The user expects the existing library layout to remain steady across this navigation.

## Acceptance criteria

- [ ] Reproduce the layout shift by entering Edit mode and returning to Library without changing the window size or library contents; record which layout elements move or resize.
- [ ] Identify the state or measurement change that triggers the unnecessary reflow, such as available space, toolbar/inspector visibility, scroll geometry, or a stale layout measurement.
- [ ] Preserve the Library layout across the transition when its actual inputs have not changed, without suppressing legitimate reflow after window or content changes.
- [ ] Preserve useful scroll position and selection across the transition where currently expected.
- [ ] Add regression coverage for the navigation/layout condition and record verification commands and results.

## Investigation notes

Compare layout measurements and view state immediately before leaving Library and after returning. Check whether Edit mode changes available content bounds or causes cached measurements to be reused or invalidated at the wrong time.


### Comment — codex @ 2026-09-28T22:07:41.681Z

Closing the inspector before switching to Library prevents an intermediate inspector-constrained grid width and the resulting mosaic reflow. Added hosted viewport-width regression coverage and a navigation check for inspector closure and selection retention. Verification: Test Suite 'Selected tests' started at 2026-09-28 16:07:38.339.
Test Suite 'KromoraKitTests.xctest' started at 2026-09-28 16:07:38.340.
Test Suite 'LibraryChromeLayoutTests' started at 2026-09-28 16:07:38.340.
Test Case '-[KromoraKitTests.LibraryChromeLayoutTests testLibraryChromeSecondUpdateFinishes]' started.
Test Case '-[KromoraKitTests.LibraryChromeLayoutTests testLibraryChromeSecondUpdateFinishes]' passed (1.001 seconds).
Test Case '-[KromoraKitTests.LibraryChromeLayoutTests testReturningFromEditRestoresTheSameLibraryViewportWidth]' started.
Test Case '-[KromoraKitTests.LibraryChromeLayoutTests testReturningFromEditRestoresTheSameLibraryViewportWidth]' passed (1.806 seconds).
Test Suite 'LibraryChromeLayoutTests' passed at 2026-09-28 16:07:41.147.
	 Executed 2 tests, with 0 failures (0 unexpected) in 2.807 (2.807) seconds
Test Suite 'WorkspaceNavigationTests' started at 2026-09-28 16:07:41.147.
Test Case '-[KromoraKitTests.WorkspaceNavigationTests testReturningToLibraryClosesInspectorBeforeSwitchingWorkspace]' started.
Test Case '-[KromoraKitTests.WorkspaceNavigationTests testReturningToLibraryClosesInspectorBeforeSwitchingWorkspace]' passed (0.257 seconds).
Test Suite 'WorkspaceNavigationTests' passed at 2026-09-28 16:07:41.404.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.257 (0.257) seconds
Test Suite 'KromoraKitTests.xctest' passed at 2026-09-28 16:07:41.404.
	 Executed 3 tests, with 0 failures (0 unexpected) in 3.064 (3.065) seconds
Test Suite 'Selected tests' passed at 2026-09-28 16:07:41.404.
	 Executed 3 tests, with 0 failures (0 unexpected) in 3.064 (3.065) seconds passed (3 tests). Commit: 18cb3a0.

## Agent log

- 2026-09-28T22:21:27.384Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce the layout shift by entering Edit mode and returning to Library without changing the window size or library contents; record which layout elements move or resize. (pass) — Implementer reproduced and documented: the mosaic grid resizes because the editor inspector was still presented for one frame when the workspace switched back to grid, then animated closed, causing the grid to lay out beside the inspector before its final width.
- [x] Identify the state or measurement change that triggers the unnecessary reflow, such as available space, toolbar/inspector visibility, scroll geometry, or a stale layout measurement. (pass) — Root cause: ContentView's onChange(of: viewModel.navigation.mode) closed the inspector with withAnimation only after the mode already flipped to .grid, so SwiftUI rendered the grid at the inspector-constrained width first.
- [x] Preserve the Library layout across the transition when its actual inputs have not changed, without suppressing legitimate reflow after window or content changes. (pass) — AppViewModel.navigate(to:) now sets inspectorState.isPresented = false before navigation.move(to: .grid), so the grid never renders at the transient inspector-constrained width. Verified via LibraryChromeLayoutTests.testReturningFromEditRestoresTheSameLibraryViewportWidth (viewport width matches pre-edit width mid-transition and after settling).
- [x] Preserve useful scroll position and selection across the transition where currently expected. (pass) — WorkspaceNavigationTests.testReturningToLibraryClosesInspectorBeforeSwitchingWorkspace and testReturningFromEditRestoresTheSameLibraryViewportWidth both assert selection.activeID is retained across the edit->grid transition.
- [x] Add regression coverage for the navigation/layout condition and record verification commands and results. (pass) — New tests: LibraryChromeLayoutTests.testReturningFromEditRestoresTheSameLibraryViewportWidth, WorkspaceNavigationTests.testReturningToLibraryClosesInspectorBeforeSwitchingWorkspace. Both pass; see checks_run.
Checks run:
- swift build
- swift test --filter 'LibraryChromeLayoutTests|WorkspaceNavigationTests|NavigationStateTests' (14 tests, 0 failures)
- scripts/ci-tests.sh fast (pass on second run; first run had one unrelated flaky parallel-execution failure in ThumbnailSwitchLifecycleTests that did not reproduce in isolation or on rerun)
- scripts/ci-tests.sh serial (13 pre-existing KeyMonitorTests failures, confirmed unrelated to KRMA-691 by reproducing identically with ContentView.swift reverted to the committed 18cb3a0 baseline; filed as child KRMA-698)
- dg validate
Findings:
- ContentView.swift:237 — the onChange(of: viewModel.navigation.mode) animated inspector-dismissal handler (added by 91c485c) became dead code once AppViewModel.navigate(to:) started closing the inspector synchronously before the mode change: every navigate(to: .grid) call path now sets inspectorState.isPresented = false before navigation.move(to: .grid), so the handler's guard (mode == .grid && inspectorState.isPresented) is never true. Fixed by removing it in this pass.
- KeyMonitorTests.swift:547 — 13 pre-existing, deterministic (non-flaky) failures in testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime and testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps in the render-ui-serial lane, confirmed unrelated to KRMA-691 by reproducing identically with ContentView.swift reverted to the committed 18cb3a0 baseline. Filed as child KRMA-698.
Fixes:
- Removed the now-unreachable onChange(of: viewModel.navigation.mode) animated inspector-dismissal handler in Sources/KromoraKit/Views/ContentView.swift, since AppViewModel.navigate(to:) already closes the inspector synchronously before the mode change on every call path.
Verification commits:
- fa56cf41d00cf2f9e81c6b4159d81c00434314f9
Actor: claude
Resolved model: sonnet
Pickup session: 01MULSTJG5U2C2NABW
Summary: Verified: inspector closes synchronously before the grid re-renders, eliminating the reflow. Removed the now-dead animated-dismissal handler it superseded and filed KRMA-698 for pre-existing unrelated KeyMonitorTests failures.
