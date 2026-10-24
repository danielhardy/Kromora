---
id: KRMA-845
title: Library double-click sometimes does not open the photo in Edit
type: bug
status: done
priority: medium
agent: codex
human_review_required: false
model: gpt-6.1-sol
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Cause recorded.
      result: pass
      notes: Silent fall-through, independent SwiftUI tap recognizers, offset-keyed cells.
    - criterion: Double-click opens Edit reliably under busy thumbnail queue and during import.
      result: pass
      notes: Human confirmed manually; automated tests cover import between clicks.
    - criterion: No silent no-op path remains in openLibraryImageForEditing/openActiveCollectionImage.
      result: pass
      notes: All early returns now present an error or loading state.
    - criterion: "Related: KRMA-841."
      result: pass
  checks_run:
    - git show b1067796 diff review
    - swift test --filter LibraryCellClickTests|LibraryGridTests|NavigationStateTests|ImageCollection (26 pass)
    - swift test --filter LibraryCellClickTests|WorkspaceNavigationTests|LibrarySelection (24 pass)
  findings:
    - "low: NSView click overlay handles only mouseDown; context menus and drag-out not exercised. Non-blocking."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-10T15:05:58.985Z
  session: 01MV2J0AFTYI6D0LG9
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T00:56:48.011Z
updated: 2026-10-10T15:05:58.989Z
blockers:
  - id: evt_mv1wlf0o_rfqul0
    type: human
    reason: The desktop is locked, so the required manual double-click check under busy thumbnails and during import could not be performed.
    action: On an unlocked, awake desktop, run the current build and double-click several photos while thumbnails are loading and while an import runs. Confirm Edit opens the clicked photo or shows an actionable error, record the outcome in KRMA-845, then run dg issue resume KRMA-845 verification.
    created_at: 2026-10-10T04:37:55.656Z
    resolved_at: 2026-10-10T15:05:19.429Z
    resolved_by: web
order: a0
board: product
blocked_reason: The desktop is locked, so the required manual double-click check under busy thumbnails and during import could not be performed.
blocked_action: On an unlocked, awake desktop, run the current build and double-click several photos while thumbnails are loading and while an import runs. Confirm Edit opens the clicked photo or shows an actionable error, record the outcome in KRMA-845, then run dg issue resume KRMA-845 verification.
blocked_from_status: ready
---

## Objective

Double-clicking a photo in the Library grid should always enter Edit for that photo. The user reports it sometimes does nothing (intermittent; possibly related to the slow thumbnail loading in KRMA-841). Find the cause(s) and make the open reliable, or visibly acknowledge a click that cannot proceed.

## Findings so far (static reading; not reproduced)

Gesture: `LibraryGridRow` (`Sources/KromoraKit/Views/LibraryGridView.swift`, ~line 225) attaches `.onTapGesture { onSelect }` and then `.simultaneousGesture(TapGesture(count: 2) { onSelect; onOpen })`. Handler: `AppViewModel.openLibraryImageForEditing` -> `openActiveCollectionImage(loadMode: true)`.

Candidate causes, most likely first:

1. **The first click does heavy main-actor work before the second click lands.** `onSelect` -> `ImageCollection.select(at:)` maps `filteredItems.map(\.id)` (O(n), twice), `prepareAdjacentThumbnails`, `reprioritizeThumbnails`, and publishes observation changes that re-evaluate the grid. When the main actor is busy (thumbnails arriving, KRMA-841; import running), the second click can miss the double-click interval or arrive while the cell view is being rebuilt, so the count-2 recognizer never completes. A single tap handler declared before a count-2 recognizer is also a known fragile combination on macOS.
2. **Silent no-ops in the open path.** `openLibraryImageForEditing` returns if `collection.selectedItem == nil`; `openActiveCollectionImage` returns when `activeAssetID == item.id` and `sourceSession.isBusy` (a slow open of a large RAW, ~130 MB `.ARW`, swallows the repeat), and does nothing when the selected item has neither `url` nor `imageData`. Portable assets may carry no resolved URL until materialized (`openPortableAsset` uses `library.resolveEmbeddedSourceURL`, the grid path uses `item.url`).
3. **Cell identity.** `ForEach(indices, id: \.self)` keys cells by row offset, not asset id; a window reload during the two clicks (import finishing, index repair) can replace the cell under the pointer.

## Suggested approach

