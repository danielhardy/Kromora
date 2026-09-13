---
id: KRMA-377
title: Organize the Looks panel into Starter Looks and My Looks sections
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Remove per-Look accordion/disclosure behavior
      result: pass
      notes: Section-level collapse state and folder Section(isExpanded:) bindings removed from LookInspectorView.swift; all Looks render flat under two sections.
    - criterion: Visible Starter Looks group with all bundled Looks
      result: pass
      notes: LUTLibrary.starterLooks / LookCollectionID.starter covers all source == .bundled looks; verified via BundledLookTests.
    - criterion: Visible My Looks group with user-provided Looks
      result: pass
      notes: LUTLibrary.myLooks covers all source != .bundled looks.
    - criterion: Group headings remain visible and non-collapsible
      result: pass
      notes: collectionHeader is rendered as a plain Section header with no expand/collapse control.
    - criterion: Existing Look actions preserved (select/apply, preview, audition, intensity, import, remove/reveal)
      result: pass
      notes: selectLook/lookRows, intensitySection, importLookButton, chooseLookFile/chooseLookFolder header actions all retained unchanged.
    - criterion: Read-only/provenance distinction preserved for Starter Looks
      result: pass
      notes: collectionHeader shows a 'Read-only' badge for .starter; LookCollectionID.isReadOnly still gates it.
    - criterion: Sensible empty states incl. My Looks import CTA
      result: pass
      notes: collectionEmptyRow renders 'No Looks imported yet' + importLookButton for empty My Looks, a search-no-match state, and a Starter-empty state.
    - criterion: Stable deterministic ordering within each group
      result: pass
      notes: sortedLooks() orders by localized name then lutID as a tiebreaker; covered by testLookCollectionsHaveDeterministicFlatOrderingAcrossCategories.
    - criterion: UI/state tests covering group membership, no accordions, empty My Looks, source separation
      result: pass
      notes: BundledLookTests + LookInspectorViewTests additions exercise lookCollections, ordering, and rendered grouped-collection separation.
    - criterion: Verify existing Look-library tests, build/test lanes, dg validate, git diff --check
      result: pass
      notes: Re-ran swift build, focused BundledLookTests/LookInspectorViewTests, scripts/ci-tests.sh fast (twice), dg validate, git diff --check on the commit — all clean.
  checks_run:
    - swift build
    - swift test --filter 'BundledLookTests|LookInspectorViewTests' (11 tests, 0 failures)
    - scripts/ci-tests.sh fast (x2; one run had a PreviewDiskCacheTests timing flake under parallel load, confirmed unrelated to this change and non-reproducing on isolated re-run and on re-running the full lane)
    - dg validate
    - git diff --check on commit 2da4856
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T18:55:42.864Z
  session: 01MTYQT2N8D2W99NWC
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - looks
  - ux
created: 2026-09-12T15:19:03.429Z
updated: 2026-09-12T18:55:42.866Z
order: a0
board: product
---

## Objective

Simplify the Looks panel by replacing the current per-Look accordion layout with two always-visible collections:

- **Starter Looks** — bundled/default Looks shipped with the app.
- **My Looks** — Looks imported or uploaded by the user.

These names are intended to be clearer and more welcoming than “Included” and “Users.”

## Context

The current Looks panel makes every Look independently collapsible, which adds interaction overhead and hides the available choices. The expanded default library work in KRMA-372 will increase the number of bundled Looks, making a flat, grouped browser more useful. User-provided Looks must remain clearly separate from the read-only bundled collection.

Related work:
- KRMA-372 — expand the default Looks library.
- KRMA-150 — original bundled starter-library behavior and bundled/user source separation.

## Acceptance criteria

