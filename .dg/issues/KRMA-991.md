---
id: KRMA-991
title: "Photos import review: thumbnails never resolve (placeholders stay forever)"
type: bug
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - photos-import
created: 2026-10-14T01:22:17.526Z
updated: 2026-10-14T01:22:17.526Z
blockers: []
order: zzzzzzx
board: product
---

## Objective

The "Import from Photos" review sheet shows real thumbnails for every selected asset, or an explicit failure state, instead of leaving placeholder tiles indefinitely.

## Context

Reported after importing from Apple Photos: the review sheet ("4 of 4 selected", Import 4 Selected enabled) shows only the generic photo-glyph placeholder in every tile, and the thumbnails never resolve.

`PhotosReviewThumbnail` in `Sources/KromoraKit/Views/PhotosImportReviewView.swift` loads via `PHImageManager.requestImage` with `isNetworkAccessAllowed = false` and resumes its continuation with whatever image arrives, including `nil`. A `nil` result (iCloud-only original, a nil `localIdentifier`, an asset that fails to fetch, or a PhotoKit error carried in the result-info dictionary that the handler ignores) is indistinguishable from "still loading", so the placeholder stays forever with no retry, spinner, or error. Likely causes to confirm: iCloud-optimized assets, missing/limited Photos authorization at the time the sheet appears, or `localIdentifier` not populated on the selection.

## Acceptance criteria

- [ ] Reproduce with the reporter's scenario (assets imported from Photos, review sheet shown) and record the root cause in the ticket.
- [ ] Thumbnails resolve for locally available assets and for iCloud-only assets (allow network access for thumbnails, or fall back to a degraded image) without blocking the sheet.
- [ ] A failed or `nil` load is distinguished from loading: show a progress state while loading and a visible failure state (with retry or at least a clear glyph) on error; inspect the `PHImageErrorKey`/`PHImageResultIsInCloudKey` info.
- [ ] The request is cancelled when the tile disappears and the continuation is resumed exactly once.
- [ ] A deterministic test covers the load-state model (loading, loaded, failed) through an injectable image provider; `swift build` stays warning-free under Swift 6 mode with no concurrency opt-outs.

## Implementation notes

Extract the thumbnail loading into a small testable loader/state type rather than a static function inside the view. Related: `PhotosImportReviewCoordinator`, `PhotosImportCoordinator`.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