1. Reproduce with a large library and a busy thumbnail queue (and while an import runs); log the click sequence, `onSelect`/`onOpen` timestamps and each early-return in `openActiveCollectionImage`.
2. Make double-click detection robust: a single `onTapGesture(count: 2)` ordered before the single tap, or an AppKit `clickCount`-based handler, so it does not depend on the first click's re-render. Keep selection feedback immediate and cheap (defer thumbnail reprioritization off the click path).
3. Remove silent returns: resolve the URL through the package when `item.url` is nil, and when a repeat open is ignored because a load is in flight, either queue it or show the loading state.
4. Add a regression test for the open path (selected item without a URL resolves through the package; repeated open while busy is not lost) and a gesture-level test if feasible.

## Acceptance criteria

- [ ] Cause recorded.
- [ ] Double-click opens Edit reliably under a busy thumbnail queue and during an import (manual check plus whatever automated coverage is practical).
- [ ] No silent no-op path remains in `openLibraryImageForEditing`/`openActiveCollectionImage` for a selected photo.
- [ ] Related: KRMA-841.

### Comment — codex @ 2026-10-10T04:37:50.108Z

Implementation committed as b1067796 (KRMA-845: make Library photo double-click opens reliable).

Cause and scope: static inspection confirmed a silent fall-through when the selected photo had neither a browsing URL nor image bytes. The grid also ran single selection and simultaneous double-tap recognizers independently, replaying modifier selection on the double-click, and keyed cells/callbacks by offsets that imports can change. The original intermittent physical-click timing could not be reproduced because this desktop is locked. The existing same-source busy return already transitioned to Edit; it now explicitly acknowledges Loading while retaining the single in-flight preparation.

Changes: native NSEvent clickCount input (including replacement surfaces), asset-ID cell identity and open callbacks, event-local Command/Shift modifiers, no selection toggle replay on double-click, constant-size selection ordering for ordinary/Command clicks, package URL resolution for unresolved sources, and visible errors for unavailable/stale/filtered targets or absent selection. Retained-source reuse and inspector presentation are preserved.

Verification: 57 focused Library/grid/selection/navigation/coordinator tests pass, including import publication between click events with original-thumbnail work pending, Command deselection, filtered/stale targets, missing browsing URL resolving through the package, and repeated opens during gated source preparation. scripts/ci-tests.sh warning-gate passes with zero Swift diagnostics. scripts/app-store-build.sh passes build, signature/entitlements, deployment-floor and resource checks (only the standard AppIntents metadata-extraction notice). git diff --check passes.

Broader lanes: fast ran 1,563 tests with four unrelated failing tests: CropInspectorTests/testResetButtonUsesTheSemanticPrimaryAccentAndKeepsLinkAccessibility, InfoInspectorPresentationTests/testLookAndHistogramHeadingsFollowSharedHierarchy, LightInspectorTests/testToneCurveResetUsesAccessibleTrailingDisclosureAction, and EditedThumbnailCoordinatorTests/testInitialVisibleDemandUsesPersistedEditsAfterPackageReopen (599x1199 vs minimum 600x1200). All four reproduced separately. Serial ran 498 tests with one unrelated failing test, MenuCommandTests/testCropResetLivesInPinnedInspectorTitleRow. Their implementation/test files are unchanged; the thumbnail-size case does not exercise selection. Logs: /tmp/krma-845-final-focused.log, /tmp/krma-845-fast.log, /tmp/krma-845-rerun.log, /tmp/krma-845-serial.log, /tmp/krma-845-warning-gate.log, /tmp/krma-845-app-build.log.

Manual acceptance check remains pending: the console reports CGSSessionScreenIsLocked=Yes and Computer Use could not access a window. Both isolated UI probe processes were terminated and their temporary app/fixtures removed; all started command sessions finished and exit statuses were inspected. Adding a Human blocker for the required manual double-click check under busy thumbnails and during import. KRMA-841 remains related, not a dependency of this fix.

### Comment - Human

I have verified this work and can cnofirm double click now works even when images are being loaded in.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-10T15:05:58.986Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Cause recorded. (pass) — Silent fall-through, independent SwiftUI tap recognizers, offset-keyed cells.
- [x] Double-click opens Edit reliably under busy thumbnail queue and during import. (pass) — Human confirmed manually; automated tests cover import between clicks.
- [x] No silent no-op path remains in openLibraryImageForEditing/openActiveCollectionImage. (pass) — All early returns now present an error or loading state.
- [x] Related: KRMA-841. (pass)
Checks run:
- git show b1067796 diff review
- swift test --filter LibraryCellClickTests|LibraryGridTests|NavigationStateTests|ImageCollection (26 pass)
- swift test --filter LibraryCellClickTests|WorkspaceNavigationTests|LibrarySelection (24 pass)
Findings:
- low: NSView click overlay handles only mouseDown; context menus and drag-out not exercised. Non-blocking.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MV2J0AFTYI6D0LG9
Summary: Verified: double-click fix reviewed, focused tests pass, human confirmed manually.
