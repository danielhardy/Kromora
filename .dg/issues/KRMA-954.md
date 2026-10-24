---
id: KRMA-954
title: "Plan: replace per-render JSON+SHA-256 edit-document hashing with structural keys"
type: task
status: done
priority: medium
human_review_required: false
model: opus
thinking: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: docs/RENDER_KEY_PLAN.md provides a window-independent measured baseline for plain, five-mask, and large five-mask documents.
      result: pass
      notes: The corrected release benchmark uses a real RenderEngine and no NSWindow. It records both warm and first-cache-miss digest costs; the large recipe measured 173.573 ms warm and 202.743 ms cold.
    - criterion: The plan selects and justifies one option, inventories persisted identities, and defines safe invalidation if a durable digest changes.
      result: pass
      notes: Option (c) is selected. docs/RENDER_KEY_PLAN.md lists durable identities and fences, preserves the current stable digest, and defines version/prefix invalidation for a future scheme change.
    - criterion: Three to six implementation child tickets exist with the required labels, parent, acceptance criteria, benchmark targets, and identity tests.
      result: pass
      notes: KRMA-1098 through KRMA-1102 are five children of KRMA-954 with release-readiness, should-fix, and performance labels. Their acceptance criteria retain the Hasher and fence rules and require before/after benchmark numbers and identity tests.
    - criterion: This planning ticket makes no production behavior change.
      result: pass
      notes: The verification fix changes only the optional benchmark, planning/testing documentation, and child-ticket baselines.
    - criterion: Additional review constraints are represented in the plan and child tickets.
      result: pass
      notes: The plan and children retain the large-brush baseline, stable durable digests, no persisted Hasher output, preserved source/Look/pipeline fences, and KRMA-963 texture-pooling boundary. KRMA-1101 now explicitly passes the component digest through LocalMaskResolveRequest.
  checks_run:
    - scripts/ci-tests.sh verify — passed, exit 0; 2829 tests assigned to disjoint required_fast=2019 and required_serial=748 lanes, optional=62.
    - "KROMORA_RENDER_KEY_BENCHMARK=1 swift test -c release --filter RenderKeyHashingBenchmark — passed, 1 test and 0 failures. Final M4 Pro/macOS 27.2 run: large recipe 19 warm digests / 173.573 ms, 24 cold digests / 202.743 ms, editHash 29.204 ms, warm engine 636.64 ms; plain warm digest 0.153 ms."
    - git diff --check — passed, exit 0.
    - Independent source review — checked RenderCacheHash call-site accounting, persisted-identity inventory, migration rule, fences, child labels/parents, and absence of production changes.
  findings:
    - The original benchmark comment called its 19-digest warm slider-tick set cache-missing and omitted the five DefaultLocalMaskResolver hashes on a first mask-payload miss. The warm baseline remained valid; the cold-request cost was underreported.
  fixes:
    - Updated Tests/KromoraKitTests/RenderKeyHashingBenchmark.swift to report 19-digest warm requests separately from 24-digest first-cache-miss requests.
    - Refreshed docs/RENDER_KEY_PLAN.md, docs/TESTING.md, and KRMA-1098 through KRMA-1102 with the verified warm/cold baseline.
    - Clarified KRMA-1101 to pass the memoized component digest through LocalMaskResolveRequest for resolver payload identity and validation.
  verification_commits:
    - 0a8e662e99586792745a915e30083b4fde9027f5
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-24T15:22:42.709Z
  session: 01MVMJAULR61RZ2HAM
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - performance
  - render
  - needs-decomposition
created: 2026-10-13T14:48:04.666Z
updated: 2026-10-24T15:22:42.712Z
parent: KRMA-922
blockers: []
order: zzq
board: product
context:
  files: []
  docs:
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
  commands: []
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-24T14:24:24.502Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 0a8e662e99586792745a915e30083b4fde9027f5
---

## Objective

Produce a measured, staged plan (and child tickets) to stop JSON-encoding and SHA-256-hashing the edit
document, mask recipes and RAW-develop settings several times per render request.

