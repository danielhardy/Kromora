---
id: KRMA-745
title: Fix warm 30-cell grid re-entry latency budget miss
type: bug
status: backlog
priority: urgent
verification_report:
  verdict: blocker
  acceptance_criteria:
    - criterion: Attribute the warm grid re-entry time to concrete views or work (grid-only profile or signposts), recorded in ticket and docs/TESTING.md
      result: fail
      notes: Only a whole-test Time Profiler trace was recorded; docs/TESTING.md states it does not isolate the grid interval. No per-view attribution exists.
    - criterion: Fix without changing KRMA-734 targets; no thumbnail swaps or extra render admissions
      result: fail
      notes: 312fb63 (plain AppViewModel reference) is safe and keeps 0 swaps/0 admissions, but did not reduce latency, so the grid is not fixed.
    - criterion: Re-run 30-sample capture on awake display and meet grid p95 <= 100 ms (grid=PASS)
      result: fail
      notes: "Ran at HEAD 1145f266 on an awake display: grid p50/p95 = 217/231 ms; LAST_KNOWN_FRAME_BUDGET_SUMMARY exact=PASS stale=PASS grid=FAIL edit=FAIL."
    - criterion: Run focused tests, Release build, git diff --check, dg validate
      result: fail
      notes: Not run after the budget failure made the outcome a blocker; dg validate only emitted pre-existing verification_agent model warnings.
  checks_run:
    - KROMORA_LAST_KNOWN_FRAME_ENFORCE_BUDGETS=1 scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW --iterations 30 (grid=FAIL, p95 230.6 ms)
    - dg validate (warnings only)
  findings:
    - Warm grid p95 is 231 ms against a 100 ms budget; the KRMA-745 change had no measurable effect (baseline 193/214 ms).
    - The required grid-only attribution was never produced.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-01T20:19:03.916Z
  session: 01MUPZ15ZK8ZBULZIU
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - verification
created: 2026-10-01T16:29:43.190Z
updated: 2026-10-01T21:25:56.282Z
depends_on:
  - KRMA-744
  - KRMA-749
blockers:
  - id: evt_muptni76_meuazs
    type: human
    reason: The required visible-window 30-sample Release capture cannot run because the display is asleep or locked (occlusionState=8192, isVisible=false, keyWindow=false, appActive=false), so the grid budget result and post-change profile remain unverified.
    action: Unlock the Mac and keep the display awake; reply when the desktop is ready so I can run the required 30-sample capture and grid-only profile.
    created_at: 2026-10-01T17:42:20.130Z
    resolved_at: 2026-10-01T19:37:08.854Z
    resolved_by: web
order: zx
board: product
blocked_reason: The required visible-window 30-sample Release capture cannot run because the display is asleep or locked (occlusionState=8192, isVisible=false, keyWindow=false, appActive=false), so the grid budget result and post-change profile remain unverified.
blocked_action: Unlock the Mac and keep the display awake; reply when the desktop is ready so I can run the required 30-sample capture and grid-only profile.
blocked_from_status: ready
---

## Objective

Bring warm 30-cell Library grid re-entry within the unchanged KRMA-734 budget (p95 <= 100 ms visible-frame hydration) without redefining the target.

## Context

First valid capture (KRMA-744 harness, 2026-10-01): Release, Apple M1 Pro, macOS 27.0 (26A428), stable Xcode 27.0, DSC01019.ARW in a 30-cell grid, viewport 1440x897 pt / 2880x1794 px, 30 warm samples. Warm grid re-entry p50/p95 = 193 / 214 ms against p95 <= 100 ms. Each sample leaves Edit, waits for LibraryGridView to unmount, re-enters, waits for a new mount with every visible cell populated, then runs one layout + display pass. Per sample: 1 grid mount, about 11 SwiftUI body evaluations, 0 thumbnail swaps, 0 render admissions. Records: `/tmp/kromora-capture/KROMORA-last-known-frame-DSC01019-20261001-101504-report.jsonl`; method and full table in docs/TESTING.md ("KRMA-744 harness repair and first valid capture").

