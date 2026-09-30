---
id: KRMA-734
title: Qualify last-known frames under faults, load, and release benchmarks
type: task
status: review
priority: urgent
verification_report:
  verdict: blocker
  acceptance_criteria:
    - criterion: Release benchmark evidence records every required field and reports p50/p95, frame counts
      result: fail
      notes: No release capture; docs/TESTING.md records only a failed link attempt.
    - criterion: All architecture budgets pass
      result: fail
      notes: Unmeasured. Blocker KRMA-738 filed.
    - criterion: Confirmed/provisional frame counts are actual drawable presentations
      result: fail
      notes: No drawable capture produced.
  checks_run:
    - "xcode-select -p; xcodebuild -version: Xcode-beta 27A5252f, stable not installed"
  findings:
    - Human blocker marked resolved but stable Xcode 27.0 is not installed; budgets unmeasured. Tracked in KRMA-738.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-30T23:39:15.222Z
  session: 01MUOQY1ODO4AQ3O7F
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - performance
  - reliability
  - verification
  - caching
created: 2026-09-30T13:19:21.193Z
updated: 2026-09-30T23:39:15.340Z
depends_on:
  - KRMA-729
  - KRMA-730
  - KRMA-731
  - KRMA-732
  - KRMA-733
  - KRMA-737
blockers:
  - id: evt_muoncf71_uxhj3k
    type: human
    reason: The only local toolchain is /Applications/Xcode-beta.app (Xcode 27.0 build 27A5252f); its beta SDK failed to link the Release XCTest bundle. Xcode 27.0 stable (build 27A266a) has since been released but is not installed here, so the release drawable and last-known-frame budgets remain unmeasured on stable.
    action: Install/select Xcode 27.0 stable (build 27A266a) on this Apple Silicon host, rerun the Release XCTest drawable capture and budgets, then resume KRMA-734 at verification.
    created_at: 2026-09-30T21:57:59.149Z
    resolved_at: 2026-09-30T22:43:18.728Z
    resolved_by: web
estimate: 8
order: zq
board: product
blocked_reason: The only local toolchain is /Applications/Xcode-beta.app (Xcode 27.0 build 27A5252f); its beta SDK failed to link the Release XCTest bundle. Xcode 27.0 stable (build 27A266a) has since been released but is not installed here, so the release drawable and last-known-frame budgets remain unmeasured on stable.
blocked_action: Install/select Xcode 27.0 stable (build 27A266a) on this Apple Silicon host, rerun the Release XCTest drawable capture and budgets, then resume KRMA-734 at verification.
blocked_from_status: ready
context:
  files:
    - Sources/KromoraKit/Models/Observability.swift
    - Sources/KromoraKit/Models/PreviewDiskCache.swift
    - Sources/KromoraKit/Models/PortablePackageMaintenance.swift
    - Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift
    - Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift
    - Tests/KromoraKitTests/
    - scripts/ci-tests.sh
    - scripts/run-kromora-capture.sh
  docs:
    - .context/last-known-frame-plan.md
    - docs/TESTING.md
    - docs/STORAGE_POLICY.md
    - docs/ENGINEERING_GUIDE.md
    - docs/APP_ARCHITECTURE.md
  issues: []
  commands:
    - scripts/ci-tests.sh warning-gate
    - swift build
    - swift test
    - swift build -c release
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - scripts/ci-tests.sh identity
    - scripts/ci-tests.sh optional
    - git diff --check
    - dg validate
---

## Objective

Prove the complete last-known-frame system remains correct under corruption, interruption,
replacement, eviction, and rapid navigation, and record release-build performance against the
architecture budgets.

## Context

This is Phase 6 and starts only after KRMA-729 through KRMA-733 are done. Do not paper over failures
with retries or relaxed assertions. Fix localized defects found here; create urgent child blockers
for broader defects.

Build one deterministic scenario matrix that covers preview envelopes, packed thumbnails,
transactional geometry, Look deltas, launch hints, and presentation generations. Use existing fault
injection and fake-render seams for correctness, then use real ImageIO/Core Image/AppKit paths in the
serial/optional lanes where needed.

Measure release builds on representative Apple Silicon. Record machine, OS, commit, source
format/dimensions, viewport/backing pixels, cold/warm state, cache state, and sample count. Fake
renderer measurements are orchestration evidence only.

Required architecture budgets from the plan:

- warm Edit navigation: correct-photo provisional pixels p95 <= 50 ms, with <= 2 ms main-actor work
  before first suspension;
