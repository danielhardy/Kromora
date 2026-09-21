---
id: KRMA-372
title: Expand the default Looks library with 10–25 more distinctive styles
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add 10-25 new default Looks beyond the current starter set, with distinct names, categories, previews, and stable IDs.
      result: pass
      notes: 12 new Looks added (4 -> 16 total), all with unique kromora.starter.* IDs, unique .cube resources, distinct preview fingerprints (verified programmatically and via testBundledLooksHaveDistinctPreviewFingerprints).
    - criterion: Include at least four additional black-and-white Looks with visibly different tonal or contrast treatments.
      result: pass
      notes: Silver Noir, Paper Grain, Blueprint Mono, Infrared Mono added under Monochrome; inspected raw .cube tables and confirmed distinct tonal curves, not palette clones.
    - criterion: Include orange-and-teal/cinematic, warm natural negative-film-inspired, faded/pastel, high-contrast, and moody/cool-toned directions.
      result: pass
      notes: Ember & Cyan (cinematic orange/teal), Honey Negative (film-inspired), Pastel Wash + Bleached Daylight (pastel/faded), Hard Light (high-contrast), Midnight Slate (cool-toned), Forest Shadow (moody) all present.
    - criterion: Film-inspired entries use non-trademarked descriptive names; no official/ripped commercial emulation data.
      result: pass
      notes: Names are descriptive only ("Honey Negative", not a brand name); manifest acknowledgement explicitly disclaims official profiles/emulation data; approval notes reiterate 'no ripped commercial emulation data, camera profile, or official manufacturer asset used' per entry.
    - criterion: Every asset has machine-readable provenance/source/author/license/attribution/redistribution/approval metadata; fail-closed validation intact.
      result: pass
      notes: Confirmed each of the 12 new manifest entries carries all required fields; testMalformedBundledEntryIsSkippedWithoutHidingHealthyEntries (pre-existing, still passing) covers fail-closed behavior.
    - criterion: Default Looks remain read-only, discoverable by category, visually distinguishable from user Looks, no change to existing user/imported Look behavior.
      result: pass
      notes: testApplicationLibrarySeparatesStarterLooksFromUserLooks confirms bundled vs. user separation and category grouping still functions with the expanded set; UI marking logic (LookInspectorView) is untouched and keys off source==.bundled, so it applies automatically.
    - criterion: Add/update regression coverage for manifest count, unique IDs/resources, category/style coverage, asset validity, previews, and graceful loading of invalid assets.
      result: pass
      notes: BundledLookTests updated with count=16, uniqueness of ids/resources, category set, added testBundledLooksHaveDistinctPreviewFingerprints; malformed-entry resilience test retained.
    - criterion: Update Looks documentation and user-facing acknowledgements/attribution for newly bundled assets.
      result: pass
      notes: docs/LOOKS.md table and prose updated to list all 16 Looks and clarify descriptive-only film references; README.md summary count/category list updated; manifest acknowledgement string updated.
  checks_run:
    - swift test --filter BundledLookTests (5/5 passed)
    - scripts/ci-tests.sh fast (897/897 passed, exit 0)
    - git diff --check bf3703d^ bf3703d (no whitespace/EOF issues)
    - manual inspection of all 12 new .cube LUT tables for distinct, non-duplicated values
    - python3 JSON check for duplicate manifest ids/names/resources (0 duplicates across 16 entries)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T15:23:42.681Z
  session: 01MTYJ7Z6Q5QNFLXCL
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - looks
created: 2026-09-12T03:50:37.568Z
updated: 2026-09-12T15:23:42.683Z
order: a0
board: product
---

## Objective

Expand Kromora's read-only default Looks library with 10–25 additional interesting, production-ready styles.

## Context

The current starter set is useful but too small for first-run exploration. The expanded set should cover distinct creative directions rather than minor variations, including at least four additional black-and-white Looks, modern color grades such as orange-and-teal, and film-inspired looks such as a warm, natural negative-film rendering inspired by the qualities users associate with Portra 400. Film and manufacturer references must be descriptive/inspirational only unless the project has explicit rights; bundled assets must not imply official affiliation or reproduce proprietary profiles.

## Acceptance criteria

- [ ] Add 10–25 new default Looks beyond the current starter set, with distinct names, categories, previews, and stable IDs.
- [ ] Include at least four additional black-and-white Looks with visibly different tonal or contrast treatments.
- [ ] Include common aesthetic directions such as orange-and-teal/cinematic, warm natural negative-film-inspired color, faded/pastel, high-contrast, and moody or cool-toned treatments.
- [ ] Film-inspired entries use non-trademarked descriptive names unless explicit rights are documented; do not label a bundled Look as an official Kodak Portra 400 profile or ship ripped commercial emulation data.
- [ ] Every asset has machine-readable provenance, source/author, compatible license, attribution, redistribution terms, and project approval metadata; the existing fail-closed package/runtime validation remains intact.
- [ ] Default Looks remain read-only, discoverable by category, visually distinguishable from user Looks, and available without changing existing user/imported Look behavior.
- [ ] Add/update regression coverage for manifest count, unique IDs/resources, category/style coverage, asset validity, previews, and graceful loading when a single asset is invalid.
- [ ] Update the Looks documentation and user-facing acknowledgements/attribution for all newly bundled assets.


