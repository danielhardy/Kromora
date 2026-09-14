---
id: KRMA-425
title: Stabilize semantic-mask source switching and temporary edit storage
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Switching to the second source publishes the new source deterministically before semantic-mask actions proceed.
      result: pass
      notes: The regression waits for source name, image publication, changed source fingerprint, and incremented source revision before applying the second-source semantic mask.
    - criterion: The test uses isolated, valid temporary storage and cleans it up only after all asynchronous work has drained.
      result: pass
      notes: The relaunch path shares the repository's per-test in-memory SwiftData container; fixture files remain under TempDirectoryTestCase cleanup after AppViewModel.shutdown.
    - criterion: Temporary store failures are surfaced as actionable test diagnostics rather than cascading source-load timeouts.
      result: pass
      notes: Source-switch timeout diagnostics include source name, revision, source/image presence, edit-store status, and status message.
    - criterion: The semantic mask is created/reused for the correct source and never leaks state from the prior source.
      result: pass
      notes: The test verifies the first mask is persisted, the second source starts empty, a second-source mask can be created, and the first source restores its own mask.
    - criterion: Focused masking/source-switch tests pass repeatedly and the full serial/fast lanes remain green.
      result: pass
      notes: Focused regression passed 10/10; lifecycle neighbors passed 116/116 with 1 intentional skip; serial 375/375; fast 1000/1000.
  checks_run:
    - "Focused regression x10: 10/10 passed"
    - "Masking/source lifecycle neighbors: 116 passed, 1 intentional skip"
    - "scripts/ci-tests.sh serial: 375 passed"
    - "scripts/ci-tests.sh fast: 1000 passed"
    - swift build
    - swift build -c release
    - "swift test --no-parallel --filter MaskingWorkspaceTests: 36 passed"
    - git diff --check
    - "dg validate --json: passed"
  findings: []
  fixes: []
  verification_commits:
    - d5e58e6
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-13T17:36:32.532Z
  session: 01MU037GVAIIE7UCFJ
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - testing
  - async
  - masking
created: 2026-09-13T15:50:12.382Z
updated: 2026-09-13T17:36:32.534Z
order: a0
board: product
branch: main
commits:
  - d5e58e6
---

## Objective

Make semantic-mask workspace source switching deterministic and eliminate the failure mode where a temporary edit store cannot be opened.

## Evidence

The full serial run on 2026-09-13 failed:
- MaskingWorkspaceTests/testInfoAnalysisMaskCreatesAndReusesTheDemonstratedSemanticMask
- It timed out waiting for the second source to load and then failed an assertion.
- The same log contains CoreData/SQLite I/O errors for a temporary edits.json database, including disk I/O and unable-to-open-database errors.

## Acceptance criteria

- Switching to the second source publishes the new source deterministically before semantic-mask actions proceed.
- The test uses isolated, valid temporary storage and cleans it up only after all asynchronous work has drained.
- Temporary store failures are surfaced as actionable test diagnostics rather than cascading source-load timeouts.
- The semantic mask is created/reused for the correct source and never leaks state from the prior source.
- Focused masking/source-switch tests pass repeatedly and the full serial/fast lanes remain green.

## Verification

Run the named test repeatedly, the complete MaskingWorkspace and source lifecycle suites, and the full serial and fast CI lanes. Separate genuine lifecycle failures from host-level temporary-storage errors.

## Agent log

- 2026-09-13T17:36:32.532Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Switching to the second source publishes the new source deterministically before semantic-mask actions proceed. (pass) — The regression waits for source name, image publication, changed source fingerprint, and incremented source revision before applying the second-source semantic mask.
- [x] The test uses isolated, valid temporary storage and cleans it up only after all asynchronous work has drained. (pass) — The relaunch path shares the repository's per-test in-memory SwiftData container; fixture files remain under TempDirectoryTestCase cleanup after AppViewModel.shutdown.
- [x] Temporary store failures are surfaced as actionable test diagnostics rather than cascading source-load timeouts. (pass) — Source-switch timeout diagnostics include source name, revision, source/image presence, edit-store status, and status message.
- [x] The semantic mask is created/reused for the correct source and never leaks state from the prior source. (pass) — The test verifies the first mask is persisted, the second source starts empty, a second-source mask can be created, and the first source restores its own mask.
- [x] Focused masking/source-switch tests pass repeatedly and the full serial/fast lanes remain green. (pass) — Focused regression passed 10/10; lifecycle neighbors passed 116/116 with 1 intentional skip; serial 375/375; fast 1000/1000.
Checks run:
- Focused regression x10: 10/10 passed
- Masking/source lifecycle neighbors: 116 passed, 1 intentional skip
- scripts/ci-tests.sh serial: 375 passed
- scripts/ci-tests.sh fast: 1000 passed
- swift build
- swift build -c release
- swift test --no-parallel --filter MaskingWorkspaceTests: 36 passed
- git diff --check
- dg validate --json: passed
Findings:
- None
Fixes:
- None
Verification commits:
- d5e58e6
Actor: codex
Resolved model: unknown
Pickup session: 01MU037GVAIIE7UCFJ
Summary: Stabilized semantic-mask source switching and isolated edit-store test lifecycle.