- exact warm Edit: zero preview renders and one confirmed frame;
- stale warm Edit: one provisional plus at most one confirmed replacement;
- warm 30-cell grid: p95 visible frame hydration <= 100 ms on the reference system;
- unchanged Look rescan: zero preview/edited-thumbnail render admissions;
- pixel epoch bump: no wipe or blanking;
- navigation burst: bounded work and zero obsolete publications.

If hardware variance makes a wall-clock limit unsuitable for required CI, keep deterministic
structural assertions in CI and record the wall-clock result as release benchmark evidence. Do not
silently drop the budget.

## Acceptance criteria

- [ ] Fault tests cover truncated/overflow/corrupt preview envelopes, corrupt/missing pack index,
      interrupted preview and pack writes, transaction failure around edit+geometry, deleted
      `Derived`, and corrupt/oversized LaunchHints.
- [ ] Identity tests cover in-place source replacement, package relocation, virtual copies, asset
      deletion, Look replacement at the same ID, raster-space mismatch, pixel epoch change, and
      storage format change.
- [ ] Rapid A -> B -> A and long filmstrip scrubs prove obsolete cache/embedded/render/thumbnail/scan
      completions never publish and work stays bounded.
- [ ] Cache-pressure tests prove preview LRU cap/pinning and thumbnail compaction without evicting or
      corrupting active visible entries.
- [ ] Release benchmark evidence records every required field and reports p50/p95, frame counts,
      render admissions, crossfades, thumbnail swaps, and layout changes.
- [ ] All architecture budgets pass. If a budget misses, this ticket stays open until an urgent
      blocker ticket records the measured miss and diagnosis and is linked in `blockers`; the
      ticket is not done while any budget is unmet and unticketed. No target is redefined in
      verification.
- [ ] "Confirmed frame" and "provisional frame" counts are actual drawable presentations, and
      KRMA-731/732/733 assertions use this same definition.
- [ ] `STORAGE_POLICY.md`, `ENGINEERING_GUIDE.md`, `APP_ARCHITECTURE.md`, and `TESTING.md` describe
      the landed implementation, ownership, failure semantics, migration, and benchmark method.
- [ ] Warning gate, build, full test, release build, fast, serial, identity, `git diff --check`, and
      `dg validate` pass. Optional RAW/manual drawable checks are run when fixtures/display exist and
      are explicitly marked unavailable otherwise.

## Implementation notes

- Count actual confirmed drawable presentations; screenshots do not establish sequence or latency.
- Cache loss/corruption must degrade to ordinary decode/render, never package-open failure.
- Keep verification artifacts out of durable package truth and within documented size/privacy
  limits.

### Comment — codex @ 2026-09-30T21:57:53.883Z

Qualification handoff committed as 70d7907. Warning gate, swift build, swift test, Release app build, fast, serial (455/455 with one skip), identity (4/4), git diff --check, and dg validate passed. The optional lane with local IMG_0371.DNG exposed two failing test methods/three assertions; urgent follow-up KRMA-737 records the RAW preparation and decoder seed diagnosis and is linked as a dependency. Release drawable capture could not link its XCTest bundle with the only installed toolchain, Xcode 27.0 beta; no release latency or actual drawable-count evidence was produced. Architecture budgets remain unmeasured.,

### Comment — codex @ 2026-09-30T22:33:32.248Z

Toolchain guidance is now Xcode 27+ with the macOS 27 SDK; the app deployment floor remains macOS 26. CI now targets GitHub's arm64 xcode-27 runner image (currently preview). Apple's release page lists Xcode 27.0 stable build 27A266a, released September 14, 2026: https://developer.apple.com/news/releases/?id=01062025a. This host still selects /Applications/Xcode-beta.app build 27A5252f, so the human blocker remains until the Release XCTest drawable capture is repeated successfully on stable Xcode 27.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-30T23:39:15.339Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] Release benchmark evidence records every required field and reports p50/p95, frame counts (fail) — No release capture; docs/TESTING.md records only a failed link attempt.
- [ ] All architecture budgets pass (fail) — Unmeasured. Blocker KRMA-738 filed.
- [ ] Confirmed/provisional frame counts are actual drawable presentations (fail) — No drawable capture produced.
Checks run:
- xcode-select -p; xcodebuild -version: Xcode-beta 27A5252f, stable not installed
Findings:
- Human blocker marked resolved but stable Xcode 27.0 is not installed; budgets unmeasured. Tracked in KRMA-738.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUOQY1ODO4AQ3O7F
Summary: Release drawable budgets remain unmeasured: host still has only Xcode 27.0 beta (27A5252f); stable not installed. Child KRMA-738 filed.
