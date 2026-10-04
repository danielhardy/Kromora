---
id: KRMA-813
title: "Epic: Ship Kromora through the Mac App Store"
type: feature
status: backlog
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - epic
  - appstore
created: 2026-10-03T19:25:34.385Z
updated: 2026-10-03T19:25:37.386Z
depends_on:
  - KRMA-808
  - KRMA-809
  - KRMA-810
  - KRMA-811
  - KRMA-812
blockers: []
order: zzzzzzzh
board: product
---

## Current disposition

**Tracking parent** for the whole Mac App Store release plan (`.context/2026-09-30-app-store-release-plan.md`). Keep in `backlog`; do not claim.

## Objective

One codebase, one binary distribution channel (Mac App Store, plus TestFlight), two tiny launchers. SwiftPM stays the development build system; the Xcode project only packages KromoraKit.

## Outcome

- [ ] `swift build`, `swift test`, `swift run Kromora`, and `scripts/ci-tests.sh` work unchanged.
- [ ] Xcode builds and archives the sandboxed production app; it passes `scripts/verify-xcode-app.sh`.
- [ ] Direct-distribution and updater infrastructure is gone.
- [ ] The sandboxed acceptance checklist has been run by a person (KRMA-059) and the build validates and uploads to App Store Connect/TestFlight (human steps in `docs/APP_STORE_SUBMISSION.md`).

## Child epics

- KRMA-808
- KRMA-809
- KRMA-810
- KRMA-811
- KRMA-812
