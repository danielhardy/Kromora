---
id: KRMA-394
title: "Phase 0.1: deterministic synthetic-library generator (1k/10k/100k)"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Generating the same scale size twice with the same seed produces identical output (same file count, same per-asset metadata, same byte layout).
      result: pass
      notes: testSameScaleAndSeedProducesIdenticalValuesAndFileLayout compares full asset value arrays and a byte-for-byte file manifest across two independent generations at 1,000 assets; passes.
    - criterion: All three scale sizes (1,000 / 10,000 / 100,000) can be generated and torn down within a single test run without leaking files outside a temp directory.
      result: pass
      notes: 1k/10k covered in the fast lane (testSupportedFastScalesGenerateExpectedFileCountsAndTearDown); 100k covered by the optional-lane SyntheticLibraryGeneratorPerformanceTests, correctly gated in scripts/ci-tests.sh optional_filter. All generated roots live under a caller-supplied temp parent and are removed via GeneratedLibrary.cleanup().
    - criterion: Cancellation mid-generation stops promptly and leaves no partial state behind.
      result: pass
      notes: "testCancellationRemovesPartialLibrary cancels a 10k-asset generation after one yield (yieldEvery: 1); generate() catches the thrown CancellationError, removes its uniquely-owned root, and rethrows. Test asserts the parent directory is empty afterward."
    - criterion: Unit tests cover determinism, the three scale sizes (100,000 in the optional/benchmark lane), and cancellation.
      result: pass
      notes: SyntheticLibraryGeneratorTests + SyntheticLibraryGeneratorPerformanceTests cover all of determinism, metadata/edit/thumbnail-demand shape, fast-lane scales, withLibrary cleanup, cancellation, and the gated 100k lane.
    - criterion: swift build, swift test (fast lane), dg validate, and git diff --check pass.
      result: pass
      notes: "Re-ran independently: swift build clean; scripts/ci-tests.sh fast (930/930 tests passing, including the 5 SyntheticLibraryGeneratorTests); dg validate OK (pre-existing unrelated model-name warnings only); git diff --check on the KRMA-394 commit (d4ef55b) clean."
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast (930 tests, 0 failures)
    - swift test --filter SyntheticLibraryGeneratorTests (5 tests, 0 failures)
    - dg validate
    - git show d4ef55b | git diff --check
    - git status --porcelain (no leaked temp artifacts from generator runs)
  findings:
    - "Low-severity, non-blocking performance nit in Tests/KromoraKitTests/Support/SyntheticLibraryGenerator.swift: cameraIndex(for:seed:) is computed twice per asset (once directly in buildAssets for the JPEG-payload cache key, once again inside metadata(for:seed:)), each call constructing a fresh SeededGenerator and burning an RNG step. Correctness/determinism/cancellation are unaffected; matters most at the 100k scale. Filed as child ticket KRMA-416 (label verification, parent KRMA-394) rather than fixed inline."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T20:13:02.458Z
  session: 01MTYTKDEUKB3CEV3Z
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - performance
  - benchmark
created: 2026-09-12T19:44:09.110Z
updated: 2026-09-12T20:13:02.460Z
order: a0
board: product
---

## Objective

Build the deterministic synthetic-library generator that every later Phase 0–3 measurement and
regression test depends on. Nothing in this ticket touches product code, current library data, or
package APIs — it is a throwaway/spike-lane test utility.

## Context

KRMA-389 (Phase 0) requires committed baselines at 1,000 / 10,000 / 100,000 assets before any
identity or persistence work starts (KRMA-390+). Those baselines and the packed-thumbnail spike both
need the same generator, so it must land first and be reusable by both.

## Scope

- Add a generator (e.g. `Tests/KromoraKitTests/Support/SyntheticLibraryGenerator.swift` or a
  benchmark-lane target — follow the existing fixture pattern in `Tests/KromoraKitTests/Fixtures.swift`,
  which builds fixtures into a temp dir and commits nothing).
- Support exactly three deterministic scale sizes: 1,000, 10,000, and 100,000 assets, driven by a
  fixed seed so repeated runs produce byte-identical layouts.
- Each generated asset needs plausible metadata (capture date, camera/lens tags, orientation),
  an edit summary (a subset with non-default develop settings), and thumbnail demand (a subset
  flagged as needing thumbnail generation) — enough variety to exercise filtering/sorting/thumbnail
  code paths in later phases, without requiring real RAW/JPEG bytes.
- The generator must be cancellable mid-run (surface a `Task`-cancellation check or equivalent) and
  must clean up after itself — no synthetic assets, thumbnails, or metadata may be committed to the
  repository or left behind in a shared location.
- Do not import or reference any not-yet-existing package APIs (manifest, shards, UUID identity
  types from KRMA-390/391) — the generator produces data shaped for the *current* folder-backed
  model, since it is used to baseline that model in KRMA-389's next sibling ticket.

## Acceptance criteria

- [ ] Generating the same scale size twice with the same seed produces identical output (same file
  count, same per-asset metadata, same byte layout where applicable).
