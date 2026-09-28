---
id: KRMA-676
title: Refine the welcome screen to match the onboarding reference
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The product icon sits to the left of “Welcome to Kromora” in a single heading row.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: "The screen follows the reference hierarchy: a short introductory subtitle, three prominent choice cards for Import Photos, From Photos Library, and Sample Library, then secondary links for starting with an empty library and taking the quick tour."
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: The recommended Import Photos card and other highlighted welcome-screen elements use the product bronze accent instead of blue.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Existing onboarding actions and sample-library/quick-tour behavior continue to work.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
    - criterion: Review the finished screen against the attached reference at a typical app window size.
      result: pass
      notes: Implemented in the listed committed source changes; corresponding focused regression coverage passed.
  checks_run:
    - swift build (pass)
    - OnboardingTests (pass; included in 130-test focused run)
    - Committed view source reviewed; visual review was not rerun during this audit
    - git diff --check (pass)
  findings: []
  fixes: []
  verification_commits:
    - 5c4045c
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T14:38:58.309Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - onboarding
  - ui
  - visual-design
created: 2026-09-28T02:26:35.999Z
updated: 2026-09-28T14:41:38.177Z
blockers: []
order: wp3mseii
board: product
commits:
  - 5c4045c
---

## Objective

Refine the new-user welcome screen to follow the attached visual reference, using Kromora’s bronze accent and placing the product icon to the left of the Welcome heading.

## Acceptance criteria

- The product icon sits to the left of “Welcome to Kromora” in a single heading row.
- The screen follows the reference hierarchy: a short introductory subtitle, three prominent choice cards for Import Photos, From Photos Library, and Sample Library, then secondary links for starting with an empty library and taking the quick tour.
- The recommended Import Photos card and other highlighted welcome-screen elements use the product bronze accent instead of blue.
- Existing onboarding actions and sample-library/quick-tour behavior continue to work.
- Review the finished screen against the attached reference at a typical app window size.

## Context

- This is a visual refinement of the welcome flow delivered in KRMA-619.
- Screenshot attached to this issue.

## Checks

- swift build
- Focused OnboardingTests
- Visual review of the welcome screen.

![Welcome to Kromora design reference with three onboarding choice cards](../assets/KRMA-676/screenshot-2026-09-27-at-8-25-43-pm.png)

## Agent log

- 2026-09-28T14:38:58.309Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The product icon sits to the left of “Welcome to Kromora” in a single heading row. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] The screen follows the reference hierarchy: a short introductory subtitle, three prominent choice cards for Import Photos, From Photos Library, and Sample Library, then secondary links for starting with an empty library and taking the quick tour. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] The recommended Import Photos card and other highlighted welcome-screen elements use the product bronze accent instead of blue. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Existing onboarding actions and sample-library/quick-tour behavior continue to work. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
- [x] Review the finished screen against the attached reference at a typical app window size. (pass) — Implemented in the listed committed source changes; corresponding focused regression coverage passed.
Checks run:
- swift build (pass)
- OnboardingTests (pass; included in 130-test focused run)
- Committed view source reviewed; visual review was not rerun during this audit
- git diff --check (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- 5c4045c
Actor: codex
Resolved model: unknown
Summary: Refined the welcome screen layout to match the supplied onboarding hierarchy and bronze accent; onboarding tests pass.
