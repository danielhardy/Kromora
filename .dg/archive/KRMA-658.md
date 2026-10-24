---
id: KRMA-658
title: Build a ground-truth evaluation harness for retouch quality
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add deterministic synthetic clean backgrounds and defect compositing for soft sensor dust (5-60 px), hard specks, 1-8 px straight/sagging wires including edge crossings, and hair/fibre; cover smooth gradients with noise/grain, cloud boundaries, foliage/texture, water, brick/roof edges, and skin-like texture; keep fixture generation bounded and repeatable.
      result: pass
      notes: RetouchQualityFixtures (Tests/KromoraKitTests/Fixtures.swift) generates sky, cloud, foliage, water, brick, and skin backgrounds with per-pixel hash-based grain, and soft dust 5px/60px, hard speck, straight wire, sagging edge-crossing wire, and hair/fibre defects at 1.4-2.2 px stroke radii. Brick and cloud backgrounds combined with wire defects exercise edge crossings. testSyntheticFixtureGenerationIsRepeatable confirms determinism; fixed seed 658 is documented.
    - criterion: "Measure clean-reference error inside each defect mask and its 4 px boundary band: mean ΔE2000, gradient-continuity error, local variance/noise-spectrum ratio, and mean luminance shift; emit a readable table grouped by defect/background and by Remove, Heal, Clone, and current behavior where the mode exists."
      result: pass
      notes: RetouchQualityEvaluationTests.measure computes all four metrics over the defect mask dilated by a 4px Manhattan boundary band. testGroundTruthGateReportsCurrentHealAndRemoveFailures prints one row per background/defect/mode (Remove (no path), Heal, Clone, Current), verified by running the suite directly.
    - criterion: Define and document initial per-background pass thresholds strict enough to catch remnants, soft halos, edge breaks, and over-smoothed grain; thresholds and fixture seeds are deterministic and can be tightened as quality improves.
      result: pass
      notes: "Per-background Limits table (deltaE/gradient/variance/luminance) is defined in RetouchQualityEvaluationTests and documented in docs/RETOUCH.md with the same numbers. Deterministic seed 658 is fixed in RetouchQualityFixtures. Observed behavior: thresholds are strict enough that essentially every wire/hair/dust row fails for every mode including Clone across all backgrounds -- consistent with 'intentionally conservative' but worth a forward-looking check, filed as KRMA-666 (non-blocking, does not violate this criterion's wording)."
    - criterion: Add tests that exercise the harness against current code and demonstrate that its Heal and prospective Remove checks fail for the defects the implementation does not handle, as meaningful behavior assertions rather than permanent expected-failures.
      result: pass
      notes: testGroundTruthGateReportsCurrentHealAndRemoveFailures asserts XCTAssertGreaterThan(healFailuresByDefect[defect], 0) and XCTAssertEqual(removeFailuresByDefect[defect], backgrounds.count) per defect family -- real XCTest assertions, not disabled/expected-failure tests, and they currently pass against the present renderer.
    - criterion: Include generated synthetic fixtures in Fixtures.swift; commit any AI-generated assets only within KRMA-459 size/provenance limits; do not commit licensed RAWs.
      result: pass
      notes: All new fixtures in Fixtures.swift are procedurally generated at runtime (no new binary assets committed); no provenance manifest was needed and none was added. No RAW files touched.
    - criterion: Provide a focused invocation/report path suitable for later retouch tickets and document fixture setup, metrics, thresholds, and the opt-in RAW lane in the relevant test/docs location.
      result: pass
      notes: docs/RETOUCH.md's 'Retouch quality evaluation' section documents the swift test --filter RetouchQualityEvaluationTests invocation, the metric definitions, the threshold table, the Remove-no-path/Heal-baseline disclosures, and the opt-in KROMORA_RAW_FIXTURE_DIR lane.
  checks_run:
    - swift build (clean, 0 errors)
    - swift test --filter 'Retouch|RenderPipeline' (52 tests, 2 skipped [no local RAW fixture], 0 failures)
    - swift test --filter RetouchQualityEvaluationTests run standalone twice (before and after the fix), 0 failures both times
    - dg validate (OK; only pre-existing unrelated agent-model-name warnings)
  findings:
    - '[maintainability, fixed] testSyntheticFixtureGenerationIsRepeatable (Tests/KromoraKitTests/RetouchQualityEvaluationTests.swift:111-112) called RetouchQualityFixtures.make(background: "cloud", defect: "wire"), but "wire" is not a member of RetouchQualityFixtures.defects (the real names are "wire straight", "wire sagging edge", etc.), so the call silently fell through to the generic default case (center (48,36), radius 8, no stroke) instead of exercising a real wire fixture. The test still passed because that default path is itself deterministic, so this was a silent test-intent bug, not a functional failure. Fixed by using defect: "wire straight" in both calls; re-ran the suite and it still passes.'
    - "[maintainability, non-blocking] Across all six backgrounds, every wire-straight, wire-sagging-edge, and hair/fibre row fails the documented thresholds for every mode (Remove, Heal, Clone, Current) -- 48/48 -- and several dust/speck rows fail near-universally too (e.g. all 24 'sky' rows fail regardless of mode). This matches the ticket's explicit framing that Remove/Heal failures are expected and not a violation of this ticket's acceptance criteria, but it leaves open whether the thresholds are achievable in principle for the line-type defect family once a real content-aware Remove/Heal exists, given the fixture's offset-translated sampling against backgrounds with per-pixel grain and high spatial frequency (e.g. foliage's sin(nx*89...)). Filed as KRMA-666 (parent KRMA-658, label verification) to sanity-check achievability and adjust thresholds/fixtures if needed before later renderer tickets rely on this gate."
  fixes:
    - 'Tests/KromoraKitTests/RetouchQualityEvaluationTests.swift: corrected testSyntheticFixtureGenerationIsRepeatable to use a real defect name ("wire straight") instead of the non-existent "wire", which had silently exercised the default fixture case.'
  verification_commits:
    - 4ccc96b
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T19:16:41.197Z
  session: 01MUK71PXNINFSIFB8
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - retouch
  - remove-heal-clone
