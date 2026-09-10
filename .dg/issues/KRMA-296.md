---
id: KRMA-296
title: Thumbnail raster path without PNG encode and MainActor decode round-trip
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Badge job performs no PNG encode/decode
      result: pass
      notes: requestEditedThumbnail calls engine.makeThumbnailCGImage; RenderEngine overrides it with actor-local makeCGImage/CIContext.createCGImage, while renderThumbnail remains available for encoded-byte callers.
    - criterion: Thumbnail pixels remain unchanged at badge scale
      result: pass
      notes: Added testDirectThumbnailRasterMatchesEncodedThumbnail using the 256px thumbnail request and exact working-space inputs; direct and legacy encoded outputs match within the suite tolerance.
    - criterion: No MainActor decode work added
      result: pass
      notes: The scheduler receives a CGImage and constructs NSImage from that image; the former NSImage(data:) decode path is absent.
  checks_run:
    - swift test --filter RenderEngineTests (29 passed, 3 environment-dependent RAW skips)
    - swift test --filter ThumbnailSwitchLifecycleTests (9 passed)
    - git diff --check
    - dg validate
  findings: []
  fixes: []
  verification_commits:
    - ef9af97
    - d1e2096
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T01:46:47.801Z
  session: 01MTTFQ7TMP0BJ6MKI
labels:
  - performance
  - preview
  - thumbnails
created: 2026-09-08T23:48:31.610Z
updated: 2026-09-10T12:53:54.399Z
order: zv
board: product
commits:
  - d1e2096
  - ef9af97
---

## Objective

Cut the per-thumbnail CPU/MainActor overhead: no PNG encode plus MainActor decode round-trip for a 256px badge.

## Context

Parent: KRMA-289. The edited-thumbnail job calls engine.renderThumbnail (PNG bytes) then NSImage(data:) on the MainActor inside a MainActor scheduler operation (Sources/LumoKit/ViewModels/AppViewModel.swift requestEditedThumbnail). renderThumbnail delegates to render() (Sources/LumoKit/Models/RenderEngine.swift). For a badge this pays PNG encode on the actor and PNG decode on the main thread.

## Plan

- Add a small-raster path (e.g. a CGImage-returning thumbnail accessor reusing the makeCIImage/makeCGImage actor-local rasterizer at thumbnail scale) and construct NSImage from the CGImage off the critical path.
- Keep renderThumbnail for any caller that needs encoded bytes; this ticket only reroutes the badge job.
- Verify thumbnail pixels unchanged (same scale/space inputs) via existing thumbnail tests.

## Acceptance

- Badge job performs no PNG encode/decode; thumbnails pixel-match current output at badge scale.
- No MainActor decode work added; scheduler operation stays lean.

## Agent log

- 2026-09-09T01:46:47.802Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Badge job performs no PNG encode/decode (pass) — requestEditedThumbnail calls engine.makeThumbnailCGImage; RenderEngine overrides it with actor-local makeCGImage/CIContext.createCGImage, while renderThumbnail remains available for encoded-byte callers.
- [x] Thumbnail pixels remain unchanged at badge scale (pass) — Added testDirectThumbnailRasterMatchesEncodedThumbnail using the 256px thumbnail request and exact working-space inputs; direct and legacy encoded outputs match within the suite tolerance.
- [x] No MainActor decode work added (pass) — The scheduler receives a CGImage and constructs NSImage from that image; the former NSImage(data:) decode path is absent.
Checks run:
- swift test --filter RenderEngineTests (29 passed, 3 environment-dependent RAW skips)
- swift test --filter ThumbnailSwitchLifecycleTests (9 passed)
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- ef9af97
- d1e2096
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTTFQ7TMP0BJ6MKI
Summary: Direct actor-local thumbnail CGImage rasterization is in ef9af97; the badge job no longer uses PNG bytes, and d1e2096 adds direct-vs-encoded pixel parity coverage.
