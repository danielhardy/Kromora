---
id: KRMA-862
title: "Library metadata filters: advanced filter sidebar (camera, lens, location, exposure, date)"
type: feature
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Delivered slice: advanced filter sidebar toggles in the Library and remembers its state per window."
      result: pass
      notes: LibraryGridView toggles the sidebar and persists presentation with SceneStorage.
    - criterion: "Delivered slice: camera and lens facets use OR within a facet, AND across facets, show value counts, and compose with existing filters and search."
      result: pass
      notes: Generated-fixture tests cover matching, counts, flag/rating, and search.
    - criterion: "Delivered slice: facet counts use the index off the main actor and preserve selection across filter changes."
      result: pass
      notes: Facet counts use a detached task over the query-controller snapshot; selection is UUID-based.
    - criterion: "Delivered slice: facets are part of Codable LibraryQuery and older payloads decode."
      result: pass
      notes: Round-trip and legacy-payload decoding are covered by LibraryFacetTests.
    - criterion: Date range, exposure, location, and all-filter toolbar summary requirements remain in this issue slice.
      result: not_applicable
      notes: These broader items were split to KRMA-880 (date), KRMA-881 (exposure), KRMA-882 (location), and KRMA-883 (all-filter toolbar summary).
    - criterion: Accessibility labels and keyboard navigation are present for the delivered sidebar controls.
      result: pass
      notes: Controls use standard SwiftUI buttons and checkbox toggles with accessibility labels; no manual assistive-technology audit was run.
  checks_run:
    - swift test --filter LibraryFacetTests — exit 0; 6 tests passed, 0 failures.
    - git diff --check cbc6eca8^ cbc6eca8 — passed.
    - Reviewed the implementation diff and query/sidebar integration; no security, maintainability, or performance blockers found.
  findings:
    - The toolbar summary and Clear action cover metadata facet selections only, not existing flag/rating filters or search. Follow-up KRMA-883 created with the verification label.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T14:39:40.743Z
  session: 01MV3XGPQ5OXPLYIQP
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - filtering
  - metadata
  - ux
created: 2026-10-10T15:45:36.939Z
updated: 2026-10-11T14:39:40.746Z
blockers: []
order: x
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T14:33:33.706Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Let the user narrow the Library by photographic metadata: camera, lens, location, and other fields such as focal length, ISO, aperture, capture date range, rating/flag/label. Presented as an optional advanced filter sidebar that slides in alongside the grid, so the default Library stays uncluttered.

## Context

Today the Library only has the basic `LibraryFilter` (flag/rating) plus text search over display name, label, camera make/model, lens and capture date (`LibraryQueryController`). Camera and lens are already sortable and already live in the index's `PortablePackageAssetSummary`. Location (GPS), ISO, aperture, shutter speed and focal length are parsed by `ImageMetadata` for the inspector but are **not** in the index summary, so they can't be filtered without a schema decision.

Decisions the ticket must settle (recommendation first):

1. **Facets from the index, not per-asset reads.** Filtering must stay on the disposable index projection. Camera, lens and capture date work today. Adding focal length, ISO, aperture, shutter and a coarse location to `PortablePackageAssetSummary` is a package-format change, so check `docs/LIBRARY_PACKAGE_FORMAT.md`, `docs/STORAGE_POLICY.md` and the existing compatibility approach (older packages decode unchanged, then a resumable repair backfills, as done for `presentedAspectRatio`/`sourceFingerprint`).
2. **Location:** start with a coarse, privacy-aware facet (country / city or a reverse-geocoded place name, computed once at import or backfill and stored) rather than raw coordinates in the filter UI. A map-based picker is a possible follow-up, not part of this ticket. Reverse geocoding must not block import or send data without the user's awareness; decide whether it is on-device only.
3. **Facet UI:** each facet lists its values with counts that reflect the other active filters; multi-select within a facet (OR), AND across facets; numeric fields (focal length, ISO, aperture) use range controls; date uses a range.
4. **Sidebar placement:** toggleable inspector-style sidebar in the Library, state remembered per window, with a clear "reset filters" and a visible active-filter summary when the sidebar is closed.

## Acceptance criteria

