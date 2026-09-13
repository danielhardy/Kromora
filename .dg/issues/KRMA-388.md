---
id: KRMA-388
title: Editor slider tracks should reach both edges with circular thumbs
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Colored slider tracks reach both ends of the bar with no unintended gap or grey cap.
      result: pass
      notes: Semantic gradient tracks are drawn against the full bar rect instead of the inset knob-travel rect; raster regression samples both bar edges.
    - criterion: Slider thumbs are circular and visually consistent across the editor controls.
      result: pass
      notes: NeutralOriginSliderCell overrides drawKnob with an adaptive oval whose fitted bounds are explicitly square and centered.
    - criterion: The appearance is correct for the Temperature, Tint, Vibrance, Saturation, and other equivalent sliders.
      result: pass
      notes: All controls share NeutralOriginSliderCell, and existing semantic track styles continue to use the shared renderer.
    - criterion: Slider hit targets and value behavior remain unchanged.
      result: pass
      notes: Native knob rect, NSSlider tracking, mapping, keyboard handling, accessibility, and editing callbacks were left unchanged; serialized UI tests passed.
    - criterion: Light and dark appearance remain legible and visually consistent.
      result: pass
      notes: Thumb fill, border, and disabled colors use adaptive AppKit colors; the full serialized render/UI lane passed.
  checks_run:
    - swift build
    - swift test --filter NeutralOriginSliderTests (13/13)
    - scripts/ci-tests.sh serial (368/368)
    - dg validate
    - git diff --check
  findings: []
  fixes: []
  verification_commits:
    - cf6ca17
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-12T18:40:50.086Z
  session: 01MTYQ43MHF6OF1Z7M
labels:
  - ui
  - sliders
created: 2026-09-12T16:42:38.336Z
updated: 2026-09-12T18:40:50.088Z
order: a0
board: product
commits:
  - cf6ca17
---

## Objective

Polish the editor slider controls so the colored track reaches the full bar width and the thumb is rendered as a circle.

## Observed behavior

The Temperature, Tint, Vibrance, Saturation, and similar sliders show a small grey gap/cap at each end of the bar. The thumb shape is not the intended circular control.

## Expected behavior

The colored slider track should extend all the way to both ends of the bar with no visible grey gap or cap, and the slider thumb should be circular.

## Acceptance criteria

- [ ] Colored slider tracks reach both ends of the bar with no unintended gap or grey cap.
- [ ] Slider thumbs are circular and visually consistent across the editor controls.
- [ ] The appearance is correct for the Temperature, Tint, Vibrance, Saturation, and other equivalent sliders.
- [ ] Slider hit targets and value behavior remain unchanged.
- [ ] Light and dark appearance remain legible and visually consistent.

## Reference

The reported screenshot shows the grey end gaps/caps and the intended circular-thumb correction.

### Comment — codex @ 2026-09-12T18:40:22.509Z

Implemented in commit cf6ca17. NeutralOriginSliderCell now paints semantic colored tracks across the complete bar, removing grey end caps, and renders the native knob geometry as an adaptive circular thumb. Native knob geometry, hit targets, value mapping, tracking, keyboard behavior, and accessibility remain unchanged. Verification: swift build passed; NeutralOriginSliderTests 13/13 passed; scripts/ci-tests.sh serial passed all 368 tests; dg validate and git diff --check passed. Existing unrelated worktree/icon changes were left untouched.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T18:40:50.086Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Colored slider tracks reach both ends of the bar with no unintended gap or grey cap. (pass) — Semantic gradient tracks are drawn against the full bar rect instead of the inset knob-travel rect; raster regression samples both bar edges.
- [x] Slider thumbs are circular and visually consistent across the editor controls. (pass) — NeutralOriginSliderCell overrides drawKnob with an adaptive oval whose fitted bounds are explicitly square and centered.
- [x] The appearance is correct for the Temperature, Tint, Vibrance, Saturation, and other equivalent sliders. (pass) — All controls share NeutralOriginSliderCell, and existing semantic track styles continue to use the shared renderer.
- [x] Slider hit targets and value behavior remain unchanged. (pass) — Native knob rect, NSSlider tracking, mapping, keyboard handling, accessibility, and editing callbacks were left unchanged; serialized UI tests passed.
- [x] Light and dark appearance remain legible and visually consistent. (pass) — Thumb fill, border, and disabled colors use adaptive AppKit colors; the full serialized render/UI lane passed.
Checks run:
- swift build
- swift test --filter NeutralOriginSliderTests (13/13)
- scripts/ci-tests.sh serial (368/368)
- dg validate
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- cf6ca17
Actor: codex
Resolved model: unknown
Pickup session: 01MTYQ43MHF6OF1Z7M
Summary: Verified: editor slider tracks now reach both bar edges and thumbs render as circles; native interaction behavior is preserved.
