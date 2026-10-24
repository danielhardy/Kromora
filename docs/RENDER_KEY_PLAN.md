# Render identity plan: structural session keys, one durable digest

Status: plan (KRMA-954, finding S10 of the 2026-10-13 review, finding 11 of the 2026-10-14 review).
Epic: KRMA-994. This document describes work to be done; it is not current behavior. When the
child tickets land, move the durable rules into `docs/ENGINEERING_GUIDE.md` and trim this file to
history.

## Problem

`RenderCacheHash.digest<T: Encodable>(_:)` (`Sources/KromoraKit/Models/RenderCacheKey.swift`)
JSON-encodes a value with `.sortedKeys` and SHA-256-hashes the bytes. That is the only identity
function for edit state, so it runs again for every key that mentions the document:

- **Render actor, per warm request** (`RenderEngine`): `RenderBuildPlan.make` (`maskIdentity`, the
  whole-document `documentIdentity`), `previewCacheKey` (whole document again), the developed-source
  key and both processing-prefix keys (`rawDevelop`, three times), `prefixDocumentHash` (a synthetic
  copy of the document, twice), the post-local prefix (`localAdjustments`), and mask resolution plus
  composition (each usable component's `MaskSource`, twice per component). For a five-mask document
  that comes to 19 digests on each repeated exposure tick. On the first request, a cache miss also
  hashes each component once inside `DefaultLocalMaskResolver`, for 24 digests total; subsequent
  ticks hit the mask-payload cache and return to 19.
- **Main actor, per edit and per presented frame**: `EditDocument.markingManualEdits` computes
  `renderingHash` for the old and the new document on every `updateDocument`.
  `AppViewModel.presentAdjustedFrame` computes `editHash` for every presented frame.
  `PreviewPresentationCoordinator` computes it again for stored-frame classification and canonical
  writes, `LookPreviewCoordinator.CacheKey` once per Look-strip cell, and
  `EditedThumbnailCoordinator` once per thumbnail revision.

Each digest is linear in the size of the recipe. Brush samples dominate, because every sample
becomes a JSON object with three numbers.

## Measured baseline

`Tests/KromoraKitTests/RenderKeyHashingBenchmark.swift` is an optional-lane benchmark. It uses a
real `RenderEngine`, a 1600×1200 procedural PNG, and no `NSWindow`:

```sh
KROMORA_RENDER_KEY_BENCHMARK=1 swift test -c release --filter RenderKeyHashingBenchmark
```

The benchmark mirrors the digest inputs from the engine call sites without production
instrumentation. It measures the 19-digest warm request on each repeated exposure tick and the
additional five default-resolver hashes on a first mask-payload cache miss. It also times one
`editHash` and a 30-tick real-engine exposure drag. Layer, component and stroke IDs stay stable
across the drag, so the engine records 150 payload-cache hits and five misses while the preview
raster misses on every tick. Finally, it times the candidate replacement operations.

The table below is a verification run on Release, Apple M4 Pro, macOS 27.2, with 30 iterations and
medians. The engine timings below are warm-tick timings; the first five-mask cache miss is reflected
in the separate cold-digest column.

| Recipe | Brush samples | JSON bytes | Warm digests / request | Warm digest ms (p95) | Cold digests / request + ms | One `editHash` | Real-engine ms / request (p95) | Warm digest share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Plain document (global Light + Color) | 0 | 1.9 KB | 6 | 0.153 (0.165) | 6 / 0.152 | 0.049 ms | 3.02 (3.64) | 5.1% |
| 5 brush masks, 2 strokes × 48 samples | 480 | 44 KB | 19 | 4.763 (4.990) | 24 / 5.483 | 0.810 ms | 168.62 (221.23) | 2.8% |
| **5 brush masks, 8 strokes × 512 samples (large recipe)** | 20,480 | 1.65 MB | 19 | **173.573 (176.063)** | **24 / 202.743** | **29.204 ms** | 636.64 (657.61) | **27.3%** |

Candidate replacement costs, measured on the large recipe:

| Operation | Cost |
| --- | ---: |
| `==` on unchanged `localAdjustments` after an exposure tick (shared array storage) | < 0.01 µs |
| `==` on equal `localAdjustments` with distinct storage (a decoded copy, or undo to an older value) | 15.0 µs |
| Digest of one small changed component (`LightAdjustments`) | 17.3 µs |

Reading the numbers:

- With the large recipe, warm identity costs 174 ms of the 637 ms the render actor spends on an
  exposure tick. Of the 19 warm digests, 14 are linear in the brush payload. The first request
  costs 203 ms across 24 digests because each component also gets hashed in the resolver.
- The main actor carries the same cost on every tick: at least two `renderingHash` calls in
  `markingManualEdits` and one `editHash` per presented frame, so ≥ 87.6 ms per tick with the large
  recipe. That is a dropped-frame problem independent of the render actor.
- A plain document is cheap (0.153 ms), so a neutral or global-only benchmark hides this cost
  entirely, as the review warned.
- The rest of the small-brush tick (≈ 164 ms) is local-layer compositing on the GPU, not identity.
  It is out of scope here.

## Constraints

These come from the 2026-10-14 review, and every child ticket repeats them in its acceptance
criteria.

1. **Compute immutable identity once per relevant mutation.** Do not JSON-encode and hash the whole
   document on every repeated interaction. An unchanged component (a mask recipe during an exposure
   drag) must not be re-encoded at all.
2. **Session-local caches may use revision or structural keys. Durable cross-launch identity keeps a
   stable digest.**
3. **Never persist Swift's randomized `Hasher` output.** `hashValue` and `Hasher` may back an
   in-memory `Dictionary` key and nothing else. They never go into a file, a frame signature, an
   edit revision, a diagnostic report, or a string that leaves the process.
4. **Do not remove source, Look, or pipeline-version fences.** `RenderSourceFingerprint`, the Look
   or LUT content fingerprint, `RenderPipeline.pixelEpoch`, `LocalMaskRenderer.version`,
   `RenderIdentity.current`, and `PresentationFrameEnvelope.storageFormatVersion` stay in every key
   that holds them today.
5. **Baselines include a large brush/mask recipe** beside the plain document. Use the benchmark
   above.
6. **Texture pooling is not part of this plan.** It belongs to KRMA-963, which is blocked on
   GPU-completion ownership.

## Options considered

**(a) Revision counter on `EditDocument` sub-structs.** Rejected. Documents reach the engine from
many owners: `AppViewModel.updateDocument`, undo and redo, stored-edit adoption, the Auto apply
path, thumbnail and idle-frame warmers, export, batch, and Derive. Several of those decode a
document from storage and never pass a mutation choke point. A counter is therefore only unique
per owner. Two owners sharing one `RenderEngine` would produce equal counters for different pixels,
which is a false cache hit. The counter would also give equal documents different keys, so undo
and re-open would always miss. Making it sound means namespacing every counter by owner, and then
the cross-owner sharing the caches exist for is lost.

**(b) Synthesized `Hashable` keys over the document tree.** Rejected as the key representation,
but adopted as a tool: the chosen design uses `Equatable`. The objections:

- Roughly 40 model types would need `Hashable`.
- A key would retain the full brush arrays in every bounded cache, which costs memory and makes
  cache cost accounting dishonest.
- `Hasher` re-walks every brush sample on every dictionary probe, and an equal key costs a second
  element-wise walk.
- The durable boundary would still need a digest, so (b) adds a second identity scheme and removes
  none.
- `CubeLUT`'s `==` compares IDs only, a trap for any "structural" key that reaches it.

**(c) Hash only changed components and combine.** Chosen. The plan below makes it concrete.

## Decision

There are two tiers of identity. Each has one owner and its own rules.

### Durable tier: the existing digest, unchanged bytes, computed at durable boundaries

`EditDocument.editHash` and `renderingHash` stay **byte-identical**: the same JSON with
`.sortedKeys`, SHA-256, and the same `lastAutoRunFingerprint` exclusion. What changes is when they
run:

- Equality checks stop hashing. `markingManualEdits` and `AutoWorkflowCoordinator` compare the
  Auto-stripped documents with `==`. `==` costs < 0.01 µs when the mask arrays are shared.
- Per-frame consumers use a session identity, not the durable digest. `PreviewFrameIdentity` is
  compared only in memory, by `PreviewSurface`, so it can hold the document value and compare it
  with `==`.
- The durable digest is computed **at most once per distinct document value**, by a memo, wherever
  it is still needed:
  - canonical preview frame writes and their classification,
  - edited-thumbnail frame signatures and the `EditedThumbnailCoordinator` revision string,
  - `LookPreviewCoordinator.CacheKey`,
  - the Auto fingerprint,
  - the current-edit measurement cache,
  - the Apple reference provenance.

  Where the consumer is already asynchronous (frame encoding, thumbnail rendering), the digest runs
  off the main actor on the `Sendable` document value. The memo is in memory only; it caches the
  durable string and never invents a new one.

Durable bytes do not change, so **no persisted identity changes in this plan, and no stored frame,
edit revision, or cache entry is invalidated.** That is deliberate. The persisted Auto fingerprint
lives inside users' edit revisions, and changing its scheme would mark every stored Auto result
stale.

### Session tier: `RenderDocumentIdentity`, component digests reused by equality

The render engine gets a `Sendable` value type, `RenderDocumentIdentity`, with one digest per
render-relevant component:

- `rawDevelop`,
- the processing-prefix upstream inputs (Light, Color, prefix Effects, ordered adjustments with and
  without the temperature/tint stage, Look settings, retouch),
- `localAdjustments`,
- the mask recipe,
- one definition digest per mask component, keyed by component ID.

It also holds a whole-document session key composed from those digests.

A bounded memo on `RenderEngine` builds the identity once at request entry. The memo keeps the last
few identities per `RenderSourceFingerprint`. For each component it compares the incoming value
with the remembered value using `==`. When they are equal it reuses the digest. Only a component
that differs is encoded and hashed. After an exposure tick, that means only the Light component, at
about 17 µs.

The identity is threaded through `RenderBuildPlan` and every cache key that currently calls
`RenderCacheHash.digest`, so the 19 warm-request digests and the five first-miss resolver digests
become field reads. Pass each component's definition digest in `LocalMaskResolveRequest`; the
default and semantic resolvers use that value for `LocalMaskPayload.definitionHash` and validation
instead of encoding the source again.

Rules for the session tier:

- Component digests remain deterministic SHA-256 strings. They are not `Hasher` output, so they are
  stable to compare across actors and carry no persistence hazard. Even so, they are **session-only
  by contract**: no persisted structure stores a `RenderDocumentIdentity` field.
  `RenderDocumentIdentity` is a distinct type, not a `String`, so it cannot be passed where a
  durable `editHash` is expected.
- Correctness never depends on the memo. A memo miss computes the same digest the slow path would
  have computed. The memo only saves work.
- Equality reuse assumes that no type reachable from `EditDocument` defines a custom `==` that
  ignores a pixel-affecting field. That holds today: the only custom `==` among render models is
  `CubeLUT`'s, which is not part of `EditDocument`. A test enforces the assumption.
- `-0.0 == 0.0` is acceptable because the pixels are identical. `NaN != NaN` makes the value
  re-hash every time, which is a miss, not a false hit. That matches today's `encoding-failed:<UUID>`
  behavior.
- Brush painting changes the brush component on every tick. Its digest is a combination of
  per-stroke digests, and committed strokes are reused by equality. Appending a sample therefore
  re-encodes one stroke, not the whole mask.

## Persisted identities

This is every identity that crosses a launch, with what versions it today. None of them changes in
this plan.

| Identity | Where it is stored | Derived from | Existing fence |
| --- | --- | --- | --- |
| `FrameSignature.editHash` (`preview2048`) | `LatestPreviewFrameStore` files | `EditDocument.editHash` | `pixelEpoch` in the signature; `PresentationFrameEnvelope.storageFormatVersion` |
| `FrameSignature.editHash` (`editedThumbnail480`) | `ThumbnailFrameStore` packs | `EditDocument.editHash` | same |
| `FrameSignature.editHash = "original"` (`originalThumbnail480`) | `ThumbnailFrameStore` | literal | same |
| `FrameSignature.look` (Look/LUT content) | both frame stores | `CubeLUT.contentHash` (digest of the cube table, once per load) | Look signature fields |
| `AutoRunFingerprint.documentHash` | inside `EditDocument.lastAutoRunFingerprint`, so in package edit revisions | `renderingHash` | `algorithmVersion`, `RenderIdentity.current` |
| `AutoRunFingerprint.digest` | diagnostics and reports | digest of the fingerprint | same |
| `CurrentEditMeasurementKey` effective and complete document hashes; `CurrentEditMeasurement.documentHash` | `CurrentEditMeasurement` cache directory | `editHash` | `CurrentEditMeasurement.version`, `measurementVersion` |
| `AppleReferenceProvenance.analysisDocumentHash` / `completeDocumentHash` | Auto provenance and reports | `editHash` | `AppleEnhancementReferenceAdapter.algorithmVersion` |
| Grain seed (`RenderPipeline` grain digest) | not a key; it is a pixel input | digest of the source fingerprint | `pixelEpoch` |

Session-only identities, which the children may change freely:

- `PreviewCacheKey`, `DevelopedSourceCacheKey`, `ProcessingPrefixCacheKey`, `LocalMaskCacheKey`,
  `MaskRasterCacheIdentity`;
- the RAW `OutputKey`;
- `RenderBuildPlan.maskIdentity` and `documentIdentity`, and the revision ledger built on them;
- the `LocalMaskRenderer` stroke cache, the `RetouchRenderer` definition hash,
  `PreviewFrameIdentity`, `LookPreviewCoordinator.CacheKey`, and the `EditedThumbnailCoordinator`
  revision string.

### Migration rule, if a durable digest ever has to change

This plan does not change one. Child 1 adds a golden test that pins the durable bytes, so an
accidental change fails CI and doesn't silently reclassify stored frames. If a later change has to
alter a durable digest:

1. **Make old and new values unable to compare equal.** Give the new scheme a distinct prefix, for
   example `v2:`. An old frame can then never classify as `.exact` against a new document hash.
2. **Frame stores self-heal.** A mismatched `editHash` classifies as `.staleCompatible`: the old
   frame is shown as an inert placeholder, rendered again, and replaced once. That is the same safe
   path a `pixelEpoch` bump takes. It never presents as exact.
3. To discard old frames outright instead of demoting them, bump
   `PresentationFrameEnvelope.storageFormatVersion`. The stores already ignore unsupported versions.
4. **Bump the owning version** for every other durable consumer: `CurrentEditMeasurement.version`
   for the measurement cache, and `AutoEnhancementPolicy.algorithmVersion` or
   `RenderIdentity.current` for Auto fingerprints. Changing the Auto fingerprint makes stored Auto
   results read as not yet run. That is user-visible and needs a release note.
5. **Never write `Hasher` output** as the new durable value.

## Child tickets

They are staged so each one is independently shippable and measured with the benchmark above.
Every child must:

- report before and after numbers from `RenderKeyHashingBenchmark`, including the large recipe;
- add a unit test showing that equal documents produce equal keys and that every edit changes the
  key;
- keep the constraints above.

1. **KRMA-1098 — Main-actor per-tick identity.**
   - Replace hashing with `==` in `markingManualEdits` and `AutoWorkflowCoordinator`.
   - Move `presentAdjustedFrame` and `PreviewFrameIdentity` off `editHash`.
   - Add a golden durable-digest test.
2. **KRMA-1099 — Durable `editHash` memo.**
   - Compute it at most once per document value, off the main actor where the consumer is async.
   - Serve it to every remaining consumer: frame signatures and classification, edited thumbnails,
     Look-strip keys, Auto, measurement, and the Apple reference.
3. **KRMA-1100 — `RenderDocumentIdentity` and its engine memo.** *(Landed: memoized build after an exposure tick 0.058 ms on the large recipe; cold 86.9 ms.)*
   - Add the value type and the equality-reuse memo, with no call-site changes yet.
   - Add the custom-`==` audit test.
4. **KRMA-1101 — Thread `RenderDocumentIdentity` through the render path.**
   - Replace the 19 per-request digests in `RenderBuildPlan`, the preview, developed-source, prefix
     and mask keys, and the mask payload validation in `LocalMaskRendering`.
5. **KRMA-1102 — Per-stroke brush identity.**
   - Make a brush definition digest a combination of per-stroke digests, so painting re-encodes
     only the active stroke.
   - Make `LocalMaskRenderer`'s stroke cache reuse the same digests.

Dependencies: KRMA-1100 → KRMA-1101 → KRMA-1102. KRMA-1098 and KRMA-1099 are independent of each other and of the engine work.

## Expected result

These are targets, not claims. Each child records its measured number.

- Large-recipe warm digest work per exposure tick on the render actor: 174 ms → < 1 ms. That is one
  `LightAdjustments` digest plus equality checks.
- Main-actor identity work per tick with the large recipe: ≥ 87.6 ms → < 0.1 ms.
- Plain document: 0.153 ms → ≤ 0.05 ms. It is already cheap, and the gate there is "no regression".
- Durable digests and persisted frames: unchanged. The golden test proves it.