> **Sizing note:** this ticket is a planning/investigation step. It is deliberately NOT an implementation ticket; its deliverable is a written plan plus child tickets small enough for a lower-capability agent. Label `needs-decomposition`.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S10.

- `Sources/KromoraKit/Models/RenderCacheKey.swift` ~L157 `RenderCacheHash.digest<T: Encodable>(_:)`
  JSON-encodes with `.sortedKeys` then SHA-256s.
- Call sites on the render path, `Sources/KromoraKit/Models/RenderEngine.swift`: L214-215
  (`maskIdentity`, `documentIdentity`), L1636, L2224, L2290/2295, L2424, L2603, L2787 (`documentHash`),
  plus `LocalMaskRendering.swift:227,283`, `RenderPipeline.swift:1023`, `CubeLUT.swift:103`.
- With brush masks this is several ms per slider tick on the render actor.
- Options to evaluate: (a) a revision counter on `EditDocument` sub-structs bumped on mutation and used
  as the key (needs a single mutation choke point), (b) synthesized `Hashable` keys hashed once per
  request and memoized, (c) hash only changed components and combine.
- Cache keys are persisted in places (frame store, thumbnail identity); changing the hash scheme must
  invalidate or version them (see `LatestPreviewFrameStore`, `ThumbnailFrameStore`, KRMA-761/764).

## Acceptance criteria

- [ ] `docs/RENDER_KEY_PLAN.md` (new) with a measured baseline from a window-independent test/benchmark
      (real `RenderEngine`, no `NSWindow`; see `docs/TESTING.md` for how existing render benchmarks are
      done) of time spent in `RenderCacheHash.digest` per request for (1) a plain document, (2) a
      document with 5 brush masks. Report numbers.
- [ ] The plan picks one option with justification, lists every persisted key that must be versioned,
      and defines the migration so old cached frames are discarded safely.
- [ ] 3-6 child tickets (`dg issue create`, label `release-readiness,should-fix,performance`) with
      acceptance criteria incl. a before/after number from the same benchmark and a unit test that
      equal documents produce equal keys and any edit changes the key.
- [ ] No production behavior change in this ticket (the benchmark may be added under `Tests/` as an
      opt-in method; follow how other benchmarks are gated).

## 2026-10-14 review

Finding 11 tightens this plan. Re-read `RenderCacheKey.swift` around line 155 and `RenderEngine.swift` around lines 214, 2285, and 2766; line numbers drift.

Required constraints for the plan and its children:

- Compute immutable identity once per relevant mutation. Do not JSON-encode and hash the whole document on every repeated interaction.
- Session-local caches may use revision or structural keys. Durable cross-launch identity keeps a stable digest.
- Do not persist Swift's randomized `Hasher` output.
- Do not remove source, Look, or pipeline-version fences.
- The baseline must include a large brush/mask recipe. A neutral document hides this cost.
- Texture pooling is not this ticket. It is KRMA-963, and it is blocked on GPU-completion ownership.

Epic KRMA-994 tracks the finding. This issue stays a child of KRMA-922.

## Additional acceptance criteria

- [ ] `docs/RENDER_KEY_PLAN.md` includes the constraints above, and the benchmark reports the large-recipe number beside the plain-document number.
- [ ] Child tickets repeat the fence and `Hasher` rules in their acceptance criteria.


### Comment — claude @ 2026-10-24T14:24:24.163Z

