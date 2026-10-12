---
id: KRMA-861
title: "Import selector: flag already-imported items and exclude them from default selection"
type: feature
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Each item in folder, Photos, and removable-volume import selectors shows an In library tag for current library matches
      result: pass
      notes: Folder and removable sources share the membership-aware selector; Photos uses a review grid. Both expose text tags and VoiceOver values.
    - criterion: Matched items are excluded from defaults, unmatched items remain selected by default, and users can manually reselect matches
      result: pass
      notes: Coordinator tests verify default exclusion, explicit reselection, and that late matches preserve a touched choice.
    - criterion: The selector shows an already-in-library count and an affordance to hide or filter matches
      result: pass
      notes: Both selector views show counts and Hide controls when matches are present.
    - criterion: Detection is off-main, progressive, cancellable on close, and does not override touched selections
      result: pass
      notes: File hashing and Photos digest work run off-main and fill progressively. Cancellation propagates to the detached matcher load and is checked between shard and asset-record reads; selector close cancels checking. Explicit selections are preserved.
    - criterion: Membership tags agree with import-time duplicate detection
      result: pass
      notes: Generated-fixture tests verify the package import duplicate policy for file and Photos payload digests.
    - criterion: Model-level matcher and default-selection tests use generated fixtures
      result: pass
      notes: Focused matcher, folder coordinator, and Photos review coordinator tests passed.
    - criterion: Large-import performance is checked with the KRMA-841 window-independent benchmark
      result: pass
      notes: "1,500-file Release benchmark passed: visible fill 1,888 ms; heartbeat max 15.3 ms with 0/1,192 gaps over 33 ms; select-all 0.54-1.01 ms; shift-click 0.73 ms; peak RSS 2,040 MB."
    - criterion: The membership tag is exposed to VoiceOver and is not conveyed by color alone
      result: pass
      notes: Both views use visible text plus a checkmark seal symbol and set an accessibility value that includes membership.
  checks_run:
    - "swift test --filter LibraryMembershipMatcherTests|LibraryMediaWorkflowCoordinatorTests|PhotosImportReviewCoordinatorTests|PhotosImportTests: exit 0; 28 tests passed."
    - "KROMORA_LARGE_IMPORT_BENCHMARK=1 KROMORA_LARGE_IMPORT_COUNT=1500 swift test -c release --filter LargeImportLibraryGridBenchmark: exit 0; visible fill 1,888 ms; heartbeat max 15.3 ms; 0/1,192 gaps above 33 ms; select-all 0.54-1.01 ms; shift-click 0.73 ms; peak RSS 2,040 MB."
    - "git diff --check -- Sources/KromoraKit/Models/PortablePackageImport.swift: exit 0."
    - Independent source review of folder routing, Photos import review and duplicate handling, cancellation propagation, and accessibility values.
  findings: []
  fixes:
    - Added cooperative cancellation checks between membership-shard and asset-record reads so closing a selector can stop an in-progress detached catalog load.
  verification_commits:
    - 68cab02fe72a1425c356a9e32d8d19918d6f0aca
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T18:28:26.001Z
  session: 01MV45H6DE5CLRKVCS
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - import
  - library
  - ux
created: 2026-10-10T15:44:44.803Z
updated: 2026-10-11T18:28:26.005Z
blockers: []
order: zx
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T17:41:34.083Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 68cab02fe72a1425c356a9e32d8d19918d6f0aca
---

## Objective

When the user opens an import source (folder, Photos, removable volume), the selection screen should detect items that are already in the open library, show them tagged (for example "In library" or "Previously imported"), and leave them unselected by default. The user can still select them explicitly to re-import.

## Context

Today duplicates are only discovered after the fact: the import runs, idempotency admits existing assets, and the result summary reports "N duplicates" (`ImportOutcomeSummary`, `PhotosImportCoordinator` `.duplicate`). Re-importing a card or folder therefore means selecting everything and waiting, or hand-picking the new files. The package owns library membership (CLAUDE.md), so "already imported" is answered from the open package's index, not from a separate import-history store.

Open questions to settle in the ticket (recommendation first):

1. Scope of "previously imported": match against the current library only (recommended; it is what the package can answer authoritatively). Remembering imports into *other* libraries or since-deleted assets would need a new local projection and is out of scope unless the owner asks for it.
2. Matching key: reuse the existing import idempotency identity (content digest / `PhotoAssetID`) so the badge agrees with what the import would actually skip. Hashing every candidate up front is expensive for large cards, so consider a cheap pre-filter (filename + size + capture date, or a Photos local identifier) with the digest as confirmation, computed lazily and cancellably off the main actor.
3. Photos source: match on the PhotoKit local identifier if the package already records it; otherwise fall back to the digest path.

