---
id: KRMA-729
title: Fence photo transitions and instrument same-asset first-frame latency
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: No A drawable retained/submitted after B selected; late A results rejected
      result: pass
      notes: previewSurface.clear() runs synchronously before suspension; publication paths gated by publicationAcceptsFrame on asset/identity/generation.
    - criterion: B edited thumbnail, then original, embedded only if no candidate
      result: pass
      notes: Covered by testSelectionPresentsItsEditedThumbnailBeforeItsOriginal and session candidate ordering.
    - criterion: No extra hop from later embedded JPEG
      result: pass
      notes: Embedded admission requires candidateSource == nil.
    - criterion: Provisional pixels stay outside publication tail
      result: pass
      notes: Provisional path does not touch lastPublishedVisibleRequest, scopes, cache or previewState.
    - criterion: Confirmed frames still route through PreviewPublicationCoordinator
      result: pass
    - criterion: Rapid A->B->A stays bounded, no obsolete publication
      result: pass
      notes: SourceSessionCoordinator untouched; rapid-change lifecycle test passes.
    - criterion: Deterministic tests for ordering, suppression, failure, late completions
      result: pass
    - criterion: Observability without paths or image content
      result: pass
      notes: Signposts log SHA-256-truncated opaque tokens only.
  checks_run:
    - swift test focused suites (36 tests, 1 opt-in skip, 0 failures)
    - scripts/ci-tests.sh fast (exit 0)
    - git diff --check
    - dg validate (only unrelated model-name warnings)
    - serial lane not rerun; implementer reported an unrelated MenuCommandTests.swift:91 failure
  findings:
    - "Minor non-blocking: presentation generation is predicted as sourceRevision+1 before sourceSession.begin; correct today but couples to begin incrementing exactly once."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-30T16:38:59.679Z
  session: 01MUOBSDX0H0GPMAB5
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - performance
  - reliability
  - preview
created: 2026-09-30T13:19:18.309Z
updated: 2026-09-30T16:38:59.681Z
blockers: []
estimate: 5
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/ViewModels/SourceSessionCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewPublicationCoordinator.swift
    - Sources/KromoraKit/Views/PreviewSurface.swift
    - Sources/KromoraKit/Models/ImageCollection.swift
    - Tests/KromoraKitTests/EmbeddedFirstFrameTests.swift
    - Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift
  docs:
    - .context/last-known-frame-plan.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
    - docs/TESTING.md
  issues: []
  commands:
    - swift test --filter 'EmbeddedFirstFrameTests|ThumbnailSwitchLifecycleTests|PreviewPublicationCoordinatorTests'
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - git diff --check
    - dg validate
---

## Objective

Make source changes incapable of displaying the previous asset after the new selection is accepted,
and establish the presentation-session state and measurements that later persistent-frame work will
use.

## Read this first

The reviewed architecture is `.context/last-known-frame-plan.md`. Implement Phase 1 only. Do not add
a disk store or preserve the old photo as a fallback.

Today `AppViewModel.load` deliberately leaves the last `PreviewSurface` frame under the loading
indicator. After B is selected, A remains visible until B's embedded camera JPEG or settled render
arrives. `SourceSessionCoordinator` already tags work with source revision, but the visible surface
does not represent target-asset ownership while loading.

Create an explicit, asset-scoped presentation session owned by
`PreviewPresentationCoordinator` (or an equally narrow presentation owner), with asset ID,
`PortablePhotoIdentity`, generation, and provisional/confirmed state. `AppViewModel` should only
wire it. Every candidate/publication must prove it belongs to the active session.

On selection, synchronously fence or clear old pixels before any suspension. Then offer only B's
already-materialized edited thumbnail, B's original thumbnail, or a neutral canvas. The embedded RAW
JPEG remains a first-ever fallback, but `presentEmbeddedFirstFrame` must drop it once any B candidate
has been presented. A provisional candidate must remain outside normal render publication: it cannot
set `lastPublishedVisibleRequest`, admit histogram/scopes/comparison, enable pixel-dependent tools,
or cause a cache write.

Preserve the existing newest-pending preparation bound in `SourceSessionCoordinator`. Do not cancel
framework work in a way that creates one non-cancellable RAW decode per click.

## Required implementation

1. Add value state for a presentation session and candidate source (`editedThumbnail`,
   `originalThumbnail`, `embeddedJPEG`, `rendered`) with a monotonic generation.
