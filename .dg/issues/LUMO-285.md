---
id: LUMO-285
title: Show latest edited state in edit and library thumbnails
type: task
status: done
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - thumbnails
  - editor
  - library
  - rendering
created: 2026-09-08T21:07:44.437Z
updated: 2026-09-08T22:13:11.994Z
order: a0
board: product
commits:
  - b6df9a3
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Edit-view filmstrip thumbnails show the latest edited appearance for each photo.
      result: pass
    - criterion: Library/grid thumbnails show the latest edited appearance for each photo.
      result: pass
    - criterion: Thumbnail refreshes are triggered when relevant per-photo edits or Look selections change, without requiring a full library rescan or application restart.
      result: pass
    - criterion: Thumbnail caching is invalidated or versioned by the effective edit state so stale original thumbnails are not reused.
      result: pass
    - criterion: Thumbnail generation remains bounded and does not block the main editor or visible preview.
      result: pass
    - criterion: Original-source thumbnails remain available as an intentional fallback while an edited thumbnail is rendering or when no edit document exists.
      result: pass
    - criterion: Regression coverage includes edit changes, Look/intensity changes, photo navigation, and shared filmstrip/library behavior.
      result: pass
  checks_run:
    - swift test
    - swift test --filter ThumbnailSwitchLifecycleTests --filter AppViewModelTests
    - git diff --check
  findings: []
  fixes:
    - Added shared edit-aware thumbnail state and fallback publication to ImageCollection.Item.
    - Added bounded scheduler requests keyed by photo with effective edit/LUT revision guards.
    - Added thumbnail rendering seam and regression coverage without affecting editor preview request accounting.
  verification_commits:
    - b6df9a3
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-08T22:13:11.992Z
  session: 01MTT7OWO8FKLL46BX
---

## Objective

Make thumbnails represent the latest saved or currently applied edit state rather than always showing
the original source image.

## Context

The edit filmstrip and library grid currently show thumbnails that can become stale as edits are made.
This makes it difficult to identify photos by their current look and creates an inconsistency between
the main preview and the browsing surfaces.

The behavior should apply to both thumbnail consumers:

- Photos in the edit view filmstrip.
- Photos in the library/grid view.

Thumbnail rendering should use the same effective document/look state as the photo's latest edit,
including changes that are persisted and changes visible during the current edit session where the
existing thumbnail architecture can support that update.

## Acceptance criteria

- [ ] Edit-view filmstrip thumbnails show the latest edited appearance for each photo.
- [ ] Library/grid thumbnails show the latest edited appearance for each photo.
- [ ] Thumbnail refreshes are triggered when relevant per-photo edits or Look selections change,
      without requiring a full library rescan or application restart.
- [ ] Thumbnail caching is invalidated or versioned by the effective edit state so stale original
      thumbnails are not reused.
- [ ] Thumbnail generation remains bounded and does not block the main editor or visible preview.
- [ ] Original-source thumbnails remain available as an intentional fallback while an edited
      thumbnail is rendering or when no edit document exists.
- [ ] Add regression coverage for edit changes, Look/intensity changes, photo navigation, and the
      shared behavior of filmstrip and library/grid surfaces.

## Implementation notes

Trace the existing `Thumbnails`, filmstrip, library-grid, edit-document, and Look-resolution paths.
Prefer a shared thumbnail request/cache identity based on the photo plus effective edit revision,
while keeping thumbnail work off the main actor and avoiding duplicate renders between the two UI
surfaces. Preserve fast original thumbnails as the initial/loading fallback.

Relevant areas to inspect:

- `Sources/LumoKit/Models/Thumbnails.swift`
- `Sources/LumoKit/Views/FilmstripView.swift`
- `Sources/LumoKit/Views/LibraryGridView.swift`
- `Sources/LumoKit/ViewModels/AppViewModel.swift`
- `Sources/LumoKit/Models/EditDocumentStore.swift`

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-08T22:13:11.993Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Edit-view filmstrip thumbnails show the latest edited appearance for each photo. (pass)
- [x] Library/grid thumbnails show the latest edited appearance for each photo. (pass)
- [x] Thumbnail refreshes are triggered when relevant per-photo edits or Look selections change, without requiring a full library rescan or application restart. (pass)
- [x] Thumbnail caching is invalidated or versioned by the effective edit state so stale original thumbnails are not reused. (pass)
- [x] Thumbnail generation remains bounded and does not block the main editor or visible preview. (pass)
- [x] Original-source thumbnails remain available as an intentional fallback while an edited thumbnail is rendering or when no edit document exists. (pass)
- [x] Regression coverage includes edit changes, Look/intensity changes, photo navigation, and shared filmstrip/library behavior. (pass)
Checks run:
- swift test
- swift test --filter ThumbnailSwitchLifecycleTests --filter AppViewModelTests
- git diff --check
Findings:
- None
Fixes:
- Added shared edit-aware thumbnail state and fallback publication to ImageCollection.Item.
- Added bounded scheduler requests keyed by photo with effective edit/LUT revision guards.
- Added thumbnail rendering seam and regression coverage without affecting editor preview request accounting.
Verification commits:
- b6df9a3
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTT7OWO8FKLL46BX
Summary: Implemented shared edit-aware thumbnails for filmstrip and library/grid surfaces with bounded scheduling, revision-aware publication, original fallback, and Look rescan refreshes.
