---
id: KRMA-337
title: Edit preview renders imported images upside down, including JPGs
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: JPG orientation metadata displays upright in Edit
      result: pass
    - criterion: RAW images retain intended orientation
      result: pass
    - criterion: Original and Adjusted surfaces share correct orientation
      result: pass
    - criterion: Export orientation remains correct
      result: pass
    - criterion: Representative JPG and existing RAW regression coverage
      result: pass
  checks_run:
    - swift build
    - "focused orientation/render tests: 21 passed"
    - "scripts/ci-tests.sh fast: 688 tests passed"
    - "scripts/ci-tests.sh serial: 327 tests passed"
    - git diff --check
    - dg validate
  findings: []
  fixes: []
  verification_commits:
    - 454fa51
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-10T14:00:52.232Z
  session: 01MTVL0MLVGWCUMWU5
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - bug
  - rendering
  - editor
created: 2026-09-10T13:12:22.027Z
updated: 2026-09-10T14:00:52.233Z
order: w
board: product
commits:
  - 454fa51
---

## Objective

Render imported images in their correct visual orientation in Edit, including JPG files. The preview must not show a source image upside down.

## Context

The upside-down rendering persists despite recent orientation work and is also reproducible with JPGs, so the problem may be in shared decode, EXIF-orientation handling, or preview presentation rather than only the RAW path.

## Steps to reproduce

1. Import or open an image with a known upright orientation; include a JPG test image as well as a RAW image where applicable.
2. Open the image in Edit.
3. Compare the Edit preview with the source/original orientation.

## Actual behavior

The Edit image can appear upside down. The report specifically notes that JPGs are affected too.

## Expected behavior

The Edit preview matches the source image's intended orientation for JPG and RAW inputs, without applying orientation metadata twice or omitting it.

## Acceptance criteria

- [ ] JPGs with orientation metadata display upright in Edit.
- [ ] RAW images continue to display in their intended orientation.
- [ ] Original and adjusted preview surfaces use the same correct orientation.
- [ ] Export orientation remains correct and is not regressed by the fix.
- [ ] Add regression coverage for representative JPG orientation metadata and an existing RAW orientation case.

## Evidence

The attached screenshot shows an incorrectly oriented Edit preview.

![Kromora Edit view showing sidebar, orientation, and Original-pane behavior](../assets/KRMA-337/screenshot-2026-09-10-at-7-10-39-am.png)

## Agent log

- 2026-09-10T14:00:52.232Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] JPG orientation metadata displays upright in Edit (pass)
- [x] RAW images retain intended orientation (pass)
- [x] Original and Adjusted surfaces share correct orientation (pass)
- [x] Export orientation remains correct (pass)
- [x] Representative JPG and existing RAW regression coverage (pass)
Checks run:
- swift build
- focused orientation/render tests: 21 passed
- scripts/ci-tests.sh fast: 688 tests passed
- scripts/ci-tests.sh serial: 327 tests passed
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- 454fa51
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTVL0MLVGWCUMWU5
Summary: Fixed Edit preview orientation handling for imported JPEGs by using the shared EXIF/TIFF orientation reader for display geometry, and added a completed-texture regression test. Existing RAW, Original/Adjusted, thumbnail, and export orientation coverage remains passing.
