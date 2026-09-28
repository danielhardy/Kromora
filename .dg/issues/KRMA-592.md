---
id: KRMA-592
title: Animate the Info sidebar closed when returning to Library
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Switching from Edit to Library with the Info sidebar open animates the sidebar closed rather than removing it abruptly.
      result: pass
      notes: "ContentView.mainContent now has .onChange(of: viewModel.navigation.mode) that, on transition to .grid with inspectorState.isPresented true, sets inspectorState.isPresented = false inside withAnimation(chromeAnimation), so SwiftUI animates the .inspector() column closed instead of it disappearing with the mode switch."
    - criterion: The transition remains smooth with the Library view and window layout.
      result: pass
      notes: "chromeAnimation is the existing Reduce-Motion-aware .easeInOut(duration: 0.3) helper already used for crop-tool and source-browser chrome, and detailContent separately animates navigation.mode with .easeInOut(duration: 0.2); the two run concurrently without conflicting. accessibilityReduceMotion disables the inspector animation (nil Animation) exactly as it does for the other chrome transitions."
    - criterion: Switching to Library with the Info sidebar already closed continues to work normally.
      result: pass
      notes: The onChange handler guards on inspectorState.isPresented and returns immediately when it is already false, so no redundant state write or animation occurs in that case.
  checks_run:
    - swift build (product) — passed
    - scripts/ci-tests.sh fast — 1243/1244 passed; 1 pre-existing failure (AutoEnhancementCoordinatorTests/testFrozenTargetsPreserveLowKeyIntent) unrelated to this issue's ContentView change, reproduced deterministically in isolation and filed as child ticket KRMA-639
    - git show 91c485c — reviewed the single ContentView.swift diff implementing the fix
  findings:
    - "Pre-existing, unrelated test failure discovered while running the required fast lane: AutoEnhancementCoordinatorTests/testFrozenTargetsPreserveLowKeyIntent fails deterministically on main because AutoExposureObjective.targetMedian forces intentWeight to 0 once robustUnderexposureEvidence crosses the structural-evidence gate, regardless of lowKeyLikelihood, so the target collapses to the neutral median (0.48) instead of the baseline median (0.25) the test expects. Not caused by and not overlapping with the KRMA-592 ContentView change. Filed as backlog child ticket KRMA-639 (parent: KRMA-592) rather than patched here, since resolving it requires an Auto-exposure policy judgment call (fix the gating logic vs. update the stale test expectation), which is outside a verifier's localized-fix scope."
    - "Also observed unrelated pre-existing working-tree state: untracked WIP files (Sources/KromoraKit/Models/RetouchModels.swift, GeometryPointMapping.swift and their tests) currently fail to compile against EditDocument, and staged-but-uncommitted changes to AppViewModel.swift/PreviewAdmissionCoordinator.swift/DevelopInspectorTests.swift rework histogram-identity tracking. Neither overlaps KRMA-592's ContentView.swift change. Left untouched per the instruction to preserve pre-existing working-tree changes; temporarily relocated the untracked WIP files outside the tree only to unblock the test-target build, then restored them immediately after the fast lane finished."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T17:50:37.606Z
  session: 01MUIOJ6U8KXVAKZ2J
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - sidebar
  - animation
created: 2026-09-26T02:56:21.124Z
updated: 2026-09-28T14:41:37.763Z
blockers: []
order: vjhi5y01
board: product
---

## Objective

Animate the Info sidebar closing when the user switches from Edit to Library.

## Context

Reproduction: open the Info panel in Edit, then switch to Library. The panel currently disappears without a closing animation. The transition should visibly animate the sidebar closed as the app moves to Library.

## Acceptance criteria

- [ ] Switching from Edit to Library with the Info sidebar open animates the sidebar closed rather than removing it abruptly.
- [ ] The transition remains smooth with the Library view and window layout.
- [ ] Switching to Library with the Info sidebar already closed continues to work normally.


### Comment — codex @ 2026-09-26T17:13:37.769Z

Implemented the Edit-to-Library inspector dismissal: when navigation enters Library, an open Info sidebar closes with the existing Reduce Motion-aware chrome animation. Verification: swift build passed. Commit: 91c485c.

## Agent log

- 2026-09-26T17:50:37.606Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Switching from Edit to Library with the Info sidebar open animates the sidebar closed rather than removing it abruptly. (pass) — ContentView.mainContent now has .onChange(of: viewModel.navigation.mode) that, on transition to .grid with inspectorState.isPresented true, sets inspectorState.isPresented = false inside withAnimation(chromeAnimation), so SwiftUI animates the .inspector() column closed instead of it disappearing with the mode switch.
- [x] The transition remains smooth with the Library view and window layout. (pass) — chromeAnimation is the existing Reduce-Motion-aware .easeInOut(duration: 0.3) helper already used for crop-tool and source-browser chrome, and detailContent separately animates navigation.mode with .easeInOut(duration: 0.2); the two run concurrently without conflicting. accessibilityReduceMotion disables the inspector animation (nil Animation) exactly as it does for the other chrome transitions.
- [x] Switching to Library with the Info sidebar already closed continues to work normally. (pass) — The onChange handler guards on inspectorState.isPresented and returns immediately when it is already false, so no redundant state write or animation occurs in that case.
Checks run:
- swift build (product) — passed
- scripts/ci-tests.sh fast — 1243/1244 passed; 1 pre-existing failure (AutoEnhancementCoordinatorTests/testFrozenTargetsPreserveLowKeyIntent) unrelated to this issue's ContentView change, reproduced deterministically in isolation and filed as child ticket KRMA-639
- git show 91c485c — reviewed the single ContentView.swift diff implementing the fix
Findings:
- Pre-existing, unrelated test failure discovered while running the required fast lane: AutoEnhancementCoordinatorTests/testFrozenTargetsPreserveLowKeyIntent fails deterministically on main because AutoExposureObjective.targetMedian forces intentWeight to 0 once robustUnderexposureEvidence crosses the structural-evidence gate, regardless of lowKeyLikelihood, so the target collapses to the neutral median (0.48) instead of the baseline median (0.25) the test expects. Not caused by and not overlapping with the KRMA-592 ContentView change. Filed as backlog child ticket KRMA-639 (parent: KRMA-592) rather than patched here, since resolving it requires an Auto-exposure policy judgment call (fix the gating logic vs. update the stale test expectation), which is outside a verifier's localized-fix scope.
- Also observed unrelated pre-existing working-tree state: untracked WIP files (Sources/KromoraKit/Models/RetouchModels.swift, GeometryPointMapping.swift and their tests) currently fail to compile against EditDocument, and staged-but-uncommitted changes to AppViewModel.swift/PreviewAdmissionCoordinator.swift/DevelopInspectorTests.swift rework histogram-identity tracking. Neither overlaps KRMA-592's ContentView.swift change. Left untouched per the instruction to preserve pre-existing working-tree changes; temporarily relocated the untracked WIP files outside the tree only to unblock the test-target build, then restored them immediately after the fast lane finished.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUIOJ6U8KXVAKZ2J
Summary: Verified Edit→Library inspector-dismissal animation (91c485c); build and fast test lane pass except one pre-existing unrelated Auto-exposure test failure, filed as child ticket KRMA-639.
