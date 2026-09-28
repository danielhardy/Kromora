---
id: KRMA-676
title: Refine the welcome screen to match the onboarding reference
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - onboarding
  - ui
  - visual-design
created: 2026-09-28T02:26:35.999Z
updated: 2026-09-28T02:26:57.606Z
order: zx
board: product
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