created: 2026-09-27T18:53:53.312Z
updated: 2026-09-28T14:41:33.733Z
parent: KRMA-599
blockers: []
order: kb898x0l
board: product
context:
  files:
    - Tests/KromoraKitTests/Fixtures.swift
    - Tests/KromoraKitTests/RenderPipelineTests.swift
    - Sources/KromoraKit/Models/RetouchRenderer.swift
  docs:
    - docs/RETOUCH.md
  issues:
    - KRMA-599
  commands:
    - swift test --filter 'Retouch|RenderPipeline'
    - dg validate
commits:
  - 4ccc96b
---

## Objective

Build a reproducible quality gate for small-defect retouching before changing the renderer. The
harness must expose failures in the current heal/remove behavior and give later implementation
tickets a stable way to compare results against known clean pixels.

## Context

The plan in `.context/2026-09-27-heal-remove-plan.md` sets best-in-class quality for small dust,
specks, blemishes, hair/fibre, and thin wires as the target. Visual inspection alone can hide soft
blobs, dust remnants, broken edges, or missing grain, so the work needs known-truth fixtures and
measurable regression signals. Keep fixtures generated where practical; the repository permits a
small, provenance-documented set of AI-generated JPEGs under the KRMA-459 limits, while licensed
RAW fixtures remain in the opt-in `KROMORA_RAW_FIXTURE_DIR` lane.

This is Phase 0 beneath KRMA-599 and is the prerequisite for renderer work. It should establish
per-background thresholds and record the current Heal/Clone baseline; Remove cases should make the
absence of an actual inpainting path visible rather than silently passing as a no-op.

## Acceptance criteria

- [ ] Add deterministic synthetic clean backgrounds and defect compositing for soft sensor dust
      (5–60 px), hard specks, 1–8 px straight/sagging wires including edge crossings, and
      hair/fibre. Include smooth gradients with noise/grain, cloud boundaries, foliage/texture,
      water, brick/roof edges, and skin-like texture; keep fixture generation bounded and repeatable.
