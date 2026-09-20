---
id: KRMA-474
title: Backlight detection returns 0 on real photos; Auto darkens a backlit subject
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Root cause identified and recorded
      result: pass
      notes: Coordinator background-stage routing and exact weighted-histogram validation were identified and documented in the issue comment.
    - criterion: ai-clear-backlit-portrait backlightingLikelihood > 0.30; Auto does not lower exposure; shadows lift
      result: pass
      notes: Report measured backlighting=0.437, exposure=0.000 EV, shadows=18.581.
    - criterion: No regression on daylight and intentional-key fixtures
      result: pass
      notes: Real-corpus assertions and focused scene/Auto tests passed.
    - criterion: AUTO_EXPOSURE_POLICY.md updated
      result: pass
    - criterion: Companion expected-failure assertion unwrapped
      result: pass
      notes: KRMA-475 XCTExpectFailure wrapper removed; real-corpus test passes normally.
    - criterion: scripts/ci-tests.sh fast and serial pass
      result: pass
      notes: "Fast: 1092 tests, 0 failures. Serial: 390 tests, 1 existing skip, 0 failures."
  checks_run:
    - scripts/photo-intelligence-report.sh
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - swift test --filter 'SceneCharacteristicsAnalyzerTests|AutoLightEngineTests|GlobalToneAnalyzerTests|PhotoIntelligenceDecisionLogicTests|PhotoIntelligenceRealCorpusTests'
    - git diff --check
    - dg validate
  findings:
    - Build/test output contains only pre-existing unrelated CIKernel deprecation warnings and existing dg unknown-model warnings.
  fixes:
    - Coordinator background composition with provider fallback; floating-point tolerance for weighted histograms; semantic matte preference for backlight inference; strong-backlight exposure guard; tests and policy documentation.
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-20T14:49:28.086Z
  session: 01MU9WY3572LTEPYFO
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - auto
  - photo-analysis
  - correctness
created: 2026-09-20T12:06:38.123Z
updated: 2026-09-20T14:49:28.087Z
depends_on:
  - KRMA-475
order: a0
board: product
---

## Objective

Find out why the backlighting likelihood is 0.000 on every real fixture, and fix Auto so a clearly backlit subject is brightened, not darkened.

## Evidence

Found by the real-pixel corpus from KRMA-459 (`Tests/KromoraKitTests/PhotoIntelligenceRealCorpusTests.swift`, fixtures in `Tests/KromoraKitTests/Resources/PhotoIntelligence/`). Regenerate with `scripts/photo-intelligence-report.sh`. Values below are read from the generated report on 2026-09-20; I did not view the rendered before/after images.

| Fixture | backlighting | Auto exposure | Auto shadows | Notes |
|---|---|---|---|---|
| `ai-clear-backlit-portrait` | **0.000** | **−0.772 EV** | +9.8 | Vision detects faces and people; tonalKey=high, p50 0.816, p05 0.118 |
| `ai-golden-hour-landscape` | 0.000 | +0.166 | +7.2 | Sun in frame, dark foreground |
| every other fixture | 0.000 | — | — | Includes all procedural fixtures |

Backlighting is 0.000 on **every** card in the report, so the detector appears not to fire on real photographs at all (or it depends on inputs the real pipeline does not supply). The backlit portrait is the clearest failure: the subject is the dark region against a bright sky, yet Auto lowers exposure by 0.77 EV.

The KRMA-459 ticket required `backlightingLikelihood > 0.30` and `hasFaces`/`hasPeople` for this image. The real-corpus test only asserts faces and people (`assertSemanticExpectations`, case `ai-clear-backlit-portrait`), so it passes over this defect.

## Investigation questions

1. What inputs does `SceneCharacteristicsAnalyzer` use for `backlightingLikelihood` (subject vs background masked means, coverage, confidence)? Log them for `ai-clear-backlit-portrait`.
2. Does the real Vision subject/background mask reach the analyzer with usable coverage and confidence? KRMA-459 changed `MaskedToneAnalyzer` to resample mismatched Vision masks; confirm the resampled mask produces sensible regional means.
3. Are the thresholds tuned to the earlier hand-typed fixture values (subject mean 0.22, background 0.90) rather than to real photographs?
4. Why is `tonalKey` reported as `high` for a scene that is backlit rather than uniformly bright, and does that push exposure down?

