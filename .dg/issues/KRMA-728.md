---
id: KRMA-728
title: "Last-known frames: eliminate flashes and make warm presentation instant"
type: feature
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: KRMA-729 prevents cross-asset frames and establishes presentation sessions/telemetry.
      result: pass
      notes: Child verified done; presentation-session and lifecycle suites pass in fast and serial lanes.
    - criterion: KRMA-730 supplies deterministic content-addressed Look identity and delta-aware scans.
      result: pass
      notes: Child verified done; LookSignature and LUTLibrary suites pass in the fast lane.
    - criterion: KRMA-731 replaces PreviewDiskCache with one atomic latest preview per asset.
      result: pass
      notes: No PreviewDiskCache reference remains under Sources; LatestPreviewFrameStore is the production path.
    - criterion: KRMA-732 persists runtime thumbnail frames and transactionally stable cell geometry.
      result: pass
      notes: Child verified done; full fast and serial lanes pass.
    - criterion: KRMA-733 adds bounded, disposable launch hints and visible-window hydration.
      result: pass
      notes: Child verified done; full fast and serial lanes pass.
    - criterion: KRMA-734 passes the fault/performance qualification and updates durable documentation.
      result: pass
      notes: Qualification matrix and measured-state tables are in docs/TESTING.md; identity lane (4 tests incl. 1,000-asset relocation) passes.
    - criterion: The performance and reliability budgets in the plan have recorded release evidence.
      result: pass
      notes: "Evidence is recorded (three Release captures on 4bbc5c5f in docs/TESTING.md). Structural budgets pass (exact warm Edit zero renders/one confirmed frame; stale warm Edit one provisional/at most one confirmed; main-actor p95 median 2.03 ms within the ADR-LKF-001 3 ms tolerance). The wall-clock budgets are NOT met: warm Edit first pixel p95 about 293 ms vs 50 ms, and warm 30-cell grid p95 about 235 ms vs 100 ms. This criterion passes only because owner decision ADR-LKF-001 makes those two budgets non-gating release evidence, tracked unchanged by KRMA-748/749 under KRMA-750. I did not independently re-run the Release benchmark."
  checks_run:
    - swift build (complete, no diagnostics)
    - scripts/ci-tests.sh fast (exit 0; 1462 tests, 0 failures)
    - scripts/ci-tests.sh serial (exit 0; 455 tests, 0 failures)
    - scripts/ci-tests.sh identity (exit 0; 4 tests, 0 failures)
    - git diff --check (clean)
    - dg validate (OK; model-name warnings only)
    - grep for PreviewDiskCache in Sources (none) and Swift 6 escape hatches in Sources (none; only a doc comment)
  findings:
    - "Non-blocking, already tracked: warm Edit first-pixel and warm grid wall-clock budgets remain unmet and are tracked by KRMA-748/KRMA-749 under KRMA-750 per ADR-LKF-001; no new ticket opened."
    - "Non-blocking: the manual smoke check recorded on the epic was a debug-build functional check without screenshots, so it is not timing or visual evidence."
    - "Non-blocking: several test-target helpers use @unchecked Sendable. This predates the epic and is outside the Sources-level guarantee; not changed here."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-01T23:24:03.093Z
  session: 01MUQ5ID44B5W3JIRE
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - architecture
  - performance
  - reliability
  - preview
  - thumbnails
created: 2026-09-30T13:19:17.755Z
updated: 2026-10-01T23:24:03.096Z
depends_on:
  - KRMA-729
  - KRMA-730
  - KRMA-731
  - KRMA-732
  - KRMA-733
  - KRMA-734
blockers: []
estimate: 40
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/PreviewDiskCache.swift
    - Sources/KromoraKit/Models/PortablePackageMaintenance.swift
    - Sources/KromoraKit/Models/ImageCollection.swift
    - Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift
    - Sources/KromoraKit/ViewModels/EditedThumbnailCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - .context/last-known-frame-plan.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
    - docs/STORAGE_POLICY.md
    - docs/TESTING.md
  issues:
    - KRMA-729
    - KRMA-730
    - KRMA-731
    - KRMA-732
    - KRMA-733
    - KRMA-734
  commands:
    - dg context KRMA-728
    - dg validate
---

## Objective

Deliver the reviewed last-known-frame architecture so Edit, Library, and filmstrip paint the
selected photo from trustworthy persisted pixels immediately, refine at most once, and remain safe
under cache loss or corruption.

## Context

The executable design is `.context/last-known-frame-plan.md`. It replaces the current exact-key
preview disk cache rather than adding another preview layer, reuses package content hashes for Look
identity, wires the existing packed thumbnail store into runtime, persists final cell geometry, and
adds bounded launch hydration.

This epic is complete only when its children are verified. Implement children in dependency order;
do not implement production code directly under the epic.

## Non-negotiable product invariants

- A newly selected asset never displays the prior asset.
- A warm surface shows one same-asset candidate and at most one refinement.
- Cached pixels skip rendering only after exact current inputs are resolved.
- Provisional pixels are inert for histogram, scopes, comparison, tools, publication state, and
  cache writes.
