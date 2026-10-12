---
id: KRMA-890
title: Refresh HSL mixer golden after band rebalance
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Confirm the current HSL mixer output reflects the intended KRMA-821 behavior.
      result: pass
      notes: The kernel uses raised-cosine interpolation across the rebalance's eight band centers, with adjacent weights summing to one. ColorMixerTests confirms neighborhood response, wraparound continuity, and cyan/blue behavior.
    - criterion: Regenerate or replace only the hsl-mixer golden using the documented golden workflow.
      result: pass
      notes: Used UPDATE_METAL_GOLDENS=1 with the focused parity test. Only hsl-mixer.rgba changed among the golden assets.
    - criterion: swift test --no-parallel --filter MetalKernelParityTests.testHSLMixerMatchesGolden passes with the existing tolerance policy.
      result: pass
      notes: The focused comparison passes at the existing tolerance of 1.
    - criterion: The focused test and review notes establish why the new golden is correct.
      result: pass
      notes: The parity input now contains distinct sRGB colors spanning all eight band centers. The existing red, green, and blue adjustments are exercised without changing the tolerance policy.
  checks_run:
    - UPDATE_METAL_GOLDENS=1 swift test --no-parallel --filter MetalKernelParityTests.testHSLMixerMatchesGolden — passed; regenerated hsl-mixer.rgba.
    - swift test --no-parallel --filter MetalKernelParityTests.testHSLMixerMatchesGolden — passed (1 test).
    - swift test --no-parallel --filter ColorMixerTests — passed (10 tests).
    - scripts/build-metal-libraries.sh — passed.
    - scripts/build-metal-libraries.sh --check — passed.
    - swift test --no-parallel --filter MetalKernelParityTests — passed (16 tests).
  findings:
    - The prior HSL parity fixture repeated one cool RGB sample six times after its red/orange pair, so it did not meaningfully exercise green or all eight hue neighborhoods; the fixture is now distinct across the palette.
    - RenderPipeline and Metal source comments still described the removed 45-degree window algorithm; those comments and the required source checksum were updated.
  fixes:
    - Corrected the HSL parity input and regenerated only the hsl-mixer golden.
    - Updated HSL algorithm comments to match the current partition-of-unity behavior and rebuilt the checked-in source checksum.
  verification_commits:
    - 666a2a25be31c3ea3838703816cb8097ab28c5e9
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T01:40:53.682Z
  session: 01MV4KSVTCFCGHSKDF
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-10-11T17:43:37.006Z
updated: 2026-10-12T01:40:53.686Z
parent: KRMA-879
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T20:54:52.104Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 666a2a25be31c3ea3838703816cb8097ab28c5e9
---

## Objective
Update the HSL mixer golden fixture to match the intentional band rebalance from KRMA-821, and keep the parity test meaningful.

## Acceptance criteria
- [ ] Confirm the current HSL mixer output reflects the intended KRMA-821 behavior.
- [ ] Regenerate or replace only the `hsl-mixer` golden using the documented golden workflow.
- [ ] `swift test --no-parallel --filter MetalKernelParityTests.testHSLMixerMatchesGolden` passes with the existing tolerance policy.
- [ ] The focused test and review notes establish why the new golden is correct.

## Agent log

- 2026-10-12T01:40:53.683Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Confirm the current HSL mixer output reflects the intended KRMA-821 behavior. (pass) — The kernel uses raised-cosine interpolation across the rebalance's eight band centers, with adjacent weights summing to one. ColorMixerTests confirms neighborhood response, wraparound continuity, and cyan/blue behavior.
- [x] Regenerate or replace only the hsl-mixer golden using the documented golden workflow. (pass) — Used UPDATE_METAL_GOLDENS=1 with the focused parity test. Only hsl-mixer.rgba changed among the golden assets.
- [x] swift test --no-parallel --filter MetalKernelParityTests.testHSLMixerMatchesGolden passes with the existing tolerance policy. (pass) — The focused comparison passes at the existing tolerance of 1.
- [x] The focused test and review notes establish why the new golden is correct. (pass) — The parity input now contains distinct sRGB colors spanning all eight band centers. The existing red, green, and blue adjustments are exercised without changing the tolerance policy.
Checks run:
- UPDATE_METAL_GOLDENS=1 swift test --no-parallel --filter MetalKernelParityTests.testHSLMixerMatchesGolden — passed; regenerated hsl-mixer.rgba.
- swift test --no-parallel --filter MetalKernelParityTests.testHSLMixerMatchesGolden — passed (1 test).
- swift test --no-parallel --filter ColorMixerTests — passed (10 tests).
- scripts/build-metal-libraries.sh — passed.
- scripts/build-metal-libraries.sh --check — passed.
- swift test --no-parallel --filter MetalKernelParityTests — passed (16 tests).
Findings:
- The prior HSL parity fixture repeated one cool RGB sample six times after its red/orange pair, so it did not meaningfully exercise green or all eight hue neighborhoods; the fixture is now distinct across the palette.
- RenderPipeline and Metal source comments still described the removed 45-degree window algorithm; those comments and the required source checksum were updated.
Fixes:
- Corrected the HSL parity input and regenerated only the hsl-mixer golden.
- Updated HSL algorithm comments to match the current partition-of-unity behavior and rebuilt the checked-in source checksum.
Verification commits:
- 666a2a25be31c3ea3838703816cb8097ab28c5e9
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV4KSVTCFCGHSKDF
Summary: Verification passed: refreshed hsl-mixer golden, corrected full-band test coverage, and passed parity and mixer checks.
