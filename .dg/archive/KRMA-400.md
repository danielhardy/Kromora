---
id: KRMA-400
title: "Phase 1.4: identity relocation/collision/stale-completion regression suite"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Full-library relocation (synthetic library moved to a new path/volume) preserves cache/edit identity end to end with no relink required, verified by an automated test.
      result: pass
      notes: testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore covers 1,000 assets, asserts byte-identical portable identities pre/post move, and reuses render cache, preview disk cache, mask store, and edit-store entries with status .ready (no relink) after relocation.
    - criterion: Collision and duplicate-detection tests pass for identity generation.
      result: pass
      notes: testDistinctSourcesDoNotCollideAndDuplicateDataImportsShareIdentity confirms duplicate byte-identical imports share identity, and two files with identical sampled fingerprint regions but differing full content resolve to distinct portable identities.
    - criterion: Stale-completion tests pass for render, mask, and preview pipelines.
      result: pass
      notes: testStaleMaskCompletionCannotPublishRenderOrThumbnailState covers render+thumbnail quality with a blocking mask resolver; testPreviewCompletionForRelocatedSourceCannotPublishOverCurrentSource covers the preview coordinator with a gated fake render engine.
    - criterion: This suite is registered as the standing regression gate referenced by later phase tickets (KRMA-391 onward) rather than a one-off.
      result: pass
      notes: IdentityRegressionGateTests is added to the required serial_filter in scripts/ci-tests.sh and given its own 'identity' lane; docs/TESTING.md documents it as the standing Phase 1 identity gate.
    - criterion: swift build, swift test (fast + serial), dg validate, and git diff --check pass.
      result: pass
      notes: "Independently re-ran: swift build (clean), scripts/ci-tests.sh fast (949/949), scripts/ci-tests.sh serial (375/375, includes identity gate), scripts/ci-tests.sh identity (4/4 standalone), dg validate --json (ok=true, only pre-existing unrelated unknown-model warnings), git diff --check (clean)."
  checks_run:
    - swift build
    - scripts/ci-tests.sh identity (4/4 passed)
    - scripts/ci-tests.sh fast (949/949 passed)
    - scripts/ci-tests.sh serial (375/375 passed)
    - dg validate --json
    - git diff --check
    - manual read-through of Tests/KromoraKitTests/IdentityRegressionGateTests.swift and the scripts/ci-tests.sh / docs/TESTING.md diff in commit d0d3060
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T09:32:53.316Z
  session: 01MTZM5PTMG3ZAGBO1
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - identity
  - performance
created: 2026-09-12T19:44:14.250Z
updated: 2026-09-13T09:32:53.318Z
depends_on:
  - KRMA-398
  - KRMA-399
order: a0
board: product
---

## Objective

Close out Phase 1 with the end-to-end regression suite that proves the new identity model holds
across relocation, collisions, cache invalidation, and stale completions — the acceptance bar KRMA-390
itself is measured against.

## Dependencies

- The cache-layer migration ticket and the persistence migration ticket (this exercises both
  together; do not start until they have landed).

## Scope

- Write integration-level tests that move/rename a synthetic library (using KRMA-389's generator)
  across simulated path and filesystem changes and assert byte-identical cache keys and no required
  relink, across render cache, mask store, preview cache, and edit persistence simultaneously.
- Add collision tests: two distinct sources that could plausibly hash-collide or share superficial
  metadata must still resolve to distinct identities; duplicate imports of the same content must be
  detected as the same identity, not silently duplicated.
- Add stale-completion tests: an in-flight async operation (render, thumbnail, mask) keyed to an
  identity that becomes invalid mid-flight must not corrupt state for the current valid identity.
- Wire these into the relocation benchmark gate established by KRMA-389 so this becomes the
  permanent regression gate for all subsequent phases.

## Acceptance criteria

- [ ] Full-library relocation (synthetic library moved to a new path/volume) preserves cache/edit
  identity end to end with no relink required, verified by an automated test.
- [ ] Collision and duplicate-detection tests pass for identity generation.
- [ ] Stale-completion tests pass for render, mask, and preview pipelines.
- [ ] This suite is registered as the standing regression gate referenced by later phase tickets
  (KRMA-391 onward) rather than a one-off.
- [ ] `swift build`, `swift test` (fast + serial), `dg validate`, and `git diff --check` pass.

## Verification lane

Identity/unit and render-cache regression lane, using the KRMA-389 generator at 1,000-asset scale for
speed; this is the gate KRMA-390's own acceptance criteria point to.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/TESTING.md
- context.issues: KRMA-390, KRMA-389


### Comment — codex @ 2026-09-13T09:30:19.780Z

Implemented in d0d3060: added IdentityRegressionGateTests covering 1,000-asset synthetic-library relocation with byte-identical portable identities and render/mask/preview/edit-store reuse, distinct-source collision resistance, duplicate-import identity reuse, and stale render/thumbnail/mask/preview completion suppression. Registered the gate in scripts/ci-tests.sh (serial plus dedicated identity lane) and documented it. Verification passed: swift build; scripts/ci-tests.sh fast (949/949); scripts/ci-tests.sh serial (375/375); scripts/ci-tests.sh identity (4/4); dg validate --json (ok, with pre-existing unknown-model warnings); git diff --check.

## Agent log

- 2026-09-13T09:32:53.316Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Full-library relocation (synthetic library moved to a new path/volume) preserves cache/edit identity end to end with no relink required, verified by an automated test. (pass) — testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore covers 1,000 assets, asserts byte-identical portable identities pre/post move, and reuses render cache, preview disk cache, mask store, and edit-store entries with status .ready (no relink) after relocation.
- [x] Collision and duplicate-detection tests pass for identity generation. (pass) — testDistinctSourcesDoNotCollideAndDuplicateDataImportsShareIdentity confirms duplicate byte-identical imports share identity, and two files with identical sampled fingerprint regions but differing full content resolve to distinct portable identities.
- [x] Stale-completion tests pass for render, mask, and preview pipelines. (pass) — testStaleMaskCompletionCannotPublishRenderOrThumbnailState covers render+thumbnail quality with a blocking mask resolver; testPreviewCompletionForRelocatedSourceCannotPublishOverCurrentSource covers the preview coordinator with a gated fake render engine.
- [x] This suite is registered as the standing regression gate referenced by later phase tickets (KRMA-391 onward) rather than a one-off. (pass) — IdentityRegressionGateTests is added to the required serial_filter in scripts/ci-tests.sh and given its own 'identity' lane; docs/TESTING.md documents it as the standing Phase 1 identity gate.
- [x] swift build, swift test (fast + serial), dg validate, and git diff --check pass. (pass) — Independently re-ran: swift build (clean), scripts/ci-tests.sh fast (949/949), scripts/ci-tests.sh serial (375/375, includes identity gate), scripts/ci-tests.sh identity (4/4 standalone), dg validate --json (ok=true, only pre-existing unrelated unknown-model warnings), git diff --check (clean).
Checks run:
- swift build
- scripts/ci-tests.sh identity (4/4 passed)
- scripts/ci-tests.sh fast (949/949 passed)
- scripts/ci-tests.sh serial (375/375 passed)
- dg validate --json
- git diff --check
- manual read-through of Tests/KromoraKitTests/IdentityRegressionGateTests.swift and the scripts/ci-tests.sh / docs/TESTING.md diff in commit d0d3060
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTZM5PTMG3ZAGBO1
Summary: Independently re-ran build/identity/fast/serial lanes plus dg validate and git diff --check; all acceptance criteria confirmed against the added IdentityRegressionGateTests suite. No blockers found.