- [ ] All three scale sizes (1,000 / 10,000 / 100,000) can be generated and torn down within a single
  test run without leaking files outside a temp directory.
- [ ] Cancellation mid-generation stops promptly and leaves no partial state behind.
- [ ] Unit tests cover determinism, the three scale sizes (100,000 may run only in the optional/
  benchmark lane per `scripts/ci-tests.sh`), and cancellation.
- [ ] `swift build`, `swift test` (fast lane), `dg validate`, and `git diff --check` pass.

## Verification lane

Deterministic unit-test lane (`scripts/ci-tests.sh fast`) for generation logic and cancellation;
100,000-asset generation itself runs only under `scripts/ci-tests.sh optional`.

## Context

- context.files: Tests/KromoraKitTests/Fixtures.swift, docs/LIBRARY_PACKAGE_PLAN.md
- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/TESTING.md
- context.issues: KRMA-389


### Comment — codex @ 2026-09-12T20:09:57.303Z

Implemented in d4ef55b. Added a cancellable deterministic synthetic-library generator for 1k/10k/100k disposable folder-backed JPEG libraries with seeded metadata, EXIF orientation/camera/lens/date tags, current EditDocument summaries, thumbnail demand, automatic operation cleanup, and partial-root cleanup on cancellation/errors. Added determinism, metadata-shape, scale teardown, cleanup, and cancellation tests; assigned the 100k all-scale test to the optional CI lane. Verification: scripts/ci-tests.sh verify; scripts/ci-tests.sh fast (930 tests, no failures); focused generator tests; optional all-scale generator run with KROMORA_SYNTHETIC_LIBRARY_BENCHMARK=1 (1k/10k/100k passed); swift build; swift build -c release; dg validate; git diff --check. Release build retains only existing Core Image deprecation warnings.

## Agent log

- 2026-09-12T20:13:02.458Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Generating the same scale size twice with the same seed produces identical output (same file count, same per-asset metadata, same byte layout). (pass) — testSameScaleAndSeedProducesIdenticalValuesAndFileLayout compares full asset value arrays and a byte-for-byte file manifest across two independent generations at 1,000 assets; passes.
- [x] All three scale sizes (1,000 / 10,000 / 100,000) can be generated and torn down within a single test run without leaking files outside a temp directory. (pass) — 1k/10k covered in the fast lane (testSupportedFastScalesGenerateExpectedFileCountsAndTearDown); 100k covered by the optional-lane SyntheticLibraryGeneratorPerformanceTests, correctly gated in scripts/ci-tests.sh optional_filter. All generated roots live under a caller-supplied temp parent and are removed via GeneratedLibrary.cleanup().
- [x] Cancellation mid-generation stops promptly and leaves no partial state behind. (pass) — testCancellationRemovesPartialLibrary cancels a 10k-asset generation after one yield (yieldEvery: 1); generate() catches the thrown CancellationError, removes its uniquely-owned root, and rethrows. Test asserts the parent directory is empty afterward.
- [x] Unit tests cover determinism, the three scale sizes (100,000 in the optional/benchmark lane), and cancellation. (pass) — SyntheticLibraryGeneratorTests + SyntheticLibraryGeneratorPerformanceTests cover all of determinism, metadata/edit/thumbnail-demand shape, fast-lane scales, withLibrary cleanup, cancellation, and the gated 100k lane.
- [x] swift build, swift test (fast lane), dg validate, and git diff --check pass. (pass) — Re-ran independently: swift build clean; scripts/ci-tests.sh fast (930/930 tests passing, including the 5 SyntheticLibraryGeneratorTests); dg validate OK (pre-existing unrelated model-name warnings only); git diff --check on the KRMA-394 commit (d4ef55b) clean.
Checks run:
- swift build
- scripts/ci-tests.sh fast (930 tests, 0 failures)
- swift test --filter SyntheticLibraryGeneratorTests (5 tests, 0 failures)
- dg validate
- git show d4ef55b | git diff --check
- git status --porcelain (no leaked temp artifacts from generator runs)
Findings:
- Low-severity, non-blocking performance nit in Tests/KromoraKitTests/Support/SyntheticLibraryGenerator.swift: cameraIndex(for:seed:) is computed twice per asset (once directly in buildAssets for the JPEG-payload cache key, once again inside metadata(for:seed:)), each call constructing a fresh SeededGenerator and burning an RNG step. Correctness/determinism/cancellation are unaffected; matters most at the 100k scale. Filed as child ticket KRMA-416 (label verification, parent KRMA-394) rather than fixed inline.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYTKDEUKB3CEV3Z
Summary: Verified: deterministic synthetic-library generator (1k/10k/100k) meets all acceptance criteria. Fast lane (930 tests) and focused generator tests pass, dg validate and git diff --check are clean, and the 100k lane is correctly gated to scripts/ci-tests.sh optional. One low-severity, non-blocking performance nit (duplicated cameraIndex RNG derivation) filed as child ticket KRMA-416.
