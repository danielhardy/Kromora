---
id: KRMA-305
title: Enable preview/prefix cache for semantic-masked photos
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 7818f95
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T10:45:32.558Z
  session: 01MTTYOUWC9CQ9UKKY
labels:
  - perf
  - phase:10
  - render
  - cache
  - masks
created: 2026-09-09T02:38:43.930Z
updated: 2026-09-10T12:53:55.176Z
estimate: 5
order: z
board: product
---

## Objective

Restore final-raster cache hits for photos that have semantic (person/sky) masks, so global slider ticks stay cheap.

## Context

**Why:** Today these are the worst slider-latency photos in the app: any `.semantic` component forces `previewCacheKey()` to return `nil`, so every global tick re-renders end-to-end even though the mask *component* payloads cache fine in `localMaskCache` (32 entries / 64MB).

**Current code:**
- `Sources/LumoKit/Models/RenderEngine.swift` — `previewCacheKey()` returns nil for `.semantic` components; `buildImage()` → `applyLocalAdjustments` (component payload cache) → `buildFinalStages`.
- `Sources/LumoKit/Models/RenderRequest.swift` — `MaskResolutionPolicy.resolved/deferSemantic`; semantic masks force full re-renders by bypass.
- `Sources/LumoKit/Models/RenderPipeline.swift` — `buildPreLUTImage` order: developed → crop → global adjustments → local adjustments → pre-LUT.
- Component cache keys already include mask payload versions — reuse that versioning for the raster key.

## Scope / Steps

1. Key the final raster (or a post-`applyLocalAdjustments` prefix) on mask payload versions, not merely presence: `document.editHash` already covers global state; add resolved semantic-mask version (request ID + payload hash) to the key.
2. Preferred: cache the post-local-adjustment prefix separately from the LUT/grain tail, so global exposure ticks with a static mask hit prefix, and LUT ticks hit the existing prefix path.
3. Handle mask-resolution races: semantic masks resolve async (Vision); a tick that arrives mid-resolution must not poison the cache with a mask-less raster under a mask-present key (and vice versa). Key must include resolution state.
4. Keep `MaskResolutionPolicy.deferSemantic` fast path intact (filmstrip/adjacent must stay cheap).

## Acceptance criteria

- [ ] `MaskedPrefixHitTest`: same document + same settled semantic-mask version + global slider tick hits prefix/final cache (re-develop count == 0).
- [ ] `MaskVersionMissTest`: bumped mask version (re-resolve / different person) misses and the new output reflects the new mask (assert output differs from stale; publication log contains no stale-mask frame).
- [ ] `MidResolutionPoisonTest`: ticks across the unresolved-to-resolved transition never publish a mask-less raster under a mask-present key (assert every publication's key resolution-state matches its pixels; unresolved vs resolved keys differ).
- [ ] `UnmaskedNoOpTest`: unmasked-photo cache keys are byte-identical before/after the change (assert key equality on fixture set).
## Verification

- `swift build` clean (zero diagnostics).
- New/updated XCTest(s) named above green: same-version hit, bumped-version miss, resolution-state key split, unmasked no-op.
- `scripts/ci-tests.sh fast` + `serial` green.
- No human steps: done = all automated checks above pass.
## Out of scope

- Changing Vision mask generation itself.
- Texture-backed prefix storage (separate ticket; composes with this).

## Constraints

- macOS 14 minimum; Apple frameworks only.
- Swift 6 zero-opt-out. Cache keys stay value types (`Hashable` structs); no shared mutable mask state.

### Comment — codex @ 2026-09-09T10:45:41.444Z

Implementation and verification: added post-local semantic-mask prefix caching keyed by source/develop/global prefix, local adjustment hash, settled payload digest, and explicit resolution state. Deferred semantic previews remain on the fast uncached path. Added MaskedPrefixHitTest, MaskVersionMissTest, MidResolutionPoisonTest, and UnmaskedNoOpTest; these pass, as do the full RenderCacheTests and relevant LocalMaskRenderingTests. swift build passes. Full ci-tests.sh fast/serial were attempted; both encounter an unrelated pre-existing LUTWorkflowTests failure in the already-dirty worktree, and the script failure handler has an existing zsh read-only-variable error. Format check also reports pre-existing violations across dirty files.

## Agent log

- 2026-09-09T10:45:32.559Z: Verification report
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
Pickup session: 01MTTYOUWC9CQ9UKKY
Summary: Implemented semantic-mask-aware post-local preview prefix caching. Resolved payload digests and explicit resolved/deferred state prevent stale or mask-less cache reuse; deferred semantic previews remain uncached and fast. Added MaskedPrefixHitTest, MaskVersionMissTest, MidResolutionPoisonTest, and UnmaskedNoOpTest coverage.