Partial diagnosis: a 1 ms `/usr/bin/sample` of the xctest main thread during a 100-sample run shows none of the whole-file SHA-256 time (see KRMA-743) under grid mount or thumbnail demand. The grid path is dominated by SwiftUI graph update and layout (`ViewLayoutEngine.sizeThatFits`, `AG::Graph::update_attribute`, `NSHostingView` transactions). Not yet attributed to a specific view: cell body cost, whether all 30 cells are laid out eagerly instead of lazily, and the `.onAppear` thumbnail demand in `LibraryGridView`. A focused profile of the grid mount alone is the first step.

## Acceptance criteria

- [ ] Attribute the warm grid re-entry time to concrete views or work (a grid-only profile or signposts), recorded in this ticket and docs/TESTING.md.
- [ ] Fix it without changing the KRMA-734 targets; no visible-cell thumbnail swaps and no extra render admissions.
- [ ] Re-run `scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW --iterations 30` on an unlocked, awake display and meet warm 30-cell grid p95 <= 100 ms (the `LAST_KNOWN_FRAME_BUDGET_SUMMARY` line reports `grid=PASS`).
- [ ] Run relevant focused tests, Release build, git diff --check, and dg validate.

## Implementation notes

Run the capture with `caffeinate -d` active and nothing else using the display; one capture at a time. Set `KROMORA_LAST_KNOWN_FRAME_ENFORCE_BUDGETS=1` to make a miss fail the test. The harness is Tests/KromoraKitTests/LastKnownFrameReleaseBenchmark.swift.


### Comment — codex @ 2026-10-01T17:42:19.861Z

Implemented and committed 312fb63: LibraryGridView now stores AppViewModel as a plain reference so unrelated view-model publications do not directly invalidate the whole grid. Focused LibraryGridTests and LibraryChromeLayoutTests passed (18 tests); Release build, git diff --check, and dg validate passed. The 5-sample Time Profiler capture reported warm-grid p50/p95 205.7/206.7 ms with zero thumbnail swaps and zero render admissions; its SwiftUI main-thread symbols include AG::Graph::UpdateStack, ForEachState, ContentView.body, and LibraryMosaicRow.body, but the full test trace does not isolate the grid interval, and the SwiftUI template emitted no view-update rows. A 30-sample run after the change could not capture: occlusionState=8192, isVisible=false, keyWindow=false, appActive=false. The unchanged p95 target is not verified.

### Comment — claude @ 2026-10-01T20:23:29.968Z

Superseded by KRMA-750 per ADR-LKF-001 (wall-clock budgets are non-gating release evidence). Parked in backlog; no work is lost. Anything this ticket produced stays in git history. Lead from the stopped KRMA-749 run (uncommitted AppViewModel handoff-animation change) is recorded in KRMA-750.

## Agent log

- 2026-10-01T20:19:04.113Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] Attribute the warm grid re-entry time to concrete views or work (grid-only profile or signposts), recorded in ticket and docs/TESTING.md (fail) — Only a whole-test Time Profiler trace was recorded; docs/TESTING.md states it does not isolate the grid interval. No per-view attribution exists.
- [ ] Fix without changing KRMA-734 targets; no thumbnail swaps or extra render admissions (fail) — 312fb63 (plain AppViewModel reference) is safe and keeps 0 swaps/0 admissions, but did not reduce latency, so the grid is not fixed.
- [ ] Re-run 30-sample capture on awake display and meet grid p95 <= 100 ms (grid=PASS) (fail) — Ran at HEAD 1145f266 on an awake display: grid p50/p95 = 217/231 ms; LAST_KNOWN_FRAME_BUDGET_SUMMARY exact=PASS stale=PASS grid=FAIL edit=FAIL.
- [ ] Run focused tests, Release build, git diff --check, dg validate (fail) — Not run after the budget failure made the outcome a blocker; dg validate only emitted pre-existing verification_agent model warnings.
Checks run:
- KROMORA_LAST_KNOWN_FRAME_ENFORCE_BUDGETS=1 scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW --iterations 30 (grid=FAIL, p95 230.6 ms)
- dg validate (warnings only)
Findings:
- Warm grid p95 is 231 ms against a 100 ms budget; the KRMA-745 change had no measurable effect (baseline 193/214 ms).
- The required grid-only attribution was never produced.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUPZ15ZK8ZBULZIU
Summary: Warm 30-cell grid p95 is 231 ms (budget 100 ms) on an awake display; the observation-narrowing change did not help and no grid-only attribution exists. Child KRMA-749 tracks attribution and the real fix.
