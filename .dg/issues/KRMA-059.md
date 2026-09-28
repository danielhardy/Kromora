---
id: KRMA-059
title: Run fault-recovery and end-to-end MVP release acceptance
type: task
status: backlog
priority: urgent
labels:
  - mvp
  - epic:quality
  - phase:10
created: 2026-08-30T18:30:37.650Z
updated: 2026-09-26T13:56:42.254Z
depends_on:
  - KRMA-058
  - KRMA-056
blockers: []
estimate: 5
order: 4aaaaaa6
board: product
---

## Objective

Verify the core MVP workflow and a focused set of data-safety failures before release.

## Context

Part of **Epic 10 — Image quality, performance, and MVP release gate**. The source product brief is `.context/initial_concept.md`. Work from the existing LUTzy-derived implementation; preserve working behavior and inspect only the smallest relevant file set before changing code.

## Scope

- On a clean profile, import representative photos, cull, edit, compare, relaunch, and export.
- Exercise the highest-risk package/edit persistence and export failures that can affect user data; confirm originals remain unchanged and failures are understandable.
- Confirm unsupported inputs are rejected clearly and cancellation does not leave partial or misleading state.
- Record known release limitations and open only actionable critical blockers.

## Acceptance criteria

- [ ] The documented import→cull→edit→compare→export path passes on a clean profile and after relaunch.
- [ ] Focused data-safety failures preserve existing originals/edits or produce clear, non-destructive errors.
- [ ] Required project CI/build checks for release are green.
- [ ] Known limitations are recorded and no unresolved critical release blocker remains.

## Verification

- Run clean-profile manual acceptance and the release-required build/CI checks; add focused checks for selected failure modes.

## Out of scope

- AI masks, healing, HDR/panorama merge, cloud sync, tethering, mobile, plugins, or catalog import.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
