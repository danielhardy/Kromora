---
id: KRMA-452
title: Reject non-rasterizable CIRAWFilter extents at the decode boundary
type: bug
status: ready
priority: high
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - raw
  - decoder
  - correctness
created: 2026-09-18T22:38:54.707Z
updated: 2026-09-18T22:40:12.678Z
order: t
board: product
---

## Objective

Reject corrupt / misnamed / truncated RAW inputs at the `ImageDecoder` / prepare boundary when `CIRAWFilter` returns a non-nil `outputImage` whose extent is not rasterizable, instead of treating them as a successful open that later blanks the preview.

## Context

### Bug shape (measured upstream as B16)

Upstream LUTzy (`fdcf2b1` on `tsvb/lutzy`) found:

- `CIRAWFilter(imageURL:)` handed twelve bytes of ASCII text named `.dng` **constructs a filter and returns an `outputImage`**.
- Extent was effectively empty / non-finite (`(inf, inf, 0, 0)` class of failure).
- Nil-checks alone were insufficient; downstream render paths already used `extent.isRasterizable`, so the status bar could show `0×0`, the preview stayed blank, and **no open error was shown**.

### Current Kromora behavior

- `CGRect.isRasterizable` already exists on `ImageDecoder.swift` and rejects empty / null / infinite extents.
- `RenderEngine` guards many paths with `image.extent.isRasterizable`.
- `ImageDecoder.developedImage(from:orientation:)` currently does:

  ```swift
  guard let output = filter.outputImage else { return nil }
  return displayOrientedRAWOutput(...)
  ```

  It does **not** require `output.extent.isRasterizable` before returning success.
- Prepare / open paths that trust `developedImage` / RAW prepare can therefore publish a “loaded” source that cannot be rasterized.

### Why this matters

Users (and tests) should get a clear `cannotLoad` / open failure for garbage RAW-named files, not a silent blank canvas. This is the third instance of “framework accepts input the code assumed it would reject” in the upstream review narrative; Kromora should fail at the decode boundary.

### Upstream reference

- `git show fdcf2b1` (ImageDecoder + ImageLoadingTests)
- Fixture approach: a tiny text file named `.dng` is enough for CI — no licensed camera RAW required.

## Acceptance criteria

- [ ] `ImageDecoder.developedImage(from:orientation:)` (and any sibling RAW decode entry that returns pixels/extent for open) returns `nil` / throws `cannotLoad` when `outputImage` is missing **or** `output.extent` is not `isRasterizable`.
- [ ] Source preparation / open failure surfaces an actionable error to the user (existing status / failure publishing path), not a blank preview with a “successful” selection.
- [ ] A CI-safe regression test opens a tiny non-RAW byte payload with a RAW extension (e.g. `.dng`) and asserts failure at the decode/prepare boundary — not a successful zero-extent source.
- [ ] Converse test: a known-good RAW fixture path (opt-in real RAW **or** an existing generated/neutral path the suite already trusts) still loads; the fix must not become “reject every RAW”.
- [ ] No change to legitimate empty-state UI for “no photo selected”; this is strictly failed open / failed decode.

## Out of scope

- Broader RAW decoder performance work.
- Changing `isRasterizable` semantics for non-RAW `CIImage` loads unless required for consistency at the same boundary.
- The failed-open probe cancellation issue (KRMA-453) — related UX, separate ticket.

## Implementation notes

1. Prefer failing in `developedImage` (single choke point) so URL and Data RAW paths both inherit the guard.
2. Reuse `CGRect.isRasterizable`; do not invent a second extent predicate.
3. Trace callers: `prepareSource`, neutral develop used by derive, thumbnail/first-frame paths — ensure they treat `nil` as failure without crashing.
4. Keep Swift 6 clean; no Sendable opt-outs.
5. Put tests in `Tests/KromoraKitTests/` beside existing image loading / decoder tests (`ImageLoadingTests` if present, else extend the closest suite).

## Verification

- Focused decoder / image-loading tests.
- `swift build`
- `git diff --check`
- Do not require `KROMORA_RAW_FIXTURE_DIR` for the corrupt-file case.

### Comment — cursor @ 2026-09-18T22:40:12.678Z

Provenance: upstream B16 from fdcf2b1 — CIRAWFilter can return non-nil outputImage with non-rasterizable extent for garbage .dng bytes. Fail at ImageDecoder.developedImage using existing isRasterizable; CI fixture can be a tiny text file named .dng.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
