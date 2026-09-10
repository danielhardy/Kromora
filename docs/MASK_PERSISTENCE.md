# Mask persistence

`MaskStore` is a durable cache, separate from edit persistence. The permanent design is the
sidecar layout under `~/Library/Application Support/Kromora/Masks/`:

- `mask-<digest>.json` contains only the exact `MaskCacheKey` and pixel dimensions.
- `mask-<digest>.bin` contains the corresponding raw `Float32` pixel buffer.

The JSON file is deliberately metadata-only. `mask(for:quality:)` reads that metadata and checks
the sidecar's file size without loading the pixel buffer, so person/foreground gating stays cheap.
`pixels(for:)` is the explicit boundary that loads and validates the binary payload. Quality is part
of the digest, so a lookup never substitutes a lower-quality mask.

Older mask files stored `size` and `values` inline under `mask`. They remain readable as a one-way
compatibility path; all new writes use the sidecar format. A missing or truncated sidecar is treated
as a cache miss, allowing the provider to regenerate the mask.

Edit records may move to SwiftData independently. Mask pixels remain flat files rather than being
placed in a SwiftData `Data` attribute: even external-storage SwiftData blobs would add model and
migration machinery without improving the streaming/cache behavior needed for full-resolution
refinements. This split also keeps mask caches disposable and avoids putting recomputable pixels in
the edit document's durable history.