## Acceptance criteria

- [ ] Each item in the import selector for folder, Photos, and removable-volume sources shows an "In library" (or equivalent) tag when it matches an asset in the open library.
- [ ] Matched items are not selected by default, including under "Select all" style defaults; unmatched items keep today's default selection.
- [ ] The user can select a tagged item manually; importing it follows the existing duplicate policy (no new duplicate behavior).
- [ ] The selector shows a count of previously imported items (for example "12 of 240 already in library") and an affordance to hide or filter them.
- [ ] Detection runs off the main actor, is cancellable when the selector closes, and does not block the grid from appearing; tags fill in progressively and selection defaults settle without flicker or surprising deselection of items the user already touched.
- [ ] The match rule agrees with import-time idempotency: an item tagged as in-library is a `.duplicate` if imported, and an untagged item is not (cover with a test).
- [ ] Tests: model-level tests for the matcher and default-selection logic using generated fixtures; no display-bound capture needed (per CLAUDE.md).
- [ ] Large-import performance is checked with the window-independent benchmark approach from KRMA-841, not a display capture.
- [ ] Accessibility: the tag is exposed to VoiceOver, not conveyed by color alone.

## Implementation notes

- Entry points to inspect: `Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift` (progress, `.duplicate`, digest handling around line 195), `Sources/KromoraKit/ViewModels/LibraryImportCoordinator.swift`, `Sources/KromoraKit/Views/RemovableMediaSelectorView.swift`, `Sources/KromoraKit/Models/PortablePackageImport.swift`, and the folder/Photos selection views.
- Keep ownership per `docs/APP_ARCHITECTURE.md`: a focused matcher that the import coordinators consult, not logic in the view.
- Update `docs/PRODUCT_SCOPE.md` or `docs/APP_ARCHITECTURE.md` only if the behavior changes a documented contract.

## Verification blocker — incomplete source coverage

Counterpoint verification found that the implementation only adds membership detection and
selection behavior to `RemovableMediaSelectorView`. Folder selection still routes directly to
`onSourceFolder` and imports without a selection screen, while the Photos picker transfers the
user's selected items without showing membership tags, excluding existing items by default, a
count, or a filter. This fails the first four acceptance criteria for folder and Photos sources;
the overall feature is incomplete.

Implementation pickup must provide an import-selection experience for folder and Photos sources
that uses the same open-library membership rule, shows accessible "In library" tags and a count,
lets users hide or explicitly reselect matches, and excludes matches from the default selection
without undoing choices made while checks arrive. Preserve the existing import duplicate policy.
For Photos, use the package's stored local identifier when available and otherwise confirm with the
same content digest used by import idempotency. Keep detection off the main actor, progressive, and
cancellable when its selector closes.