2. Start/reset it in the existing source-change path before `sourceSession.begin`.
3. Add one guarded provisional-presentation entry point. It must require active asset, identity, and
   generation and must not call the confirmed publication tail.
4. Change embedded-frame admission to check whether the active session already has same-asset
   pixels, rather than relying only on `previewState` and `hasPublishedFrame`.
5. Preserve a same-asset provisional frame if the renderer fails, while publishing the existing
   actionable error. Never restore the prior asset.
6. Add signposts/counters for selection-to-first-same-asset-pixel, candidate source, distinct frame
   count, selection-to-confirmed-frame, and stale-generation drops. Log opaque IDs only.
7. Keep Reduce Motion and transition animation out of this ticket; later work owns refinement.

## Acceptance criteria

- [ ] After B is selected, no drawable request belonging to A is submitted or retained as B's
      loading content. A late A thumbnail, embedded frame, cache result, or render is rejected.
- [ ] B uses its own edited thumbnail first when available, then its original thumbnail; the
      embedded JPEG is admitted only when no B candidate exists.
- [ ] Once any B candidate is visible, a later embedded JPEG cannot create an extra hop.
- [ ] Provisional pixels do not update `lastPublishedVisibleRequest`, histogram, scopes,
      comparison, pixel tools, or persistent-cache writes.
- [ ] Exact existing confirmed-frame behavior remains routed through
      `PreviewPublicationCoordinator` and admits supporting work once.
- [ ] Rapid A -> B -> A navigation remains bounded to current preparation plus one pending request
      and never publishes an obsolete completion.
- [ ] Deterministic tests cover candidate ordering, embedded suppression, renderer failure, and
      late completions. Presentation-order integration coverage asserts same-asset candidate ->
      confirmed render with no cross-asset frame.
- [ ] Observability can report first-same-asset and confirmed latency plus distinct-frame count
      without paths or image content.

## Guardrails

- Keep `CIImage`/`CGImage` transfer within existing Swift 6 boundaries; do not add concurrency
  escape hatches.
- Do not make a thumbnail authoritative or mark `previewState` ready from a provisional frame.
- Do not broaden this into persistent preview or thumbnail storage.
- Preserve package-backed identity; URL equality is not an adequate source fence.

### Comment — codex @ 2026-09-30T16:34:10.648Z

Implemented asset-scoped presentation sessions, synchronous source fencing, same-asset edited/original thumbnail candidates, embedded-JPEG suppression, guarded render publication, and first/confirmed-frame signpost metrics. Added candidate ordering, stale generation, renderer failure, and navigation regression coverage. Checks: focused preview/thumbnail suites passed (36 tests, 1 opt-in skip); fast CI passed; dg validate and git diff --check passed. The serial CI lane ran 452 tests and reproduced one unrelated failure at MenuCommandTests.swift:91.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-30T16:38:59.679Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] No A drawable retained/submitted after B selected; late A results rejected (pass) — previewSurface.clear() runs synchronously before suspension; publication paths gated by publicationAcceptsFrame on asset/identity/generation.
- [x] B edited thumbnail, then original, embedded only if no candidate (pass) — Covered by testSelectionPresentsItsEditedThumbnailBeforeItsOriginal and session candidate ordering.
- [x] No extra hop from later embedded JPEG (pass) — Embedded admission requires candidateSource == nil.
- [x] Provisional pixels stay outside publication tail (pass) — Provisional path does not touch lastPublishedVisibleRequest, scopes, cache or previewState.
- [x] Confirmed frames still route through PreviewPublicationCoordinator (pass)
- [x] Rapid A->B->A stays bounded, no obsolete publication (pass) — SourceSessionCoordinator untouched; rapid-change lifecycle test passes.
- [x] Deterministic tests for ordering, suppression, failure, late completions (pass)
- [x] Observability without paths or image content (pass) — Signposts log SHA-256-truncated opaque tokens only.
Checks run:
- swift test focused suites (36 tests, 1 opt-in skip, 0 failures)
- scripts/ci-tests.sh fast (exit 0)
- git diff --check
- dg validate (only unrelated model-name warnings)
- serial lane not rerun; implementer reported an unrelated MenuCommandTests.swift:91 failure
Findings:
- Minor non-blocking: presentation generation is predicted as sourceRevision+1 before sourceSession.begin; correct today but couples to begin incrementing exactly once.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUOBSDX0H0GPMAB5
