---
id: KRMA-912
title: Show camera and lens in Library facets from backfilled capture metadata
type: task
status: backlog
priority: medium
agent: claude
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - library
  - facets
created: 2026-10-12T17:27:12.750Z
updated: 2026-10-12T17:28:13.378Z
blockers: []
order: zzzy
board: product
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/Models/LibraryFacets.swift
      access: write
      confidence: 1
---

## Objective

Make the Library camera and lens facets list real names for every photo, including photos imported or indexed before camera and lens were recorded in the asset summary.

## Context

The camera and lens facets read `cameraMake`, `cameraModel` and `lens` from `PortablePackageAssetSummary`. Newly imported photos did not record them, the capture-metadata backfill (which repairs `captureSettings`, `coarseLocation` and `captureDateISO` from embedded originals) did not fill them, and a Library index written before a backfill committed kept showing the old summary. The camera facet also repeated the make when the model already began with it (for example "Canon Canon EOS R5").

Note for the verifier: this working-tree change was written by the project owner (or another session), not by the implementer; the implementer reviewed the diff, ran the checks below and added the `cameraName` test.

## Work done

- `LibraryFacets.swift`: new `LibraryFacet.cameraName(make:model:)` collapses a make repeated at the start of the model and is used for the camera facet value.
- `PortablePackageImport.swift`: imported summaries now record `cameraMake`, `cameraModel` and `lens` (empty string when nothing is embedded).
- `PortablePackageEditSidecar.swift`: `needsCaptureMetadata` also checks `cameraModel`; the backfill fills make, model and lens, writing empty strings for "read, nothing embedded" so the repair does not retry.
- `LibraryQueryController.swift`: the index reconcile adopts backfilled capture settings, location, date and camera/lens from the package when the index lacks them, and only rewrites the entry if the summary actually changed.
- `LibraryFacetTests`: `testCameraNameDoesNotRepeatTheMakeAlreadyInTheModel`.

## Acceptance criteria

- The camera facet shows "Make Model" without a repeated make; the lens facet shows lens names.
- A newly imported photo has camera and lens in its summary.
- A package indexed before the backfill ran picks up camera, lens, location, settings and date on the next reconcile, without a rebuild.
- An original with no embedded camera data is not re-read on every open.

## Verification notes

- Checks run: `swift build`; `swift test --filter 'CaptureMetadataBackfillTests|LibraryFacetTests|LibraryQueryControllerTests|CaptureMetadataOverlayTests'` (36 tests, 0 failures).
- Gap: there is no direct test for the index reconcile adopting backfilled values, or for the importer writing camera/lens. A verifier should add or request those.