To verify the fix, add model/coordinator coverage for folder and Photos default selection, explicit
reselection and late membership results; prove tagged items import as duplicates and untagged
items do not; verify the accessibility value; run the focused tests and the KRMA-841 window-
independent Release benchmark (no display-bound capture).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-11T17:50:07.018Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] Each item in folder, Photos, and removable-volume import selectors shows an In library tag for current library matches (fail) — Removable-media cells are tagged. Folder imports have no selector and Photos selection uses the system picker without membership tags.
- [ ] Matched items are excluded from defaults, unmatched items remain selected by default, and users can manually reselect matches (fail) — These behaviors are implemented and tested for removable media only; folder and Photos selection do not provide them.
- [ ] The selector shows an already-in-library count and an affordance to hide or filter matches (fail) — Implemented only in RemovableMediaSelectorView.
- [ ] Detection is off-main, progressive, cancellable on close, and does not override touched selections (fail) — Removable-media hashing is off-main and progressive and selection state preserves explicit choices. The Photos and folder flows are missing. Additionally, the detached library-catalog loader is awaited without cancellation propagation, so closing during catalog loading may leave that work running to completion.
- [x] Membership tags agree with import-time duplicate detection (pass) — LibraryMembershipMatcherTests.testMatcherAgreesWithImportTimeDuplicateDetection covers renamed same-content, new-content, and same-size different-content files.
- [x] Model-level matcher and default-selection tests use generated fixtures (pass) — Focused tests cover matcher identity, unreadable files, cancellation, selection defaults, late tags, and explicit selection.
- [x] Large-import performance is checked with the KRMA-841 window-independent benchmark (pass) — The 1,500-file Release benchmark passed: 2,141 ms visible fill, heartbeat max 20.5 ms with 0/1,371 gaps over 33 ms, select-all 0.53-1.00 ms, shift-click 0.67 ms, peak RSS 1,802 MB.
- [x] The membership tag is exposed to VoiceOver and is not conveyed by color alone (pass) — Removable-media cells expose Already in library in their accessibility value; the visible tag includes text and a checkmark seal symbol.
Checks run:
- swift test --filter LibraryMembershipMatcherTests and LibraryMediaWorkflowCoordinatorTests: exit 0; 12 tests passed.
- KROMORA_LARGE_IMPORT_BENCHMARK=1 KROMORA_LARGE_IMPORT_COUNT=1500 swift test -c release --filter LargeImportLibraryGridBenchmark: exit 0; 1 benchmark passed; visible fill 2,141 ms; heartbeat max 20.5 ms; 0/1,371 gaps above 33 ms; select-all 0.53-1.00 ms; shift-click 0.67 ms; peak RSS 1,802 MB.
- Independent source review of folder routing in LibraryMediaWorkflowCoordinator, Photos selection in ContentView and PhotosImportCoordinator, and removable-media selector.
Findings:
- Blocking: implementation scope is limited to removable media, while folder and Photos import flows do not show membership, exclude matches from default selection, provide the count/filter, or allow selector-based reselection.
- Cancellation gap: the detached package catalog loader is not cancelled when its awaiting selector check task is cancelled.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV446AYTYH5C1GGI
Summary: Verification blocked: membership selection is implemented only for removable media; folder and Photos flows are missing the acceptance criteria.

- 2026-10-11T18:28:26.001Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Each item in folder, Photos, and removable-volume import selectors shows an In library tag for current library matches (pass) — Folder and removable sources share the membership-aware selector; Photos uses a review grid. Both expose text tags and VoiceOver values.
- [x] Matched items are excluded from defaults, unmatched items remain selected by default, and users can manually reselect matches (pass) — Coordinator tests verify default exclusion, explicit reselection, and that late matches preserve a touched choice.
- [x] The selector shows an already-in-library count and an affordance to hide or filter matches (pass) — Both selector views show counts and Hide controls when matches are present.
- [x] Detection is off-main, progressive, cancellable on close, and does not override touched selections (pass) — File hashing and Photos digest work run off-main and fill progressively. Cancellation propagates to the detached matcher load and is checked between shard and asset-record reads; selector close cancels checking. Explicit selections are preserved.
- [x] Membership tags agree with import-time duplicate detection (pass) — Generated-fixture tests verify the package import duplicate policy for file and Photos payload digests.
- [x] Model-level matcher and default-selection tests use generated fixtures (pass) — Focused matcher, folder coordinator, and Photos review coordinator tests passed.
- [x] Large-import performance is checked with the KRMA-841 window-independent benchmark (pass) — 1,500-file Release benchmark passed: visible fill 1,888 ms; heartbeat max 15.3 ms with 0/1,192 gaps over 33 ms; select-all 0.54-1.01 ms; shift-click 0.73 ms; peak RSS 2,040 MB.
- [x] The membership tag is exposed to VoiceOver and is not conveyed by color alone (pass) — Both views use visible text plus a checkmark seal symbol and set an accessibility value that includes membership.
Checks run:
- swift test --filter LibraryMembershipMatcherTests|LibraryMediaWorkflowCoordinatorTests|PhotosImportReviewCoordinatorTests|PhotosImportTests: exit 0; 28 tests passed.
- KROMORA_LARGE_IMPORT_BENCHMARK=1 KROMORA_LARGE_IMPORT_COUNT=1500 swift test -c release --filter LargeImportLibraryGridBenchmark: exit 0; visible fill 1,888 ms; heartbeat max 15.3 ms; 0/1,192 gaps above 33 ms; select-all 0.54-1.01 ms; shift-click 0.73 ms; peak RSS 2,040 MB.
- git diff --check -- Sources/KromoraKit/Models/PortablePackageImport.swift: exit 0.
- Independent source review of folder routing, Photos import review and duplicate handling, cancellation propagation, and accessibility values.
Findings:
- None
Fixes:
- Added cooperative cancellation checks between membership-shard and asset-record reads so closing a selector can stop an in-progress detached catalog load.
Verification commits:
- 68cab02fe72a1425c356a9e32d8d19918d6f0aca
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV45H6DE5CLRKVCS
Summary: Verification passed after adding cooperative cancellation checks to package membership catalog reads.