- [ ] Measure clean-reference error inside each defect mask and its 4 px boundary band: mean
      ΔE2000, gradient-continuity error, local variance/noise-spectrum ratio, and mean luminance
      shift. Emit a readable table grouped by defect/background and by Remove, Heal, Clone, and
      current behavior where the mode exists.
- [ ] Define and document initial per-background pass thresholds that are strict enough to catch
      remnants, soft halos, edge breaks, and over-smoothed grain; thresholds and fixture seeds are
      deterministic and can be tightened as quality improves.
- [ ] Add tests that exercise the harness against current code and demonstrate that its Heal and
      prospective Remove checks fail for the defects the implementation does not handle. Keep
      those as meaningful behavior assertions, not permanently expected-failure tests.
- [ ] Include generated synthetic fixtures in `Fixtures.swift`; if committed AI-generated sky or
      texture images materially improve coverage, keep each at or below 500 KB, total at or below
      5 MB, and include the required provenance manifest. Do not commit licensed RAWs.
- [ ] Provide a focused invocation/report path suitable for later retouch tickets and document
      fixture setup, metrics, thresholds, and opt-in RAW lane in the relevant test/docs location.

## Implementation notes

Use only existing Apple frameworks and the existing XCTest setup; do not add dependencies. Keep
quality measurements separate from timing measurements, and ensure the report makes threshold
failures actionable. This ticket establishes the oracle; passing implementation thresholds belong
to the later renderer and Remove tickets.

### Comment — codex @ 2026-09-27T19:10:34.054Z

