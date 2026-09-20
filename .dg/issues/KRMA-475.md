---
id: KRMA-475
title: Assert backlit-portrait expectations in real corpus test (expected failure)
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The two assertions exist for ai-clear-backlit-portrait and reference the backlight-detection ticket ID in the XCTExpectFailure message.
      result: pass
      notes: 'PhotoIntelligenceRealCorpusTests.swift:230-234: backlightingLikelihood > 0.30 and AutoLightEngine exposure >= 0 assertions wrapped in XCTExpectFailure("KRMA-474: backlight detection is 0.000 on real photos").'
    - criterion: swift test --filter PhotoIntelligenceRealCorpusTests passes with the expected failures recorded.
      result: pass
      notes: 2 tests, 0 failures, 2 expected failures each (backlighting 0.0 vs 0.3; exposure -0.7719 vs 0).
    - criterion: scripts/ci-tests.sh serial passes.
      result: pass
      notes: 390 tests, 1 pre-existing RAW-fixture skip, 0 failures.
    - criterion: The fix ticket (KRMA-474) depends on this one and removes the XCTExpectFailure wrappers when it lands.
      result: pass
      notes: "KRMA-474.md has depends_on: [KRMA-475] and lists un-expected-failing the companion assertion as an acceptance criterion."
  checks_run:
    - swift test --filter PhotoIntelligenceRealCorpusTests
    - scripts/ci-tests.sh serial
    - git status --porcelain (confirmed no unexpected tracked-source changes from verification)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-20T14:04:53.429Z
  session: 01MU9VYZIB13OVPPMP
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - testing
  - auto
  - photo-analysis
created: 2026-09-20T12:06:39.636Z
updated: 2026-09-20T14:04:53.431Z
order: a0
board: product
---

## Objective

Make the real-pixel corpus test fail (as an expected failure) for the known backlit-portrait defect, so it cannot be forgotten and cannot silently regress.

## Context

KRMA-459 specified that `ai-clear-backlit-portrait` must show `backlightingLikelihood > 0.30`, `hasFaces`, and `hasPeople`. The committed test (`Tests/KromoraKitTests/PhotoIntelligenceRealCorpusTests.swift`, `assertSemanticExpectations`, case `ai-clear-backlit-portrait`) asserts only the last two. The measured backlighting for that image is 0.000, so the original assertion would fail; it was left out and the ticket was verified as PASS anyway.

## Work

- Add `XCTAssertGreaterThan(analysis.scene.backlightingLikelihood, 0.30, fixture.name)` for `ai-clear-backlit-portrait`.
- Wrap it in `XCTExpectFailure("KRMA-474: backlight detection is 0.000 on real photos")` so CI stays green while the defect is open.
- Use non-strict-off behaviour: when the underlying fix lands and the assertion starts passing, XCTest reports the expected failure as an unexpected pass, which forces someone to remove the wrapper.
- Also assert the intended Auto direction with the same wrapper: `exposure >= 0` on this image (Auto currently returns −0.772).

## Acceptance criteria

- [ ] The two assertions exist for `ai-clear-backlit-portrait` and reference the backlight-detection ticket ID in the `XCTExpectFailure` message.
- [ ] `swift test --filter PhotoIntelligenceRealCorpusTests` passes with the expected failures recorded.
- [ ] `scripts/ci-tests.sh serial` passes.
- [ ] The fix ticket (KRMA-474) depends on this one and removes the `XCTExpectFailure` wrappers when it lands.


### Comment — codex @ 2026-09-20T14:02:45.784Z

Implemented in 83a88ea. Added the ai-clear-backlit-portrait backlightingLikelihood > 0.30 assertion and non-negative Auto exposure assertion under XCTExpectFailure("KRMA-474: backlight detection is 0.000 on real photos"). Verification: swift test --filter PhotoIntelligenceRealCorpusTests passed (2 tests, 0 failures, 2 expected failures); scripts/ci-tests.sh serial passed (390 tests, 1 pre-existing RAW skip, 0 failures); dg validate passed with existing unknown-model warnings; git diff --check passed.

## Agent log

- 2026-09-20T14:04:53.429Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The two assertions exist for ai-clear-backlit-portrait and reference the backlight-detection ticket ID in the XCTExpectFailure message. (pass) — PhotoIntelligenceRealCorpusTests.swift:230-234: backlightingLikelihood > 0.30 and AutoLightEngine exposure >= 0 assertions wrapped in XCTExpectFailure("KRMA-474: backlight detection is 0.000 on real photos").
- [x] swift test --filter PhotoIntelligenceRealCorpusTests passes with the expected failures recorded. (pass) — 2 tests, 0 failures, 2 expected failures each (backlighting 0.0 vs 0.3; exposure -0.7719 vs 0).
- [x] scripts/ci-tests.sh serial passes. (pass) — 390 tests, 1 pre-existing RAW-fixture skip, 0 failures.
- [x] The fix ticket (KRMA-474) depends on this one and removes the XCTExpectFailure wrappers when it lands. (pass) — KRMA-474.md has depends_on: [KRMA-475] and lists un-expected-failing the companion assertion as an acceptance criterion.
Checks run:
- swift test --filter PhotoIntelligenceRealCorpusTests
- scripts/ci-tests.sh serial
- git status --porcelain (confirmed no unexpected tracked-source changes from verification)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU9VYZIB13OVPPMP
