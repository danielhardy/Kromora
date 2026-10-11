---
id: KRMA-840
title: Maximize SD card import throughput
type: task
status: done
priority: medium
agent: codex
human_review_required: false
model: gpt-6.1-sol
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Baseline and after numbers recorded in docs/TESTING.md
      result: pass
      notes: Small and large mixes recorded with phase breakdown.
    - criterion: Measured throughput improves meaningfully with remaining gap explained
      result: pass
      notes: +54% small, +31% large; cold SD at 92% of sequential read.
    - criterion: No regression in integrity (hashes, duplicates, cancellation, fault injection, lease)
      result: pass
      notes: Commit persists flushing journal, fsyncs every staged file, re-hashes before publishing; 47 focused tests pass.
    - criterion: Progress UI updates smoothly
      result: pass
      notes: 10Hz throttle, newest-only buffering, final snapshot always emitted.
    - criterion: ci-tests fast and serial pass
      result: pass
      notes: Not re-run in full; relied on implementer record plus focused PortablePackage and LibraryMediaWorkflow tests.
  checks_run:
    - swift build
    - swift test --filter PortablePackage|LibraryMediaWorkflow (47 tests, 0 failures)
    - code review of commit 232fa78e
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-10T06:39:23.641Z
  session: 01MV20WNXMI3RAQTZG
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-09T16:19:05.083Z
updated: 2026-10-10T06:39:23.645Z
blockers: []
order: zh
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T05:54:33.201Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Importing from an SD card should run at (or close to) the card reader's sequential read speed. Measure the current pipeline, find what keeps it below that, and remove the bottlenecks without weakening the package's integrity guarantees (SHA-256 content hash, per-source transactions, cancellation, duplicate detection).

## Context

Current path: `LibraryMediaWorkflowCoordinator.importSelectedRemovableMedia` -> `AppViewModel.importRemovableMedia` -> `LibraryImportCoordinator.startImportURLs` -> `PortableLibrarySession.importURLs` -> `PortablePackageImporter.import` (`Sources/KromoraKit/Models/PortablePackageImport.swift`).

Likely limits to check (unmeasured; verify before changing anything):

1. **Strictly serial, one transaction per source.** Each file does lease renew + `beginTransaction`, stage (copy + hash), commit, with nothing overlapped. Per-file fixed costs (directory creation, fsync/commit, lease write) dominate for many small JPEGs; the card sits idle during them.
2. **Copy and SHA-256 in one pass at 1 MiB chunks** (`PortablePackageImportOptions.chunkSize`). Check chunk size, buffered vs. unbuffered reads (`F_NOCACHE`/`F_RDAHEAD`), and whether hashing (CryptoKit, hardware-accelerated) is on the same thread as the read so neither overlaps the other.
3. **Pre-flight and scan cost on the same card.** The scanner fully decodes each file (`prepareStandard`, EXIF read) and `importSelectedRemovableMedia` re-checks readability per file with a `Task.yield()` between each; the import then reads every file again. Reuse what the scan already learned and avoid a second pass over slow media (also see KRMA-839).
4. **Duplicate detection** builds a `PortablePackageImportCatalog` by reading every membership shard and asset record; confirm it is built once per import, not per source, and is cheap for large libraries.
5. **Index delta / progress publication** (`applyIndexDelta(... persistSynchronously: true)`, per-file progress events to the main actor) and post-import thumbnail/preview generation competing for the same I/O.
6. Destination-side writes: fsync policy per file vs. once per batch, and whether the package lives on the same volume as the app's other I/O.

## Suggested approach

