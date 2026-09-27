---
id: KRMA-640
title: Untracked WIP files break full swift test build (RetouchModels/GeometryPointMapping)
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: swift build and swift test (or at least RetouchModelTests.swift and GeometryPointMappingTests.swift specifically) compile with the WIP files present.
      result: pass
      notes: swift build succeeds; targeted swift test --filter for both suites passes (6/6 tests).
    - criterion: scripts/ci-tests.sh fast and scripts/ci-tests.sh serial pass with the files present.
      result: pass
      notes: "fast lane: 1253 tests, exit 0. serial lane: 427 tests, 1 skip (pre-existing, matches prior implementer report), 0 failures, exit 0."
    - criterion: No test or source file needs to be removed to get a clean build.
      result: pass
      notes: All four WIP files remain in place and are now committed at 08dae5c; no removals were needed.
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - swift test --filter GeometryPointMappingTests|RetouchModelTests
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T03:30:50.529Z
  session: 01MUJ96PH4FAE0R6AR
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-26T21:08:45.558Z
updated: 2026-09-27T03:30:50.531Z
parent: KRMA-636
blockers: []
order: a0
board: product
---

## Objective

Get the working tree's untracked WIP back to a state where `swift build`/`swift test` succeed
for everyone, without losing the in-progress retouch/geometry work.

## Context

Found during KRMA-636 verification (2026-09-26). Four untracked files already in the working
tree at that time do not compile together:

- `Sources/KromoraKit/Models/GeometryPointMapping.swift`
- `Sources/KromoraKit/Models/RetouchModels.swift`
- `Tests/KromoraKitTests/GeometryPointMappingTests.swift`
- `Tests/KromoraKitTests/RetouchModelTests.swift`

`Tests/KromoraKitTests/RetouchModelTests.swift` references API that `RetouchModels.swift` does
not yet provide: `Equatable.neutral` (used as `.neutral` for a `RetouchSettings`/retouch value),
an `EditDocument(retouch:)` initializer overload, and a `document.retouch` settable property.
Because the test target compiles as one module, this alone fails `swift build`/`swift test` for
the *entire* `KromoraKitTests` target — not just those two files' tests — blocking anyone running
a plain `swift test` while this WIP sits in the tree.

This is a plain in-progress-work gap, not a regression from any merged commit: these files are
untracked and were never committed. Verification of KRMA-636 worked around it by temporarily
moving the four files out of the tree, running the required checks, then moving them back
unchanged; this ticket is to actually finish or fix that WIP (or stash/branch it) so `swift test`
works again without the workaround.

## Acceptance criteria

- [ ] `swift build` and `swift test` (or at least `Tests/KromoraKitTests/RetouchModelTests.swift`
      and `GeometryPointMappingTests.swift` specifically) compile with the WIP files present.
- [ ] `scripts/ci-tests.sh fast` and `scripts/ci-tests.sh serial` pass with the files present.
- [ ] No test or source file needs to be removed to get a clean build.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-27T03:22:39.608Z

Completed the WIP model integration: EditDocument now persists retouch settings as schema v7, defaults legacy documents to neutral retouch, and includes retouch in identity and comparison behavior. Kept all four WIP files and added the missing document API. Verified with swift build, scripts/ci-tests.sh fast, scripts/ci-tests.sh serial, and focused GeometryPointMappingTests/RetouchModelTests (all passed; serial lane had one skip). Commit: 08dae5c.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T03:30:50.529Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] swift build and swift test (or at least RetouchModelTests.swift and GeometryPointMappingTests.swift specifically) compile with the WIP files present. (pass) — swift build succeeds; targeted swift test --filter for both suites passes (6/6 tests).
- [x] scripts/ci-tests.sh fast and scripts/ci-tests.sh serial pass with the files present. (pass) — fast lane: 1253 tests, exit 0. serial lane: 427 tests, 1 skip (pre-existing, matches prior implementer report), 0 failures, exit 0.
- [x] No test or source file needs to be removed to get a clean build. (pass) — All four WIP files remain in place and are now committed at 08dae5c; no removals were needed.
Checks run:
- swift build
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- swift test --filter GeometryPointMappingTests|RetouchModelTests
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJ96PH4FAE0R6AR
Summary: Verified retouch/geometry WIP integration (commit 08dae5c): swift build, ci-tests.sh fast, ci-tests.sh serial, and the two targeted test suites all pass with no source removal needed. No correctness/maintainability/security/performance issues found.