Implemented deterministic synthetic ground-truth retouch evaluation across sky, cloud, foliage, water, brick, and skin backgrounds; defects cover 5/60 px dust, specks, straight/sagging wires, and hair/fibre. Added ΔE2000, gradient, local variance, and luminance metrics with per-background thresholds and a readable Remove/Heal/Clone/current table. The Remove no-path and current Heal gaps are asserted as behavior baselines. Documented invocation, metrics, thresholds, and the opt-in RAW lane. Checks: swift test --filter 'Retouch|RenderPipeline' (passed; one optional RAW test skipped), swift test --filter RetouchQualityEvaluationTests (passed), dg validate (OK; existing model-name warnings). Commit: bc2aa2e.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T19:16:41.198Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add deterministic synthetic clean backgrounds and defect compositing for soft sensor dust (5-60 px), hard specks, 1-8 px straight/sagging wires including edge crossings, and hair/fibre; cover smooth gradients with noise/grain, cloud boundaries, foliage/texture, water, brick/roof edges, and skin-like texture; keep fixture generation bounded and repeatable. (pass) — RetouchQualityFixtures (Tests/KromoraKitTests/Fixtures.swift) generates sky, cloud, foliage, water, brick, and skin backgrounds with per-pixel hash-based grain, and soft dust 5px/60px, hard speck, straight wire, sagging edge-crossing wire, and hair/fibre defects at 1.4-2.2 px stroke radii. Brick and cloud backgrounds combined with wire defects exercise edge crossings. testSyntheticFixtureGenerationIsRepeatable confirms determinism; fixed seed 658 is documented.
- [x] Measure clean-reference error inside each defect mask and its 4 px boundary band: mean ΔE2000, gradient-continuity error, local variance/noise-spectrum ratio, and mean luminance shift; emit a readable table grouped by defect/background and by Remove, Heal, Clone, and current behavior where the mode exists. (pass) — RetouchQualityEvaluationTests.measure computes all four metrics over the defect mask dilated by a 4px Manhattan boundary band. testGroundTruthGateReportsCurrentHealAndRemoveFailures prints one row per background/defect/mode (Remove (no path), Heal, Clone, Current), verified by running the suite directly.
- [x] Define and document initial per-background pass thresholds strict enough to catch remnants, soft halos, edge breaks, and over-smoothed grain; thresholds and fixture seeds are deterministic and can be tightened as quality improves. (pass) — Per-background Limits table (deltaE/gradient/variance/luminance) is defined in RetouchQualityEvaluationTests and documented in docs/RETOUCH.md with the same numbers. Deterministic seed 658 is fixed in RetouchQualityFixtures. Observed behavior: thresholds are strict enough that essentially every wire/hair/dust row fails for every mode including Clone across all backgrounds -- consistent with 'intentionally conservative' but worth a forward-looking check, filed as KRMA-666 (non-blocking, does not violate this criterion's wording).
- [x] Add tests that exercise the harness against current code and demonstrate that its Heal and prospective Remove checks fail for the defects the implementation does not handle, as meaningful behavior assertions rather than permanent expected-failures. (pass) — testGroundTruthGateReportsCurrentHealAndRemoveFailures asserts XCTAssertGreaterThan(healFailuresByDefect[defect], 0) and XCTAssertEqual(removeFailuresByDefect[defect], backgrounds.count) per defect family -- real XCTest assertions, not disabled/expected-failure tests, and they currently pass against the present renderer.
- [x] Include generated synthetic fixtures in Fixtures.swift; commit any AI-generated assets only within KRMA-459 size/provenance limits; do not commit licensed RAWs. (pass) — All new fixtures in Fixtures.swift are procedurally generated at runtime (no new binary assets committed); no provenance manifest was needed and none was added. No RAW files touched.
- [x] Provide a focused invocation/report path suitable for later retouch tickets and document fixture setup, metrics, thresholds, and the opt-in RAW lane in the relevant test/docs location. (pass) — docs/RETOUCH.md's 'Retouch quality evaluation' section documents the swift test --filter RetouchQualityEvaluationTests invocation, the metric definitions, the threshold table, the Remove-no-path/Heal-baseline disclosures, and the opt-in KROMORA_RAW_FIXTURE_DIR lane.
Checks run:
- swift build (clean, 0 errors)
- swift test --filter 'Retouch|RenderPipeline' (52 tests, 2 skipped [no local RAW fixture], 0 failures)
- swift test --filter RetouchQualityEvaluationTests run standalone twice (before and after the fix), 0 failures both times
- dg validate (OK; only pre-existing unrelated agent-model-name warnings)
Findings:
- [maintainability, fixed] testSyntheticFixtureGenerationIsRepeatable (Tests/KromoraKitTests/RetouchQualityEvaluationTests.swift:111-112) called RetouchQualityFixtures.make(background: "cloud", defect: "wire"), but "wire" is not a member of RetouchQualityFixtures.defects (the real names are "wire straight", "wire sagging edge", etc.), so the call silently fell through to the generic default case (center (48,36), radius 8, no stroke) instead of exercising a real wire fixture. The test still passed because that default path is itself deterministic, so this was a silent test-intent bug, not a functional failure. Fixed by using defect: "wire straight" in both calls; re-ran the suite and it still passes.
- [maintainability, non-blocking] Across all six backgrounds, every wire-straight, wire-sagging-edge, and hair/fibre row fails the documented thresholds for every mode (Remove, Heal, Clone, Current) -- 48/48 -- and several dust/speck rows fail near-universally too (e.g. all 24 'sky' rows fail regardless of mode). This matches the ticket's explicit framing that Remove/Heal failures are expected and not a violation of this ticket's acceptance criteria, but it leaves open whether the thresholds are achievable in principle for the line-type defect family once a real content-aware Remove/Heal exists, given the fixture's offset-translated sampling against backgrounds with per-pixel grain and high spatial frequency (e.g. foliage's sin(nx*89...)). Filed as KRMA-666 (parent KRMA-658, label verification) to sanity-check achievability and adjust thresholds/fixtures if needed before later renderer tickets rely on this gate.
Fixes:
- Tests/KromoraKitTests/RetouchQualityEvaluationTests.swift: corrected testSyntheticFixtureGenerationIsRepeatable to use a real defect name ("wire straight") instead of the non-existent "wire", which had silently exercised the default fixture case.
Verification commits:
- 4ccc96b
Actor: claude
Resolved model: sonnet
Pickup session: 01MUK71PXNINFSIFB8