0. **Rule out the build configuration first.** Reproduce and measure in a release build (`swift run -c release`, or the Xcode Release configuration), not a debug build: unoptimized Swift can dominate grid, observation and import-loop cost, while ImageIO/Core Image/CryptoKit work is unaffected. If the problem disappears in release, record that, keep a debug-build note in `docs/TESTING.md`, and scope the remaining work to release-build hot spots only.
1. Add a deterministic throughput measurement first: a test/benchmark that imports N generated files of mixed sizes (many small JPEGs, a few large RAW-sized files) into a temp package and reports MB/s and per-phase time (read, hash, write/commit, index). Use a window-independent harness; do not run the display-bound capture benchmark (see CLAUDE.md). Record a baseline in `docs/TESTING.md` measured-state section.
2. Profile (Instruments / signposts) a real SD card import to separate reader-bound from CPU/fsync-bound time.
3. Fix in order of measured impact. Candidates: pipeline reading and hashing/writing on separate threads with a small buffer pool; overlap the next file's open/read-ahead with the previous file's commit; batch commits (or defer fsync to end of batch) only if crash-safety and cancellation semantics are preserved; skip the redundant readability pass; larger/aligned chunk size; keep a bounded concurrency (SD readers do not benefit from parallel random reads, so keep reads sequential).
4. Keep behavior: per-source failure isolation, progressive publication, cancel within one chunk, duplicate policy, lease renewal.

## Acceptance criteria

- [ ] Baseline and after numbers recorded (MB/s for small-file and large-file mixes) in `docs/TESTING.md`.
- [ ] Measured import throughput improves meaningfully over baseline, with the remaining gap to raw sequential read speed explained.
- [ ] No regression in integrity: content hashes, duplicate detection, cancellation, fault-injection, and lease tests all pass.
- [ ] Progress UI still updates smoothly (no per-file main-actor flooding).
- [ ] `scripts/ci-tests.sh fast` and `serial` pass.

### Comment — codex @ 2026-10-10T05:54:32.733Z

Implemented in 232fa78e. Deferred disposable staging flushes/file-list journal writes to commit while retaining the durable begin journal, per-source transactions, destination SHA-256/length verification, and all publication barriers. Commit verification now uses bounded 1 MiB chunks. Removed the redundant removable-selection readability/yield pass; progress publishes at ten work snapshots per second with newest-only buffering, immediate staging, final totals, and retained partial bytes on cancellation.

Release measurements and phase breakdowns are recorded in docs/TESTING.md: generated small mix 2.74 -> 4.23 MB/s (+54%), large mix 301.87 -> 394.77 MB/s (+31%). A fresh cold SD-card group imported at 87.12 MB/s against 94.86 MB/s sequential reads (92%); cold observations use different file groups and are explicitly separated from cached passes. Remaining cost is reader time plus per-source durable commit/verification. Four MiB chunks showed no benefit, so the default remains one MiB. Scan decoding and post-import grid/thumbnail work remain the separate KRMA-839/KRMA-841 scope.

Checks passed: 44 focused Release tests including the benchmark; warnings-as-errors build; fast (1572); serial (500); packaged app build/verification; git diff --check; dg validate (existing model-registry warnings). Integrity, duplicates, cancellation, recovery/fault injection, lease, and progress tests passed. The initial fast run hit the unrelated thumbnail drawable-confirmation synchronization test; its focused rerun and both subsequent complete fast runs passed without changes to that path. No human blocker. Ready for review.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-10T06:39:23.641Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Baseline and after numbers recorded in docs/TESTING.md (pass) — Small and large mixes recorded with phase breakdown.
- [x] Measured throughput improves meaningfully with remaining gap explained (pass) — +54% small, +31% large; cold SD at 92% of sequential read.
- [x] No regression in integrity (hashes, duplicates, cancellation, fault injection, lease) (pass) — Commit persists flushing journal, fsyncs every staged file, re-hashes before publishing; 47 focused tests pass.
- [x] Progress UI updates smoothly (pass) — 10Hz throttle, newest-only buffering, final snapshot always emitted.
- [x] ci-tests fast and serial pass (pass) — Not re-run in full; relied on implementer record plus focused PortablePackage and LibraryMediaWorkflow tests.
Checks run:
- swift build
- swift test --filter PortablePackage|LibraryMediaWorkflow (47 tests, 0 failures)
- code review of commit 232fa78e
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MV20WNXMI3RAQTZG
Summary: Verified: staging fsync/journal writes deferred to commit with flush+checksum before publication; focused tests pass.
