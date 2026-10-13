---
id: KRMA-954
title: "Plan: replace per-render JSON+SHA-256 edit-document hashing with structural keys"
type: task
status: backlog
priority: medium
human_review_required: false
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
parent: KRMA-922
created: 2026-10-13T14:48:04.666Z
updated: 2026-10-13T14:48:22.153Z
blockers: []
order: zv
board: product
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
