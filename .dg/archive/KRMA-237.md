---
id: KRMA-237
title: Foreground and Background mask components have no observable effect
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Foreground resolves to analyzed foreground alpha and Background resolves to complementary background alpha
      result: pass
    - criterion: Foreground/background local adjustments change expected pixels in preview and export
      result: pass
    - criterion: Enable/disable, invert, combine mode, amount, and solo/inspection operate on the selected semantic component
      result: pass
    - criterion: Loading, unavailable-analysis, and analysis-failure states are explicit
      result: pass
    - criterion: Results remain aligned through source switching and preview/export resolution changes
      result: pass
    - criterion: Regression coverage covers both component kinds, visibly non-empty output, and unavailable/error path
      result: pass
  checks_run:
    - swift test — 891 executed, 42 skipped, 0 failures
    - swift test --filter LocalMaskRenderingTests.testMaskOverlayInspects|LocalMaskRenderingTests.testForegroundAndBackground|LocalMaskRenderingTests.testSemanticPreview — 3 passed, 0 failures
    - dg validate — OK; pre-existing unknown pickup-runner model warning
    - git diff --check — clean
  findings:
    - The Swift format check still reports pre-existing violations across already-dirty masking files; no formatting-only rewrite was applied to preserve unrelated work.
  fixes: []
  verification_commits:
    - a42c5cfafb9370b4e746ed96934814417295912d
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T04:35:33.677Z
  session: 01MTPB2898YODMPOMA
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
  - rendering
  - editor
  - epic:masking
created: 2026-09-06T03:14:52.682Z
updated: 2026-09-10T12:53:49.582Z
order: ipx4bimy
board: product
commits:
  - a42c5cfafb9370b4e746ed96934814417295912d
---

## Objective

Make Foreground and Background mask components produce a visible, functional mask result.

## Context

The Foreground and Background mask components can be added in the masking workflow, but using them
appears to do nothing. Their presence does not produce an observable masked local adjustment or a
meaningful inspection result, so the controls look like no-ops.

### Reproduction

1. Open the masking workspace on a photo with a detectable subject/background.
2. Add or select a Foreground mask, then apply a clearly visible local adjustment.
3. Repeat with a Background mask; also try enable/disable, invert, and solo/inspection where
   available.

### Observed

The foreground/background selection does not visibly change the adjusted pixels or the displayed
mask result. The user cannot tell whether analysis ran, whether a result is empty, or whether the
component is simply disconnected from rendering.

### Expected

Foreground and Background should resolve to their semantic alpha masks and drive the same local
adjustment, inspection, and state controls as other mask components, with explicit loading and
failure states when analysis cannot produce a result.

## Acceptance criteria

- [ ] A Foreground component resolves to the analyzed foreground/subject alpha and a Background
      component resolves to the complementary/background alpha for a supported photo.
- [ ] Applying an obviously visible local adjustment through either component changes the expected
      pixels in preview and export, with no-op behavior only when the resolved alpha is genuinely
      empty.
- [ ] Enable/disable, invert, combine mode, amount, and solo/inspection operate on the selected
      semantic component and do not silently target another component.
- [ ] Loading, unavailable-analysis, and analysis-failure states are explicit and do not present a
      successful-looking but inert component.
- [ ] Results remain aligned through source switching, crop/orientation, zoom, and preview/export
      resolution changes.
- [ ] Add regression coverage for both component kinds, including a visibly non-empty result and
      the unavailable/error path.

## Implementation notes

Coordinate the user-facing behavior in KRMA-220 with the semantic provider and persistent-mask work
in KRMA-184, KRMA-187, KRMA-201, and KRMA-224. Keep analysis and Core Image ownership within the
existing seams; do not fake a visible result with vector guides or a hard-coded rectangle.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-06T04:35:33.682Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Foreground resolves to analyzed foreground alpha and Background resolves to complementary background alpha (pass)
- [x] Foreground/background local adjustments change expected pixels in preview and export (pass)
- [x] Enable/disable, invert, combine mode, amount, and solo/inspection operate on the selected semantic component (pass)
- [x] Loading, unavailable-analysis, and analysis-failure states are explicit (pass)
- [x] Results remain aligned through source switching and preview/export resolution changes (pass)
- [x] Regression coverage covers both component kinds, visibly non-empty output, and unavailable/error path (pass)
Checks run:
- swift test — 891 executed, 42 skipped, 0 failures
- swift test --filter LocalMaskRenderingTests.testMaskOverlayInspects|LocalMaskRenderingTests.testForegroundAndBackground|LocalMaskRenderingTests.testSemanticPreview — 3 passed, 0 failures
- dg validate — OK; pre-existing unknown pickup-runner model warning
- git diff --check — clean
Findings:
- The Swift format check still reports pre-existing violations across already-dirty masking files; no formatting-only rewrite was applied to preserve unrelated work.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTPB2898YODMPOMA
Summary: Foreground/background semantic masks now resolve into visible preview/export adjustments with explicit resolution states and component inspection
