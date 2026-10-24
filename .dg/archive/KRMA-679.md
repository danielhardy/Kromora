---
id: KRMA-679
title: Clarify the Color inspector hierarchy and white-balance controls
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Keep one clear Color inspector title and make it visually distinct from subsection/accordion headings.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Remove or rename the nested “Color” heading so it does not repeat the parent inspector title.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Remove the “RAW decoder” label beside the Preset picker.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Place a compact eyedropper button on the same row as the Preset picker; the icon-only button retains an accessible label or help text identifying Sample Neutral.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Keep White Balance, Color adjustments, Color Mixer / HSL, and Color Grading controls understandable and usable.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Review the revised hierarchy and white-balance row against the attached screenshot at a typical inspector width.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
  checks_run:
    - swift build (pass)
    - ColorInspectorTests (pass; included in 130-test focused run)
    - Committed view source reviewed; visual review was not rerun during this audit
    - git diff --check (pass)
  findings: []
  fixes: []
  verification_commits:
    - da8750c
    - 5b7e2ff
    - 1dfc910
    - 6ff9f57
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:39:00.881Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - inspector
  - color
  - ui
created: 2026-09-28T02:33:53.268Z
updated: 2026-09-28T14:41:38.361Z
blockers: []
order: x6xorqqf
board: product
commits:
  - 6ff9f57
  - da8750c
  - 5b7e2ff
  - 1dfc910
---

## Objective

Make the Color inspector easier to scan by reducing repeated labels, simplifying the white-balance controls, and clarifying the hierarchy between the inspector title and its subsections.

## User report

The word “Color” is overused, the “RAW decoder” label is unnecessary beside the Preset control, and the Sample Neutral action should be a compact eyedropper beside the preset. The inspector title and subsection headings also need a clearer visual hierarchy. See the attached screenshot.

## Acceptance criteria

- Keep one clear Color inspector title and make it visually distinct from subsection/accordion headings.
- Remove or rename the nested “Color” heading so it does not repeat the parent inspector title.
- Remove the “RAW decoder” label beside the Preset picker.
- Place a compact eyedropper button on the same row as the Preset picker; the icon-only button retains an accessible label or help text identifying Sample Neutral.
- Keep White Balance, Color adjustments, Color Mixer / HSL, and Color Grading controls understandable and usable.
- Review the revised hierarchy and white-balance row against the attached screenshot.

## Context

- Screenshot attached to this issue.

## Checks

- swift build
- Focused Color inspector tests
- Visual review at a typical inspector width.

![Color inspector with repeated Color headings and separate Sample Neutral button](../assets/KRMA-679/screenshot-2026-09-27-at-8-31-36-pm.png)

## Agent log

- 2026-09-28T14:39:00.881Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Keep one clear Color inspector title and make it visually distinct from subsection/accordion headings. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Remove or rename the nested “Color” heading so it does not repeat the parent inspector title. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Remove the “RAW decoder” label beside the Preset picker. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Place a compact eyedropper button on the same row as the Preset picker; the icon-only button retains an accessible label or help text identifying Sample Neutral. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Keep White Balance, Color adjustments, Color Mixer / HSL, and Color Grading controls understandable and usable. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Review the revised hierarchy and white-balance row against the attached screenshot at a typical inspector width. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
Checks run:
- swift build (pass)
- ColorInspectorTests (pass; included in 130-test focused run)
- Committed view source reviewed; visual review was not rerun during this audit
- git diff --check (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- da8750c
- 5b7e2ff
- 1dfc910
- 6ff9f57
Actor: codex
Resolved model: unknown
Summary: Clarified the Color inspector hierarchy and white-balance row, using the shared panel-title styling; Color inspector tests pass.
