---
id: KRMA-760
title: Show the histogram for an exact stored frame without waiting for source preparation
type: task
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - design
created: 2026-10-02T03:33:22.387Z
updated: 2026-10-02T03:34:17.346Z
blockers: []
order: zzy
board: product
---

## Objective

Design, and only then build, a way for the histogram of an **exact** stored frame to appear without waiting for source preparation. This is a design ticket for a stronger agent or the owner; it is not for an unattended run.

## Why it is separate

Today the histogram needs a prepared `imageSource` and a presented frame whose `RenderRequest` matches the current document (`PreviewAdmissionCoordinator.updateHistogram`), and an exact stored frame is only recognized at settled-preview admission, which also needs the prepared source. So the histogram cannot start before source preparation (about 290 ms for the benchmark RAW), regardless of how early the panel values arrive. The plan (docs/ and .context/last-known-frame-plan.md) allows the exact frame to feed histogram and supporting work through the confirmed tail but forbids a provisional frame from doing so, so the boundary matters.

## Options to weigh

1. Classify the stored frame as exact before preparation completes. Exact needs only the source identity (known from the record), the edit hash (now available early, KRMA-755), and the resolved Look; if all are known, the frame is exact and its raster is the final pixels, so its histogram is the real histogram. Needs the admission path to stop assuming a prepared source for this one case.
2. Persist a small histogram (for example 256 bins per channel) in the `LatestPreviewFrameStore` envelope beside the raster and show it with an exact hit. Derived data of the same pixels, but it changes the envelope (a `storageFormatVersion` bump, per-entry miss) and has to be invalidated exactly as the frame is.
3. Leave the histogram where it is and only fix queue order (KRMA-759).

## Decide before building

Which of these is worth its complexity once KRMA-757 and KRMA-759 have measured how much of the histogram delay is preparation versus queue. If KRMA-759 closes most of the gap, close this ticket as not needed.
