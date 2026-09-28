---
id: KRMA-638
title: "Pre-existing serial-lane fixture failures: IdentityRegressionGateTests/PreviewCutoverTests/ThumbnailTests"
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: scripts/ci-tests.sh serial passes with 0 failures on a clean HEAD checkout.
      result: pass
      notes: Ran on HEAD 90811f0. 427 tests, 1 skipped (RAW fixture opt-in), 0 failures, including IdentityRegressionGateTests, PreviewCutoverTests, and ThumbnailTests. Pre-existing uncommitted WIP (untracked RetouchModels.swift/GeometryPointMapping.swift and their tests, tracked separately as KRMA-640) was temporarily moved out of the tree to get a clean build, then restored byte-identical afterward; unrelated staged changes to AppViewModel.swift/PreviewAdmissionCoordinator.swift/DevelopInspectorTests.swift were left untouched throughout.
  checks_run:
    - scripts/ci-tests.sh serial (full run, 427 tests, 0 failures, 1 skipped)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T21:34:14.172Z
  session: 01MUIWIJ488VZJO7L2
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-26T17:25:14.059Z
updated: 2026-09-28T14:41:32.921Z
parent: KRMA-631
blockers: []
order: hzzzzzzn
board: product
---

## Objective

Pre-existing serial-lane fixture failures: IdentityRegressionGateTests/PreviewCutoverTests/ThumbnailTests

## Context

Found while verifying KRMA-631 (capture metadata preview overlay). On a clean checkout of
HEAD (91c485c, no uncommitted changes), `scripts/ci-tests.sh serial` fails deterministically
(reproduced individually with `--no-parallel`, not flaky):

- `IdentityRegressionGateTests.testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore`
  — `NSCocoaErrorDomain Code=4` removing `relocated-library` (underlying POSIX "No such file or
  directory").
- `PreviewCutoverTests.testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument` and
  `PreviewCutoverTests.testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto` — both fail
  reading `asset.json` from a `.kromoralibrary` fixture at `EditDocumentStore.swift:289` with
  "No such file or directory".
- `ThumbnailTests.testImportingFromDataAlsoProducesThumbnails` — asserts a non-nil imported
  library URL but gets `nil`.

All four point at a shared root cause in library/asset fixture setup or teardown (missing
files where a `.kromoralibrary`/import fixture is expected), not anything touched by KRMA-631's
diff (`ImageMetadata.swift`, `KeyboardShortcuts.swift`, `MenuCommands.swift`,
`PreviewView.swift`).

## Acceptance criteria

- [ ] `scripts/ci-tests.sh serial` passes with 0 failures on a clean HEAD checkout.

## Implementation notes

Start from `TempDirectoryTestCase`/fixture setup shared by these suites — the common thread is
a `.kromoralibrary`-style fixture missing an expected file at test time.

### Comment — codex @ 2026-09-26T21:27:58.065Z

Verified KRMA-638 on clean HEAD 90811f0, which already contains the fixture/import corrections for the failures in this issue.  passed: 427 tests, 1 skipped, 0 failures, including IdentityRegressionGateTests, PreviewCutoverTests, and ThumbnailTests. No additional code change was needed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-26T21:34:14.172Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] scripts/ci-tests.sh serial passes with 0 failures on a clean HEAD checkout. (pass) — Ran on HEAD 90811f0. 427 tests, 1 skipped (RAW fixture opt-in), 0 failures, including IdentityRegressionGateTests, PreviewCutoverTests, and ThumbnailTests. Pre-existing uncommitted WIP (untracked RetouchModels.swift/GeometryPointMapping.swift and their tests, tracked separately as KRMA-640) was temporarily moved out of the tree to get a clean build, then restored byte-identical afterward; unrelated staged changes to AppViewModel.swift/PreviewAdmissionCoordinator.swift/DevelopInspectorTests.swift were left untouched throughout.
Checks run:
- scripts/ci-tests.sh serial (full run, 427 tests, 0 failures, 1 skipped)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUIWIJ488VZJO7L2
Summary: Confirmed fixture failures already resolved on HEAD 90811f0: scripts/ci-tests.sh serial passes 427/427 (1 skipped) including IdentityRegressionGateTests, PreviewCutoverTests, and ThumbnailTests. No code change needed for this issue.