## Acceptance criteria

- [ ] Root cause identified and written into this ticket.
- [ ] On `ai-clear-backlit-portrait`, `backlightingLikelihood` exceeds 0.30 and Auto does not lower exposure; shadows are lifted meaningfully.
- [ ] No regression on the other fixtures, including `ai-normal-daylight-street` (`backlightingLikelihood` below 0.35) and the two portraits with intentional key.
- [ ] `AUTO_EXPOSURE_POLICY.md` updated if thresholds or behaviour change.
- [ ] Companion ticket (test assertion) is un-expected-failed in the same change.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass.

## Out of scope

- Confidence values being 1.000 on every card (separate ticket if wanted).
- Face detection missing on the high-key and low-key portraits; verify by viewing those images first.

## Verification

Run `scripts/photo-intelligence-report.sh`, compare the backlit portrait card before and after, and view the rendered result: the subject should be visibly lifted.


### Comment — codex @ 2026-09-20T14:49:11.859Z

Implemented and verified. Root cause: PhotoAnalysisCoordinator sent the .background analysis stage directly to VisionSemanticMaskProvider, which intentionally rejects .background because the coordinator owns foreground-complement composition; this omitted the background region and left subject/background delta nil. After routing through coordinator composition (with a native-provider fallback), resampled fractional masks reached MaskedToneAnalyzer, but GlobalToneAnalyzer rejected valid weighted histograms due exact channel-total equality; a scale-aware 1e-6 tolerance fixes that. Scene backlight inference now prefers person/face mattes over broad saliency boxes, and Auto exposure stays neutral/positive at likelihood >= 0.30 while shadows provide the subject lift. Real report: ai-clear-backlit-portrait backlighting=0.437, exposure=0.000 EV, shadows=18.581; normal daylight remains below the backlight threshold. Removed KRMA-475 XCTExpectFailure wrappers. Verification: scripts/photo-intelligence-report.sh passed; scripts/ci-tests.sh fast passed (1092 tests); scripts/ci-tests.sh serial passed (390 tests, 1 pre-existing skip); git diff --check passed; dg validate passed with existing unknown-model warnings.

## Agent log

- 2026-09-20T14:49:28.086Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Root cause identified and recorded (pass) — Coordinator background-stage routing and exact weighted-histogram validation were identified and documented in the issue comment.
- [x] ai-clear-backlit-portrait backlightingLikelihood > 0.30; Auto does not lower exposure; shadows lift (pass) — Report measured backlighting=0.437, exposure=0.000 EV, shadows=18.581.
- [x] No regression on daylight and intentional-key fixtures (pass) — Real-corpus assertions and focused scene/Auto tests passed.
- [x] AUTO_EXPOSURE_POLICY.md updated (pass)
- [x] Companion expected-failure assertion unwrapped (pass) — KRMA-475 XCTExpectFailure wrapper removed; real-corpus test passes normally.
- [x] scripts/ci-tests.sh fast and serial pass (pass) — Fast: 1092 tests, 0 failures. Serial: 390 tests, 1 existing skip, 0 failures.
Checks run:
- scripts/photo-intelligence-report.sh
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- swift test --filter 'SceneCharacteristicsAnalyzerTests|AutoLightEngineTests|GlobalToneAnalyzerTests|PhotoIntelligenceDecisionLogicTests|PhotoIntelligenceRealCorpusTests'
- git diff --check
- dg validate
Findings:
- Build/test output contains only pre-existing unrelated CIKernel deprecation warnings and existing dg unknown-model warnings.
Fixes:
- Coordinator background composition with provider fallback; floating-point tolerance for weighted histograms; semantic matte preference for backlight inference; strong-backlight exposure guard; tests and policy documentation.
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU9WY3572LTEPYFO
Summary: Fixed real-photo backlight detection and Auto darkening; verified the real corpus and required CI lanes.
