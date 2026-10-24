---
id: KRMA-738
title: Measure KRMA-734 release drawable budgets on stable Xcode 27
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Release test bundle links on stable Xcode 27.0
      result: pass
      notes: Release capture built and ran on Xcode 27.0 (27A266a).
    - criterion: Capture records machine/OS/commit/source/viewport/cold-warm/cache/sample count with p50/p95
      result: pass
      notes: report.jsonl contains all fields for 4 scenarios (commit 8bb287a7, M1 Pro, macOS 27.0, DSC01019.ARW, 1440x897 pt / 2880x1794 px).
    - criterion: Frame counts, render admissions, crossfades, thumbnail swaps, layout changes recorded
      result: pass
      notes: Records carry provisional/confirmed frames, renderAdmissions, crossfades, thumbnailSwaps, gridMounts and bodyEvaluations (layout passes replaced by SwiftUI mount/body counts per KRMA-744).
    - criterion: Every KRMA-734 budget evaluated, no target redefined
      result: pass
      notes: Exact PASS (0 renders, 1 confirmed); stale PASS (1 provisional, 1 confirmed); warm grid p95 202 ms vs 100 (miss, KRMA-745); warm Edit p95 694 ms vs 50 and main-actor p95 74 ms vs 2 (miss, KRMA-743). Misses are tracked by their own urgent tickets and are not this ticket pass condition.
    - criterion: Results documented in docs/TESTING.md
      result: pass
      notes: KRMA-738/744 sections plus verification re-run paragraph added.
  checks_run:
    - "xcodebuild -version: Xcode 27.0 (27A266a)"
    - "scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW --iterations 30: 0 failures, LAST_KNOWN_FRAME_BUDGET_SUMMARY exact=PASS stale=PASS grid=FAIL edit=FAIL; report.jsonl has 4 records"
    - "git diff --check: pass"
  findings:
    - "Budget misses reproduced: warm grid p95 202 ms (KRMA-745, backlog) and warm Edit first pixel p95 694 ms / main-actor 74 ms (KRMA-743, review). Not caused by this ticket; targets unchanged."
  fixes:
    - Recorded the verification re-run in docs/TESTING.md.
  verification_commits:
    - "73312736"
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-01T16:52:01.475Z
  session: 01MUPROK7T4SJKI7WO
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - performance
created: 2026-09-30T23:39:00.887Z
updated: 2026-10-01T16:52:01.479Z
depends_on:
  - KRMA-741
  - KRMA-742
blockers: []
order: n
board: product
commits:
  - 90088f1c
  - "73312736"
---

## Objective

Measure KRMA-734 release drawable budgets on stable Xcode 27

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-10-01T00:24:28.360Z