- [ ] Remove the individual accordion/disclosure behavior from Look rows; each Look is directly visible in its collection.
- [ ] Add a visible **Starter Looks** group containing every bundled/default Look, including the additional defaults from KRMA-372.
- [ ] Add a visible **My Looks** group containing every user-uploaded/imported or user-created Look.
- [ ] The two group headings remain visible while browsing; they are not themselves collapsible unless a later design decision explicitly adds that behavior.
- [ ] Keep the existing Look actions intact, including selecting/applying, previewing, auditioning, intensity adjustment, importing, and any remove/reveal actions supported for user Looks.
- [ ] Preserve the read-only status and provenance distinction for Starter Looks; user Looks must not be presented as bundled content.
- [ ] Define and implement sensible empty states, including a clear import action when My Looks has no user-provided entries.
- [ ] Use stable deterministic ordering within each group and keep the layout usable as the Starter Looks collection grows.
- [ ] Add or update UI/state tests covering group membership, no per-row accordions, empty My Looks behavior, and separation of bundled versus user sources.
- [ ] Verify existing Look-library tests and the relevant build/test lanes; run `dg validate` and `git diff --check`.

## Out of scope

- Adding or replacing Look assets; the bundled asset expansion belongs to KRMA-372.
- Changing LUT/Look import formats, persistence locations, or application/rendering behavior.
- Making the Starter Looks collection editable or deletable by users.


### Comment — codex @ 2026-09-12T18:52:43.055Z

Implemented in commit 2da4856. Replaced per-folder Look disclosures with always-visible Starter Looks and My Looks sections; preserved ID-based selection, previews, search/category matching, intensity, import, acknowledgement, and read-only provenance; added deterministic flat ordering and an empty My Looks import CTA. Added collection/state and rendered inspector coverage. Verification: scripts/ci-tests.sh verify; scripts/ci-tests.sh fast (922 tests); scripts/ci-tests.sh serial (370 tests); focused Looks/library/workflow run (46 tests); swift build -c release; dg validate; git diff --check. No findings or blockers.

## Agent log

- 2026-09-12T18:55:42.864Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Remove per-Look accordion/disclosure behavior (pass) — Section-level collapse state and folder Section(isExpanded:) bindings removed from LookInspectorView.swift; all Looks render flat under two sections.
- [x] Visible Starter Looks group with all bundled Looks (pass) — LUTLibrary.starterLooks / LookCollectionID.starter covers all source == .bundled looks; verified via BundledLookTests.
- [x] Visible My Looks group with user-provided Looks (pass) — LUTLibrary.myLooks covers all source != .bundled looks.
- [x] Group headings remain visible and non-collapsible (pass) — collectionHeader is rendered as a plain Section header with no expand/collapse control.
- [x] Existing Look actions preserved (select/apply, preview, audition, intensity, import, remove/reveal) (pass) — selectLook/lookRows, intensitySection, importLookButton, chooseLookFile/chooseLookFolder header actions all retained unchanged.
- [x] Read-only/provenance distinction preserved for Starter Looks (pass) — collectionHeader shows a 'Read-only' badge for .starter; LookCollectionID.isReadOnly still gates it.
- [x] Sensible empty states incl. My Looks import CTA (pass) — collectionEmptyRow renders 'No Looks imported yet' + importLookButton for empty My Looks, a search-no-match state, and a Starter-empty state.
- [x] Stable deterministic ordering within each group (pass) — sortedLooks() orders by localized name then lutID as a tiebreaker; covered by testLookCollectionsHaveDeterministicFlatOrderingAcrossCategories.
- [x] UI/state tests covering group membership, no accordions, empty My Looks, source separation (pass) — BundledLookTests + LookInspectorViewTests additions exercise lookCollections, ordering, and rendered grouped-collection separation.
- [x] Verify existing Look-library tests, build/test lanes, dg validate, git diff --check (pass) — Re-ran swift build, focused BundledLookTests/LookInspectorViewTests, scripts/ci-tests.sh fast (twice), dg validate, git diff --check on the commit — all clean.
Checks run:
- swift build
- swift test --filter 'BundledLookTests|LookInspectorViewTests' (11 tests, 0 failures)
- scripts/ci-tests.sh fast (x2; one run had a PreviewDiskCacheTests timing flake under parallel load, confirmed unrelated to this change and non-reproducing on isolated re-run and on re-running the full lane)
- dg validate
- git diff --check on commit 2da4856
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYQT2N8D2W99NWC
Summary: Independent verification pass: Starter/My Looks grouping, provenance/read-only badge, deterministic ordering, and empty-state CTA all verified against acceptance criteria; targeted tests + fast lane + dg validate + diff-check clean. No findings.
