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
updated: 2026-10-24T14:25:58.055Z
depends_on:
  - KRMA-056
  - KRMA-1016
  - KRMA-1066
blockers: []
estimate: 5
order: 4p1kcis6
board: product
context:
  files:
    - .context/2026-10-19-release-readiness-review.md
  docs:
    - docs/PRODUCT_SCOPE.md
    - docs/APP_STORE_ACCEPTANCE.md
  issues:
    - KRMA-1051
    - KRMA-1016
    - KRMA-1066
  commands: []
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

### Comment — codex @ 2026-10-04T23:20:54.695Z

Acceptance note for KRMA-059: run the end-to-end acceptance pass against the signed, sandboxed Xcode Release build, not `swift run`. Follow [docs/APP_STORE_ACCEPTANCE.md](../../docs/APP_STORE_ACCEPTANCE.md) for commands, manual cases, expected results, and the results template.

### Comment — cursor @ 2026-10-14T16:11:01.463Z

The 2026-10-14 signed-app qualification checklist is KRMA-1016 under epic KRMA-994. This MVP gate stays the broader release ticket. Do not file a second end-to-end acceptance issue for the same pass.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## 2026-10-19 review follow-up

The current review follow-up tracker is KRMA-1051. Continue using KRMA-1016 as the single signed-app qualification owner and consume its current candidate evidence, plus the subsequent TestFlight pilot KRMA-1066. Do not create another duplicate end-to-end acceptance ticket or treat an earlier ad hoc build as a release-qualified pass. Completed October 14 product fixes remain completed; the new recovery and verification defects are separate child tasks. Current product scope is docs/PRODUCT_SCOPE.md; historical exclusions/concepts above do not override it.
