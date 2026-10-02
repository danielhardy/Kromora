---
id: KRMA-750
title: "Last-known-frame performance: warm Edit first-pixel and 30-cell grid budgets (non-gating umbrella)"
type: task
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
created: 2026-10-01T20:23:06.838Z
updated: 2026-10-01T21:25:56.534Z
blockers: []
order: zy
board: product
---

## Objective

Meet the unchanged last-known-frame wall-clock budgets: warm Edit first pixel p95 <= 50 ms and warm 30-cell grid re-entry p95 <= 100 ms. This is the NON-GATING umbrella for the work: KRMA-734 and KRMA-728 close without it (ADR-LKF-001). The two budgets are separate work items with separate causes and stay separate: **KRMA-748** (warm Edit first pixel) and **KRMA-749** (warm 30-cell grid). KRMA-745 was the first, unsuccessful grid attempt and stays parked; 749 continues it. This ticket owns what they share: the profiling method and the one structural decision below.

## Where things stand (Release, M1 Pro, macOS 27.0, DSC01019.ARW 126 MB, 30 warm samples, KRMA-744 harness)

| Budget | Start | Now | Target |
| --- | ---: | ---: | ---: |
| Main-actor before first suspension p95 | 72 ms | 1.99 ms | <= 2 ms (met) |
| Warm Edit first pixel p95 | 664 ms | ~290 ms | <= 50 ms |
| Warm 30-cell grid p95 | 214 ms | ~231 ms | <= 100 ms |

The whole-file SHA-256 on the main actor is fixed (KRMA-746/747; down to 64 samples in a Time Profiler trace). What remains in both paths is SwiftUI graph updates and layout and the Edit mount (`Attribute.init`, `AG::Graph`, `ContentView.body`, `NSHostingView.updateEnvironment`). Two incremental fixes did not move the grid (observation narrowing in KRMA-745: 193/214 became 217/231). Stop tuning one function at a time.

## Shared approach (decided here, applied in 748 and 749): profile first, then one structural change

1. Take a grid-only and an Edit-handoff-only Time Profiler (or os_signpost) trace. Previous traces spanned setup and every phase, so nothing was attributed.
2. Evaluate keeping the Library grid and the Edit surface mounted and switching visibility (opacity/hit-testing or a persistent container) instead of unmounting and remounting `LibraryGridView`, `PreviewSurfaceView`, and the inspector. This targets both budgets at once. Weigh memory, lifecycle, and the existing grid-mount/unmount instrumentation the harness counts.
3. Lead from the stopped KRMA-749 agent (also recorded in KRMA-749), left uncommitted in the working tree and unreviewed: `AppViewModel` disables animations on the Edit-to-Library handoff (`Transaction.disablesAnimations` around `inspectorState.isPresented = false` and `navigation.move(to: .grid)`), on the theory that the inspector close animation delays the first stable Library display by a full transition. A grid-only profile will confirm or refute it quickly. It also changed the benchmark file by 13 lines; check `git diff` before trusting either.

## Acceptance criteria

- [ ] The structural decision (keep Library and Edit mounted vs. remount, with the memory and lifecycle trade-offs) is made from a grid-only and an Edit-only profile and recorded here and in docs/TESTING.md; 748 and 749 implement it for their own paths.
- [ ] KRMA-748 and KRMA-749 are both done: warm Edit first pixel p95 <= 50 ms and warm 30-cell grid p95 <= 100 ms with 0 thumbnail swaps and no extra render admissions. `scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW --iterations 30` reports `edit=PASS grid=PASS`; set `KROMORA_LAST_KNOWN_FRAME_ENFORCE_BUDGETS=1` to make a miss fail.
- [ ] Focused tests, Release build, git diff --check, dg validate. Keep the KRMA-734 identity tests green.

## Run notes

Caffeinate the display (`caffeinate -dimu`), one capture at a time, nothing else on the display. See docs/TESTING.md ("KRMA-744 harness repair and first valid capture"). Do not open a child ticket per re-run: a measured miss with a profile and an open ticket is a handoff (ADR-LKF-001).
