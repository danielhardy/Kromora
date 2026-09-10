---
id: KRMA-233
title: Duplicate background-mask composition path left dead in VisionSemanticMaskProvider
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Decide whether VisionSemanticMaskProvider background composition is needed and document the caller
      result: pass
    - criterion: Background masks still resolve, cache, and invert identically through the coordinator
      result: pass
    - criterion: swift build and swift test continue to pass
      result: pass
  checks_run:
    - swift build (passes)
    - swift test --filter VisionSemanticMaskProviderTests (5 passed, 0 failures)
    - swift test (882 passed, 42 skipped, 0 failures)
    - git diff --check (passes)
    - dg validate (OK; pre-existing pickup-runner model warning only)
  findings: []
  fixes: []
  verification_commits:
    - 6f7327d
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T02:48:56.529Z
  session: 01MTP7KPP4SD6UR6VJ
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - masking
  - rendering
created: 2026-09-05T14:58:51.848Z
updated: 2026-09-10T12:53:49.239Z
parent: KRMA-224
depends_on:
  - KRMA-224
order: n6mgpca5
board: product
commits:
  - 6f7327d
---

## Objective

Consolidate background-mask composition onto a single live path, or explicitly document why two
equivalent implementations remain.

## Context

KRMA-224 gave `PhotoAnalysisCoordinator.performMask` (`PhotoAnalysisCoordinator.swift`) its own
special case for `kind == .background`: it fetches the Foreground union through the coordinator's
`mask(...)` entry point, inverts those pixels, and caches the result under a background cache key —
all before ever reaching the provider. Because `PhotoAnalysisCoordinator.mask(...)` is the only
production call path into mask generation, this coordinator-level composition now runs for every
real background request.

`VisionSemanticMaskProvider.mask(kind:...)` still has its own `.background` case
(`VisionSemanticMaskProvider.swift`, the `backgroundMask` composition that unions foreground
instances and inverts them), which was updated in the same commit to reuse the new
`foregroundUnionMask` helper. That method is no longer reachable from the app: any real caller goes
through the coordinator, which never forwards `.background` requests down to
`performMask(image:kind:quality:)`. The only remaining caller is
`VisionSemanticMaskProviderTests.testNoForegroundIsEmptyAndBackgroundIsItsComplement`, which invokes
`provider.mask(kind:)` directly and bypasses the coordinator entirely.

This isn't a functional bug — both paths compute the same "invert of the foreground union" result —
but it is a second, independently maintained implementation of the same composition that KRMA-224's
own implementation notes said to avoid ("do not create a parallel Vision/cache path"). A future edit
to one composition (e.g. a feather/threshold tweak) could silently diverge from the other without
any test catching it, since production traffic only ever exercises the coordinator's copy.

## Acceptance criteria

- [ ] Decide whether `VisionSemanticMaskProvider`'s `.background` case should be removed (with the
      test updated to exercise the coordinator-level path instead) or whether the provider-level
      path is still needed for some caller — and if so, document that caller.
- [ ] If removed, confirm no behavior change: background masks still resolve, cache, and invert
      identically through the coordinator.
- [ ] `swift build` and `swift test` continue to pass.

## Implementation notes

<!-- Approach, constraints, links -->
Scope is narrow: this is a dead-code/duplication cleanup, not a request to change how background
masks are computed or cached.

### Comment — codex @ 2026-09-06T02:48:46.488Z

Decision: remove VisionSemanticMaskProvider's duplicate background composition. PhotoAnalysisCoordinator remains the sole background-mask owner because it controls foreground/background request de-duplication and shared cache identity. The provider now rejects direct .background requests, and the no-foreground complement/cache test exercises the coordinator path. Verification: swift build; swift test (882 passed, 42 skipped); dg validate (OK with the pre-existing pickup-runner model warning).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-06T02:48:56.530Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Decide whether VisionSemanticMaskProvider background composition is needed and document the caller (pass)
- [x] Background masks still resolve, cache, and invert identically through the coordinator (pass)
- [x] swift build and swift test continue to pass (pass)
Checks run:
- swift build (passes)
- swift test --filter VisionSemanticMaskProviderTests (5 passed, 0 failures)
- swift test (882 passed, 42 skipped, 0 failures)
- git diff --check (passes)
- dg validate (OK; pre-existing pickup-runner model warning only)
Findings:
- None
Fixes:
- None
Verification commits:
- 6f7327d
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTP7KPP4SD6UR6VJ
Summary: Removed the dead VisionSemanticMaskProvider background composition path. PhotoAnalysisCoordinator is now the sole owner of background inversion and caching; provider coverage was moved to the coordinator path and verifies complement plus cache reuse.
