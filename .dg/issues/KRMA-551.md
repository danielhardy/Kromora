---
id: KRMA-551
title: Extract LibraryImportCoordinator for package import entry points
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: LibraryImportCoordinator extracted as shared package-write boundary for URL/data imports
      result: pass
      notes: 6664e61 moves generations, handles, progress observation, fencing, shutdown; AppViewModel keeps presentation.
    - criterion: Boundary documented and covered by focused tests
      result: pass
      notes: APP_ARCHITECTURE.md updated; coordinator tests plus new queued-cancel regression test.
  checks_run:
    - "swift build: pass"
    - "LibraryImportCoordinatorTests (2): pass"
    - "PortableLibrarySessionTests incl. new test (12): pass"
    - "PortablePackageImportTests + ImageWorkSchedulerTests: pass"
    - "PackageSettingsTests: pass"
    - "git diff --check: pass"
    - "negative control of new test vs reverted fix (hang reproduced): pass"
  findings:
    - "major: queued-cancel left progress stream unterminated, risking a quit-time hang in the new shutdown await; fixed at source"
    - "minor: progress-sink finish-before-iterate race hardened"
    - "minor: removed uncalled cancelCurrent()"
  fixes:
    - finish progress sink from scheduler terminal callback on every outcome
    - sticky progress-sink finish for late installers
    - removed dead cancelCurrent()
    - added queued-cancel regression test
  verification_commits:
    - cbd9e5b
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-23T11:54:04.339Z
  session: 01MUE1ECVF7KUO1WFL
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - cleanup
  - architecture
  - app-model
created: 2026-09-23T07:59:54.627Z
updated: 2026-09-23T11:54:04.341Z
depends_on:
  - KRMA-529
order: y
board: product
commits:
  - cbd9e5b
---

## Objective

Extract LibraryImportCoordinator for package import entry points

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ]

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-23T11:45:48.373Z

Implemented in commit 6664e61: extracted LibraryImportCoordinator as the shared package-write boundary for URL/data imports from Open, folders, Photos, and removable media. It owns import generations, worker handles, progress observation, stale-result fencing, and observer shutdown; AppViewModel keeps presentation and collection updates. Documented the ownership boundary and added two focused fake-only generation/shutdown tests. Checks: swift build passed; swift test --filter LibraryImportCoordinatorTests passed (2 tests); git diff --check passed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-23T11:54:04.339Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] LibraryImportCoordinator extracted as shared package-write boundary for URL/data imports (pass) — 6664e61 moves generations, handles, progress observation, fencing, shutdown; AppViewModel keeps presentation.
- [x] Boundary documented and covered by focused tests (pass) — APP_ARCHITECTURE.md updated; coordinator tests plus new queued-cancel regression test.
Checks run:
- swift build: pass
- LibraryImportCoordinatorTests (2): pass
- PortableLibrarySessionTests incl. new test (12): pass
- PortablePackageImportTests + ImageWorkSchedulerTests: pass
- PackageSettingsTests: pass
- git diff --check: pass
- negative control of new test vs reverted fix (hang reproduced): pass
Findings:
- major: queued-cancel left progress stream unterminated, risking a quit-time hang in the new shutdown await; fixed at source
- minor: progress-sink finish-before-iterate race hardened
- minor: removed uncalled cancelCurrent()
Fixes:
- finish progress sink from scheduler terminal callback on every outcome
- sticky progress-sink finish for late installers
- removed dead cancelCurrent()
- added queued-cancel regression test
Verification commits:
- cbd9e5b
Actor: pi
Resolved model: unknown
Pickup session: 01MUE1ECVF7KUO1WFL
Summary: KRMA-551 passes verification. Extraction is behavior-preserving; one real defect found and fixed: queued-cancel could leave the import progress stream unterminated and hang the new shutdown await. All checks green.
