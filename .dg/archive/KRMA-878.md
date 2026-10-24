---
id: KRMA-878
title: Guard AppViewModel.swift against regrowth with a line-count test
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add a line-count test that fails above a documented AppViewModel.swift ceiling and points contributors to docs/APP_ARCHITECTURE.md.
      result: pass
      notes: PackageSettingsTests enforces a 5,500-line ceiling; docs record the measured 5,398-line baseline and explain the trend-guard intent.
    - criterion: Set the ceiling from the measured size after the coordinator extractions.
      result: pass
      notes: The current AppViewModel.swift measures 5,398 lines.
  checks_run:
    - swift test --filter PackageSettingsTests/testAppViewModelDoesNotRegrow (passed; 1 test, 0 failures, exit 0)
    - git diff --check (passed, exit 0)
    - wc -l Sources/KromoraKit/ViewModels/AppViewModel.swift (5,398 lines)
  findings:
    - The initial guard counted the empty split segment after a trailing newline, so its measured count was one higher than the documented physical line count. Corrected locally.
  fixes:
    - Changed the test to count physical LF-terminated source lines accurately while preserving blank lines and handling a missing final newline.
  verification_commits:
    - b3ba954d2e173f608c693b67b5c4f7b55bf474b2
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T16:04:24.549Z
  session: 01MV40ITWOAXEXLRZO
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T13:33:44.500Z
updated: 2026-10-24T13:04:54.617Z
depends_on:
  - KRMA-874
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T16:03:20.378Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - b3ba954d2e173f608c693b67b5c4f7b55bf474b2
---

After the extraction children land, add a test (similar in spirit to XcodeProjectInvariantTests/PackageSettingsTests) that fails when AppViewModel.swift exceeds a documented ceiling (suggest ~5,000 lines at that time), with a message pointing at docs/APP_ARCHITECTURE.md. Line count is a trend guard, not the goal. Do this last; set the ceiling from the measured size after the other children.

## Agent log

- 2026-10-11T16:04:24.549Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add a line-count test that fails above a documented AppViewModel.swift ceiling and points contributors to docs/APP_ARCHITECTURE.md. (pass) — PackageSettingsTests enforces a 5,500-line ceiling; docs record the measured 5,398-line baseline and explain the trend-guard intent.
- [x] Set the ceiling from the measured size after the coordinator extractions. (pass) — The current AppViewModel.swift measures 5,398 lines.
Checks run:
- swift test --filter PackageSettingsTests/testAppViewModelDoesNotRegrow (passed; 1 test, 0 failures, exit 0)
- git diff --check (passed, exit 0)
- wc -l Sources/KromoraKit/ViewModels/AppViewModel.swift (5,398 lines)
Findings:
- The initial guard counted the empty split segment after a trailing newline, so its measured count was one higher than the documented physical line count. Corrected locally.
Fixes:
- Changed the test to count physical LF-terminated source lines accurately while preserving blank lines and handling a missing final newline.
Verification commits:
- b3ba954d2e173f608c693b67b5c4f7b55bf474b2
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV40ITWOAXEXLRZO
Summary: Verified the AppViewModel line-count guard and corrected its newline accounting.
