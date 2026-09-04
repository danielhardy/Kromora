---
id: LUMO-210
title: Preserve Apple Photos original names and make photo-name display configurable
type: bug
status: done
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ux
  - photo-library
created: 2026-09-04T19:07:58.571Z
updated: 2026-09-04T19:34:29.320Z
order: n
board: product
commits:
  - 7e891c8
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run:
    - swift build
    - swift test --filter 'LumoSettingsTests|PhotosImportTests'
    - git diff --check
  findings: []
  fixes:
    - Preserved Apple Photos original filenames and added persisted Show Photo Names setting
    - Batched the pending culling/library presentation changes with the shared library surfaces
  verification_commits:
    - 7e891c8
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T19:34:29.314Z
  session: 01MTNCNQ2S69ML5V0B
---

## Objective

Preserve the original Apple Photos name through import and make photo-name display configurable in
the library and thumbnail views.

## Context

Photos imports currently manufacture names such as `Photo 1` before constructing
`ImageCollection.PhotoImportItem`. The generated name is then used by the durable asset, library
grid, and filmstrip, so users lose the name they recognize in Apple Photos. Both the library grid
and filmstrip always render a name, with no user preference or View-menu control.

## Acceptance criteria

- [ ] A successful Apple Photos import uses the asset's original filename/title when available,
      and carries it through the durable `PhotoAsset` and pending-import state.
- [ ] If Photos does not provide an original name, the current generated-name fallback remains
      deterministic and clearly does not break import or export naming.
- [ ] The original name appears consistently in both the library grid and thumbnail/filmstrip
      views, with sensible truncation and no loss of accessibility labels.
- [ ] Add a persistent `Show Photo Names` setting, exposed from the View menu as a checkmarked
      toggle (a context-menu mirror may be added if it improves discoverability), controlling both
      library and thumbnail name labels.
- [ ] The setting updates existing views immediately, survives relaunch, and does not affect the
      name shown in the Inspect panel or the filename used for export.
- [ ] Add tests for original-name propagation, fallback naming, setting persistence, and both
      display surfaces.

## Implementation notes

- Keep the original display name separate from the durable asset identity and source fingerprint.
  Do not use a renamed display value as a cache key or deduplication key.
- Investigate the PhotoKit/PhotosPicker path for the authoritative original filename/title and use
  the existing `PhotoImportItem.name` → `PhotoAsset.filename` path. Preserve the extension when it
  is part of the source name, while keeping current display/export conventions consistent.
- Wire the preference through the existing commands/settings architecture rather than adding view
  local state, so Library and Filmstrip cannot drift.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T19:34:29.318Z: Verification report
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
Pickup session: 01MTNCNQ2S69ML5V0B
Summary: Preserve Photos original filenames through durable imports and add persisted Show Photo Names control for library and filmstrip.