Diagnosis update (KRMA-734 verification, 2026-09-30): stable Xcode 27.0 (27A266a) is now installed and selected, but the Release KromoraKitTests.xctest still fails to link under scripts/run-kromora-capture.sh (metal-presentation, realworldtest/DSC01019.ARW, 30 iterations): unresolved SwiftUI opaque type descriptors for View.tag(_:includeOptional:) and View.task(name:priority:file:line:_:), missing CoreAudioTypes, SwiftUICore.tbd not an allowed client. So it is a Release test-bundle link defect, not only a missing toolchain. 'swift build -c release --build-tests' also fails (KromoraKit module not compatible). Acceptance: Release test bundle links; capture records machine/OS/commit/source/viewport/cold-warm/cache/sample count with p50/p95, frame counts, render admissions, crossfades, thumbnail swaps, layout changes; every KRMA-734 budget evaluated (warm Edit p95<=50ms and <=2ms main-actor pre-suspension, exact warm zero renders/one confirmed, stale warm one provisional+<=1 confirmed, 30-cell grid p95<=100ms); results in docs/TESTING.md; no target redefined. Fixtures: realworldtest/*.ARW (script default DSC07826.ARW is absent; pass --source).

### Comment — codex @ 2026-10-01T00:59:03.039Z

Retried the 30-sample drawable capture on stable Xcode 27.0 (27A266a); Release XCTest bundle still fails to link before launch, so no drawable or KRMA-734 budget samples are available. Recorded the host/toolchain, source, commit, link diagnostics, and unmeasured budgets in docs/TESTING.md. Filed urgent dependency KRMA-741 to fix the Release XCTest linkage. Checks: git diff --check; dg validate (OK, existing model-name warnings). Commit: bd1bbe9.

### Comment — claude @ 2026-10-01T16:30:20.580Z

Unblocking chain: KRMA-742 (harness) depends on KRMA-744, which is now implemented in 8bb287a7 and handed to review. The required fields and every KRMA-734 budget are now evaluated by one capture (docs/TESTING.md, KRMA-744 section): exact PASS, stale PASS, grid p95 214 ms vs 100 (KRMA-745), warm Edit first pixel p95 664 ms vs 50 and main-actor p95 72 ms vs 2 (KRMA-743). Once KRMA-742 passes verification this ticket's acceptance (release test bundle links, capture records the fields, every budget evaluated, results documented, no target redefined) is met; budget misses are tracked by their own urgent tickets rather than being this ticket's pass condition.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## Objective

Parent: KRMA-734. Install/select Xcode 27.0 stable (27A266a), then run the Release drawable capture (`scripts/run-kromora-capture.sh --benchmark metal-presentation`) and record the required fields and p50/p95 results in docs/TESTING.md. Verify every KRMA-734 architecture budget: warm Edit p95 <= 50 ms, <= 2 ms main-actor work before first suspension, exact warm Edit zero renders, 30-cell grid p95 <= 100 ms, and crossfade/swap/layout counts.

## Diagnosis

The 2026-09-30 verification found `xcode-select -p` still pointing at Xcode-beta.app (27A5252f) and no stable Xcode installed, although the human blocker was marked resolved. The Release XCTest bundle cannot link on the beta SDK, so no budget has been measured. Any measured miss needs its own urgent ticket; do not redefine targets.

- 2026-10-01T02:14:13.216Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Release test bundle links on stable Xcode 27.0 (pass) — Links after KRMA-741; swift test -c release builds and the capture runs.
- [x] Capture runs and records machine/OS/commit/source/viewport/cold-warm/cache/sample count with p50/p95 (pass) — metal-presentation, DSC01019.ARW, 30 iterations: input-to-present p50/p95 24.4/24.5 ms; release-to-settled p95 49.5 ms. Recorded in docs/TESTING.md. Required fixing a stale bundle name in scripts/run-kromora-capture.sh.
- [ ] Frame counts, render admissions, crossfades, thumbnail swaps, layout changes recorded (fail) — No harness in the test target emits these.
- [ ] Every KRMA-734 budget evaluated (warm Edit p95<=50ms and <=2ms pre-suspension, exact/stale warm counts, 30-cell grid p95<=100ms) (fail) — Unmeasured; no benchmark exists for them. Child KRMA-742. No target redefined.
- [x] Results documented in docs/TESTING.md (pass) — Section KRMA-738 stable Release capture added.
Checks run:
- xcodebuild -version: Xcode 27.0 (27A266a); macOS 27.0 (26A428); Apple M1 Pro
- scripts/run-kromora-capture.sh --benchmark metal-presentation --source realworldtest/DSC01019.ARW --iterations 30: pass after script fix, trace saved
- git diff --check: pass
- dg validate: pass (model warnings only)
Findings:
- scripts/run-kromora-capture.sh referenced nonexistent KromoraPackageTests.xctest; fixed to KromoraKitTests.xctest.
- The only real-drawable benchmark measures single-photo presentation; warm Edit navigation, exact/stale frame counts, main-actor pre-suspension time, and 30-cell grid hydration have no Release harness. Filed urgent KRMA-742.
Fixes:
- Corrected test bundle name in scripts/run-kromora-capture.sh; documented the capture in docs/TESTING.md.
Verification commits:
- 90088f1c
Actor: claude
Resolved model: sonnet
Pickup session: 01MUOWCWF6TVM29TTQ
Summary: Release capture now runs on stable Xcode 27.0 (presentation p95 24.5 ms), but the warm Edit, exact/stale frame count, and 30-cell grid budgets have no benchmark harness and remain unmeasured. Urgent child KRMA-742 filed.

- 2026-10-01T16:52:01.475Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Release test bundle links on stable Xcode 27.0 (pass) — Release capture built and ran on Xcode 27.0 (27A266a).
- [x] Capture records machine/OS/commit/source/viewport/cold-warm/cache/sample count with p50/p95 (pass) — report.jsonl contains all fields for 4 scenarios (commit 8bb287a7, M1 Pro, macOS 27.0, DSC01019.ARW, 1440x897 pt / 2880x1794 px).
- [x] Frame counts, render admissions, crossfades, thumbnail swaps, layout changes recorded (pass) — Records carry provisional/confirmed frames, renderAdmissions, crossfades, thumbnailSwaps, gridMounts and bodyEvaluations (layout passes replaced by SwiftUI mount/body counts per KRMA-744).
- [x] Every KRMA-734 budget evaluated, no target redefined (pass) — Exact PASS (0 renders, 1 confirmed); stale PASS (1 provisional, 1 confirmed); warm grid p95 202 ms vs 100 (miss, KRMA-745); warm Edit p95 694 ms vs 50 and main-actor p95 74 ms vs 2 (miss, KRMA-743). Misses are tracked by their own urgent tickets and are not this ticket pass condition.
- [x] Results documented in docs/TESTING.md (pass) — KRMA-738/744 sections plus verification re-run paragraph added.
Checks run:
- xcodebuild -version: Xcode 27.0 (27A266a)
- scripts/run-kromora-capture.sh --benchmark last-known-frame --source realworldtest/DSC01019.ARW --iterations 30: 0 failures, LAST_KNOWN_FRAME_BUDGET_SUMMARY exact=PASS stale=PASS grid=FAIL edit=FAIL; report.jsonl has 4 records
- git diff --check: pass
Findings:
- Budget misses reproduced: warm grid p95 202 ms (KRMA-745, backlog) and warm Edit first pixel p95 694 ms / main-actor 74 ms (KRMA-743, review). Not caused by this ticket; targets unchanged.
Fixes:
- Recorded the verification re-run in docs/TESTING.md.
Verification commits:
- 73312736
Actor: claude
Resolved model: sonnet
Pickup session: 01MUPROK7T4SJKI7WO