- Grid/filmstrip geometry is final before raster arrival.
- Derived-frame deletion/corruption only costs work; it never affects edit/package truth.
- No Core Image object leaves `RenderEngine`, no Swift 6 escape hatch is introduced, and no older
  macOS/Intel fallback is added.

## Acceptance criteria

- [x] KRMA-729 prevents cross-asset frames and establishes presentation sessions/telemetry.
- [x] KRMA-730 supplies deterministic content-addressed Look identity and delta-aware scans.
- [x] KRMA-731 replaces `PreviewDiskCache` with one atomic latest preview per asset.
- [x] KRMA-732 persists runtime thumbnail frames and transactionally stable cell geometry.
- [x] KRMA-733 adds bounded, disposable launch hints and visible-window hydration.
- [x] KRMA-734 passes the fault/performance qualification and updates durable documentation.
- [x] The performance and reliability budgets in the plan have recorded release evidence.

## Implementation notes

Dependency graph:

```text
KRMA-729 ----\
              -> KRMA-731 -> KRMA-732 -> KRMA-733 -> KRMA-734
KRMA-730 ----/                 ^                       ^
       \----------------------/-----------------------/
```

KRMA-728 depends on every child so the epic cannot complete early.

### Comment — claude @ 2026-10-01T22:35:36.640Z

Manual check by the owner on 2026-10-01 against 4bbc5c5f: ran the debug build (swift run), clicked through Library, Edit, and filmstrip selection, and nothing looked wrong. Debug builds run noticeably slower, so this is a functional smoke check and not timing evidence; release timings are the three captures in docs/TESTING.md. Screenshots were not captured.

### Comment — codex @ 2026-10-01T23:13:58.745Z

Epic handoff: KRMA-729 through KRMA-734 are verified done. The latest KRMA-734 report records passing fault, identity, rapid-navigation, cache-pressure, documentation, warning/build/test, Release benchmark, and drawable-count checks. Structural budgets pass; the first-pixel and grid wall-clock misses are recorded in docs/TESTING.md and tracked under ADR-LKF-001/KRMA-750. Updated this epic's acceptance checklist; no production work was added directly under the epic.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-01T23:24:03.093Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] KRMA-729 prevents cross-asset frames and establishes presentation sessions/telemetry. (pass) — Child verified done; presentation-session and lifecycle suites pass in fast and serial lanes.
- [x] KRMA-730 supplies deterministic content-addressed Look identity and delta-aware scans. (pass) — Child verified done; LookSignature and LUTLibrary suites pass in the fast lane.
- [x] KRMA-731 replaces PreviewDiskCache with one atomic latest preview per asset. (pass) — No PreviewDiskCache reference remains under Sources; LatestPreviewFrameStore is the production path.
- [x] KRMA-732 persists runtime thumbnail frames and transactionally stable cell geometry. (pass) — Child verified done; full fast and serial lanes pass.
- [x] KRMA-733 adds bounded, disposable launch hints and visible-window hydration. (pass) — Child verified done; full fast and serial lanes pass.
- [x] KRMA-734 passes the fault/performance qualification and updates durable documentation. (pass) — Qualification matrix and measured-state tables are in docs/TESTING.md; identity lane (4 tests incl. 1,000-asset relocation) passes.
- [x] The performance and reliability budgets in the plan have recorded release evidence. (pass) — Evidence is recorded (three Release captures on 4bbc5c5f in docs/TESTING.md). Structural budgets pass (exact warm Edit zero renders/one confirmed frame; stale warm Edit one provisional/at most one confirmed; main-actor p95 median 2.03 ms within the ADR-LKF-001 3 ms tolerance). The wall-clock budgets are NOT met: warm Edit first pixel p95 about 293 ms vs 50 ms, and warm 30-cell grid p95 about 235 ms vs 100 ms. This criterion passes only because owner decision ADR-LKF-001 makes those two budgets non-gating release evidence, tracked unchanged by KRMA-748/749 under KRMA-750. I did not independently re-run the Release benchmark.
Checks run:
- swift build (complete, no diagnostics)
- scripts/ci-tests.sh fast (exit 0; 1462 tests, 0 failures)
- scripts/ci-tests.sh serial (exit 0; 455 tests, 0 failures)
- scripts/ci-tests.sh identity (exit 0; 4 tests, 0 failures)
- git diff --check (clean)
- dg validate (OK; model-name warnings only)
- grep for PreviewDiskCache in Sources (none) and Swift 6 escape hatches in Sources (none; only a doc comment)
Findings:
- Non-blocking, already tracked: warm Edit first-pixel and warm grid wall-clock budgets remain unmet and are tracked by KRMA-748/KRMA-749 under KRMA-750 per ADR-LKF-001; no new ticket opened.
- Non-blocking: the manual smoke check recorded on the epic was a debug-build functional check without screenshots, so it is not timing or visual evidence.
- Non-blocking: several test-target helpers use @unchecked Sendable. This predates the epic and is outside the Sources-level guarantee; not changed here.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUQ5ID44B5W3JIRE
Summary: Verified the epic. Build, fast, serial and identity lanes pass; wall-clock first-pixel and grid budgets remain unmet and are tracked non-gating under ADR-LKF-001/KRMA-750.
