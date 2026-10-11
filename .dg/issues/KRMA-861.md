---
id: KRMA-861
title: "Import selector: flag already-imported items and exclude them from default selection"
type: feature
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - import
  - library
  - ux
created: 2026-10-10T15:44:44.803Z
updated: 2026-10-10T15:44:44.803Z
blockers: []
order: zzzx
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