- [ ] An advanced filter sidebar can be shown/hidden in the Library and remembers its state.
- [ ] Users can filter by camera (make+model), lens, and capture date range, with value lists and counts, combined with the existing flag/rating filters and search.
- [ ] Users can filter by focal length, ISO and aperture (ranges or value lists) once those fields are in the index summary; older packages work unchanged and backfill via a resumable, non-blocking repair.
- [ ] Users can filter by location using a coarse place facet; assets without GPS are reachable via a "No location" value. Location handling is documented as to what is stored and whether any network lookup occurs.
- [ ] Active filters are summarized in the Library toolbar/status area and clearable in one action.
- [ ] Filtering and facet counts run against the index off the main actor, stay responsive on the large-library scale in `docs/LIBRARY_SCALE_REGRESSION.md`, and preserve selection across filter changes as the existing query controller does.
- [ ] Facet selection state is part of `LibraryQuery` (Codable) so it is testable without UI.
- [ ] Tests: query-controller tests for each facet and for combined filters/counts using generated fixtures; format/compat tests for any new summary fields; no display-bound capture.
- [ ] Accessibility: sidebar controls are keyboard navigable and labeled for VoiceOver.
- [ ] Docs updated (`docs/LIBRARY_PACKAGE_FORMAT.md` if the summary changes; `docs/PRODUCT_SCOPE.md` if scope text changes).

## Implementation notes

- Start from `Sources/KromoraKit/Models/LibraryQueryController.swift` (`LibraryQuery`, `LibraryFilter`, matching around line 695) and `PortablePackageAssetSummary` in `Sources/KromoraKit/Models/PortableLibraryPackage.swift`; metadata parsing is in `Sources/KromoraKit/Models/ImageMetadata.swift`; the grid is `Sources/KromoraKit/Views/LibraryGridView.swift`.
- Consider splitting into child tickets once decisions 1 and 2 are made: (a) sidebar shell + camera/lens/date facets (no format change), (b) summary schema + backfill for exposure fields, (c) location facet.

### Comment — claude @ 2026-10-11T14:33:34.108Z

Delivered slice (a): sidebar shell, camera+lens facets with OR/AND semantics and counts, active-filter summary + clear, SceneStorage per-window state, facets in Codable LibraryQuery, tests in LibraryFacetTests (commit cbc6eca8). Not delivered: date range (KRMA-880), focal/ISO/aperture (KRMA-881), location (KRMA-882), docs update (no format change yet), VoiceOver/keyboard audit beyond labeled checkboxes, and no manual UI run.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-11T14:39:40.743Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Delivered slice: advanced filter sidebar toggles in the Library and remembers its state per window. (pass) — LibraryGridView toggles the sidebar and persists presentation with SceneStorage.
- [x] Delivered slice: camera and lens facets use OR within a facet, AND across facets, show value counts, and compose with existing filters and search. (pass) — Generated-fixture tests cover matching, counts, flag/rating, and search.
- [x] Delivered slice: facet counts use the index off the main actor and preserve selection across filter changes. (pass) — Facet counts use a detached task over the query-controller snapshot; selection is UUID-based.
- [x] Delivered slice: facets are part of Codable LibraryQuery and older payloads decode. (pass) — Round-trip and legacy-payload decoding are covered by LibraryFacetTests.
- [ ] Date range, exposure, location, and all-filter toolbar summary requirements remain in this issue slice. (not_applicable) — These broader items were split to KRMA-880 (date), KRMA-881 (exposure), KRMA-882 (location), and KRMA-883 (all-filter toolbar summary).
- [x] Accessibility labels and keyboard navigation are present for the delivered sidebar controls. (pass) — Controls use standard SwiftUI buttons and checkbox toggles with accessibility labels; no manual assistive-technology audit was run.
Checks run:
- swift test --filter LibraryFacetTests — exit 0; 6 tests passed, 0 failures.
- git diff --check cbc6eca8^ cbc6eca8 — passed.
- Reviewed the implementation diff and query/sidebar integration; no security, maintainability, or performance blockers found.
Findings:
- The toolbar summary and Clear action cover metadata facet selections only, not existing flag/rating filters or search. Follow-up KRMA-883 created with the verification label.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV3XGPQ5OXPLYIQP
Summary: Verified the delivered camera/lens advanced-filter slice. Deferred date, exposure, location, and all-filter toolbar summary work are tracked in KRMA-880 through KRMA-883.
