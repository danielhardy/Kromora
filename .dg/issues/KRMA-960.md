---
id: KRMA-960
title: "Plan: adopt a String Catalog and stop composing user-facing strings in view models"
type: task
status: backlog
priority: low
human_review_required: true
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - localization
  - needs-decomposition
created: 2026-10-13T14:48:10.444Z
updated: 2026-10-24T14:25:58.188Z
parent: KRMA-922
blockers: []
order: 9e34p1kc
board: product
context:
  files: []
  docs:
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
  commands: []
---

## Objective

Decide whether v1 is English-only before adopting a String Catalog, and only then plan the catalog.

## Context

The 2026-10-13 review found no String Catalog and user-facing strings composed in view models, including manual plurals. The 2026-10-14 review (accessibility note in `.context/2026-10-14-release-readiness-review.md`) asks for an explicit decision: v1 may be English-only, and formatted sentences should not keep spreading through workflow code while that is undecided.

SwiftPM can host `.xcstrings` (`defaultLocalization` plus a package resource). The Xcode app target packages KromoraKit and must not gain implementation files (`XcodeProjectInvariantTests`).

Epic KRMA-994 tracks the note. This issue stays a child of KRMA-922.

## Acceptance criteria

- [ ] A comment inventories user-facing literals approximately, by directory, and recommends either English-only for v1 or a catalog now.
- [ ] Record the decision with `dg decision` or `dg issue block` asking the human to choose. Do not create the 5–10 migration child tickets, and do not land a String Catalog, before that decision.
- [ ] If the decision is English-only for v1: say that in the decision, point future copy at views rather than new sentences assembled in coordinators, and close this ticket without a catalog. A one-line scope note in `docs/PRODUCT_SCOPE.md` or `README.md` is enough.
- [ ] If the decision is to localize now: write `docs/LOCALIZATION_PLAN.md` covering where strings live, plural variants, and how `.xcstrings` is wired for SwiftPM and the Xcode package. Prove the wiring on the Export sheet only. Then create 5–10 child tickets, one directory or feature at a time.
- [ ] No other copy or behavior change.

## Implementation notes

Block for the human choice before creating child tickets. `dg issue block KRMA-960 --reason "v1 language scope is undecided" --action "Choose English-only for v1, or approve a String Catalog now"`.