### Comment — codex @ 2026-09-12T15:20:24.614Z

Implemented and committed as bf3703d. Expanded the read-only bundled Looks library from 4 to 16 with 12 original 3x3x3 cubes: four distinct monochrome treatments plus cinematic orange-and-teal, cool twilight, warm natural negative-film-inspired, pastel, faded, high-contrast, cool-toned, and moody styles. Added unique stable manifest IDs/resources, full provenance/license/attribution/redistribution/approval metadata, manifest acknowledgement, docs/README updates, and regression coverage for count, categories, uniqueness, fingerprints/previews, application, user/bundled separation, and invalid-entry resilience. Checks: BundledLookTests 5 passed; scripts/ci-tests.sh fast 897 passed; scripts/ci-tests.sh serial 349 passed; swift build -c release passed; git diff --check and dg validate passed (only pre-existing model-name/deprecation warnings).

## Agent log

- 2026-09-12T15:23:42.681Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add 10-25 new default Looks beyond the current starter set, with distinct names, categories, previews, and stable IDs. (pass) — 12 new Looks added (4 -> 16 total), all with unique kromora.starter.* IDs, unique .cube resources, distinct preview fingerprints (verified programmatically and via testBundledLooksHaveDistinctPreviewFingerprints).
- [x] Include at least four additional black-and-white Looks with visibly different tonal or contrast treatments. (pass) — Silver Noir, Paper Grain, Blueprint Mono, Infrared Mono added under Monochrome; inspected raw .cube tables and confirmed distinct tonal curves, not palette clones.
- [x] Include orange-and-teal/cinematic, warm natural negative-film-inspired, faded/pastel, high-contrast, and moody/cool-toned directions. (pass) — Ember & Cyan (cinematic orange/teal), Honey Negative (film-inspired), Pastel Wash + Bleached Daylight (pastel/faded), Hard Light (high-contrast), Midnight Slate (cool-toned), Forest Shadow (moody) all present.
- [x] Film-inspired entries use non-trademarked descriptive names; no official/ripped commercial emulation data. (pass) — Names are descriptive only ("Honey Negative", not a brand name); manifest acknowledgement explicitly disclaims official profiles/emulation data; approval notes reiterate 'no ripped commercial emulation data, camera profile, or official manufacturer asset used' per entry.
- [x] Every asset has machine-readable provenance/source/author/license/attribution/redistribution/approval metadata; fail-closed validation intact. (pass) — Confirmed each of the 12 new manifest entries carries all required fields; testMalformedBundledEntryIsSkippedWithoutHidingHealthyEntries (pre-existing, still passing) covers fail-closed behavior.
- [x] Default Looks remain read-only, discoverable by category, visually distinguishable from user Looks, no change to existing user/imported Look behavior. (pass) — testApplicationLibrarySeparatesStarterLooksFromUserLooks confirms bundled vs. user separation and category grouping still functions with the expanded set; UI marking logic (LookInspectorView) is untouched and keys off source==.bundled, so it applies automatically.
- [x] Add/update regression coverage for manifest count, unique IDs/resources, category/style coverage, asset validity, previews, and graceful loading of invalid assets. (pass) — BundledLookTests updated with count=16, uniqueness of ids/resources, category set, added testBundledLooksHaveDistinctPreviewFingerprints; malformed-entry resilience test retained.
- [x] Update Looks documentation and user-facing acknowledgements/attribution for newly bundled assets. (pass) — docs/LOOKS.md table and prose updated to list all 16 Looks and clarify descriptive-only film references; README.md summary count/category list updated; manifest acknowledgement string updated.
Checks run:
- swift test --filter BundledLookTests (5/5 passed)
- scripts/ci-tests.sh fast (897/897 passed, exit 0)
- git diff --check bf3703d^ bf3703d (no whitespace/EOF issues)
- manual inspection of all 12 new .cube LUT tables for distinct, non-duplicated values
- python3 JSON check for duplicate manifest ids/names/resources (0 duplicates across 16 entries)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYJ7Z6Q5QNFLXCL
Summary: Verified: 12 new bundled Looks (4->16) meet all acceptance criteria — coverage of monochrome/cinematic/film-inspired/pastel/faded/high-contrast/cool-toned/moody, non-trademarked descriptive naming, full provenance metadata, updated docs, and expanded regression tests. BundledLookTests (5/5) and full fast suite (897/897) pass; no defects found; no fixes needed.
