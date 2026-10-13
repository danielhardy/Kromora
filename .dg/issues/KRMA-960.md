---
id: KRMA-960
title: "Plan: adopt a String Catalog and stop composing user-facing strings in view models"
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - localization
  - needs-decomposition
parent: KRMA-922
created: 2026-10-13T14:48:10.444Z
updated: 2026-10-13T14:48:23.374Z
blockers: []
order: zzv
board: product
---

## Objective

Produce a plan (and child tickets) to localize user-facing strings with a String Catalog and
automatic plural handling.

## Context

Review `.context/2026-10-13-release-readiness-review.md` "Nice to have: Localization": no String Catalog exists; many user-facing strings are
composed in view models with manual plurals (for example `"Showing \(n) of \(m) photos"`, export
status text, error messages in coordinators). SwiftPM supports `.xcstrings` as a target resource
(`Package.swift` needs `defaultLocalization` and the resource declared); the Xcode app target packages
KromoraKit, so the resources must flow through (CLAUDE.md: no implementation files in the Xcode target;
a test enforces it — `XcodeProjectInvariantTests`).

## Acceptance criteria

- [ ] `docs/LOCALIZATION_PLAN.md` (new): inventory the count of user-facing string literals by
      directory (`grep`-based, approximate is fine), decide where strings live (views get
      `LocalizedStringKey`; view models return typed state/enums and views format it), the plural
      strategy (String Catalog variations), and how `.xcstrings` is wired for both SwiftPM and the Xcode
      package without adding files to the Xcode target.
- [ ] A spike proves the wiring on ONE screen (the Export sheet) in a throwaway branch/commit: English
      catalog compiles under `swift build`, `scripts/app-store-build.sh` is not required to run.
- [ ] 5-10 child tickets created, each one directory/feature at a time.
- [ ] No behavior or copy changes shipped by this ticket other than the spike.
