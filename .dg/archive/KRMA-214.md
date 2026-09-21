---
id: KRMA-214
title: Show the current photo name and file type in the Inspect panel
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run:
    - swift test --filter PhotoAssetTests
    - git diff --check
  findings: []
  fixes:
    - Added durable current-photo name and file-type rows with deterministic fallbacks to Inspect
  verification_commits:
    - a3aa2fc
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T19:49:13.784Z
  session: 01MTND3JYKJ75K4SLA
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ux
  - photo-library
created: 2026-09-04T19:08:10.869Z
updated: 2026-09-10T12:53:47.690Z
order: prxp20gn
board: product
commits:
  - a3aa2fc
---

## Objective

Show the current photo's name and file type in the Inspect panel.

## Context

The Info/Inspect panel currently shows histogram and EXIF/TIFF metadata, but it does not identify
which photo is open. This is especially confusing for Apple Photos imports and data-backed assets
whose source is not obvious from a filesystem path. The requested identity rows should remain
available even when the optional photographic metadata is empty.

## Acceptance criteria

- [ ] Inspect shows a stable `Name` row for the current asset using its preserved display/original
      name, with a deterministic fallback when no name exists.
- [ ] Inspect shows a `File Type` row derived from the source UTI/extension or decoded image type,
      including for Photos-imported data-backed assets.
- [ ] The rows update immediately when navigating between photos, never show the prior photo's
      identity, and remain available when EXIF metadata is missing.
- [ ] The rows are text-selectable/accessibility-readable and use the same naming convention as the
      library and filmstrip without being affected by the `Show Photo Names` view preference.
- [ ] Add tests for file-backed, Apple Photos/data-backed, missing-metadata, and navigation cases.

## Implementation notes

- Keep identity display separate from the optional `ImageMetadata.sections` content if necessary;
  an image with no EXIF should still show name/type. Reuse the existing `PhotoAsset`/`ImageSource`
  metadata rather than inferring type from the rendered preview.
- Coordinate with KRMA-210 so original Photos names are preserved once and consumed consistently by
  the library, filmstrip, Inspect, and export flows.

### Comment — codex @ 2026-09-04T19:49:13.491Z

Implemented Inspect identity rows. PhotoAsset now provides the shared display-name fallback and extension/ImageIO-derived file type; ImageCollection uses the same display name, and InfoInspector renders selectable Name and File Type rows independently of EXIF metadata and Show Photo Names. Verification: swift test --filter PhotoAssetTests (9/9 passed). Full swift test builds but the pre-existing dirty worktree reports 15 unrelated failures in comparison/develop/workflow tests.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T19:49:13.785Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTND3JYKJ75K4SLA
Summary: Inspect now shows current asset name and file type using durable PhotoAsset identity, including Photos/data-backed and missing-metadata cases; added deterministic fallbacks and focused tests.