Plan and baseline in docs/RENDER_KEY_PLAN.md (commit 960f3691). The opt-in benchmark Tests/KromoraKitTests/RenderKeyHashingBenchmark.swift uses a real RenderEngine and no window, and is in the optional lane (KROMORA_RENDER_KEY_BENCHMARK=1 swift test -c release --filter RenderKeyHashingBenchmark). Release, M4 Pro, macOS 27.2: plain document 0.15 ms of digest per request and 0.05 ms per editHash; 5 brush masks (480 samples) 4.7 ms; large 5-brush recipe (20,480 samples) 170.9 ms per request, 27% of a 626 ms render-actor tick, and 28.7 ms per main-actor editHash. Main-actor editHash runs at least 3 times per tick (markingManualEdits twice, presentAdjustedFrame once). Decision: option (c). Durable editHash stays byte-identical, so no persisted identity is versioned and no stored frame, revision, or cache is invalidated; it is computed once per document value. Session caches move to a RenderDocumentIdentity of component digests, reused by == against a memo (< 0.01 us on shared storage, 15 us for a deep compare). The plan lists every persisted identity and the migration rule if one ever changes. Children: KRMA-1098, 1099, 1100 (ready); KRMA-1101 (depends on 1100) and KRMA-1102 (depends on 1101). Each repeats the fence and Hasher rules and requires before/after benchmark numbers and an equal-keys/edit-changes-key test. No production behavior change. Checks: scripts/ci-tests.sh verify (lanes disjoint, benchmark is optional); the benchmark skips by default in debug and passes opted in, in release.

## Agent log

- 2026-10-24T15:22:42.709Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] docs/RENDER_KEY_PLAN.md provides a window-independent measured baseline for plain, five-mask, and large five-mask documents. (pass) — The corrected release benchmark uses a real RenderEngine and no NSWindow. It records both warm and first-cache-miss digest costs; the large recipe measured 173.573 ms warm and 202.743 ms cold.
- [x] The plan selects and justifies one option, inventories persisted identities, and defines safe invalidation if a durable digest changes. (pass) — Option (c) is selected. docs/RENDER_KEY_PLAN.md lists durable identities and fences, preserves the current stable digest, and defines version/prefix invalidation for a future scheme change.
- [x] Three to six implementation child tickets exist with the required labels, parent, acceptance criteria, benchmark targets, and identity tests. (pass) — KRMA-1098 through KRMA-1102 are five children of KRMA-954 with release-readiness, should-fix, and performance labels. Their acceptance criteria retain the Hasher and fence rules and require before/after benchmark numbers and identity tests.
- [x] This planning ticket makes no production behavior change. (pass) — The verification fix changes only the optional benchmark, planning/testing documentation, and child-ticket baselines.
- [x] Additional review constraints are represented in the plan and child tickets. (pass) — The plan and children retain the large-brush baseline, stable durable digests, no persisted Hasher output, preserved source/Look/pipeline fences, and KRMA-963 texture-pooling boundary. KRMA-1101 now explicitly passes the component digest through LocalMaskResolveRequest.
Checks run:
- scripts/ci-tests.sh verify — passed, exit 0; 2829 tests assigned to disjoint required_fast=2019 and required_serial=748 lanes, optional=62.
- KROMORA_RENDER_KEY_BENCHMARK=1 swift test -c release --filter RenderKeyHashingBenchmark — passed, 1 test and 0 failures. Final M4 Pro/macOS 27.2 run: large recipe 19 warm digests / 173.573 ms, 24 cold digests / 202.743 ms, editHash 29.204 ms, warm engine 636.64 ms; plain warm digest 0.153 ms.
- git diff --check — passed, exit 0.
- Independent source review — checked RenderCacheHash call-site accounting, persisted-identity inventory, migration rule, fences, child labels/parents, and absence of production changes.
Findings:
- The original benchmark comment called its 19-digest warm slider-tick set cache-missing and omitted the five DefaultLocalMaskResolver hashes on a first mask-payload miss. The warm baseline remained valid; the cold-request cost was underreported.
Fixes:
- Updated Tests/KromoraKitTests/RenderKeyHashingBenchmark.swift to report 19-digest warm requests separately from 24-digest first-cache-miss requests.
- Refreshed docs/RENDER_KEY_PLAN.md, docs/TESTING.md, and KRMA-1098 through KRMA-1102 with the verified warm/cold baseline.
- Clarified KRMA-1101 to pass the memoized component digest through LocalMaskResolveRequest for resolver payload identity and validation.
Verification commits:
- 0a8e662e99586792745a915e30083b4fde9027f5
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MVMJAULR61RZ2HAM
Summary: Verification passed; corrected warm/cold render-key benchmark accounting and refreshed the plan baselines.
