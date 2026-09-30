---
id: KRMA-737
title: Restore RAW preparation and decoder seed bounds for local camera fixtures
type: task
status: backlog
priority: urgent
agent: codex
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - reliability
  - verification
  - raw
created: 2026-09-30T21:55:42.693Z
updated: 2026-09-30T21:55:42.693Z
blockers: []
order: m
board: product
---

## Objective

Restore the opt-in real-RAW qualification checks for representative local camera files on the
supported macOS/Xcode toolchain.

## Context

During KRMA-734 on 2026-09-30, the optional lane used the local 8064×6048 IMG_0371.DNG fixture and
exposed two failing test methods with three failed assertions:

- `ImageLoadingTests.testLoadingARAWGoesThroughCIRAWFilter`: `RenderEngine.prepareSource` returned
  nil for the DNG after `ImageDecoder.load` and neutral RAW development succeeded.
- `RAWCapabilitiesTests.testEveryPerImageSeedLandsStrictlyInsideItsSliderRange`: the decoder
  reported Sharpness = 1.0 and Local Tone Map = 1.0, both at the top of their slider ranges.

These are broad RAW preparation and control-range issues outside last-known-frame ownership. Keep
them isolated here; do not weaken assertions or convert failures to skips.

## Acceptance criteria

- [ ] A supported real DNG/ARW fixture is admitted by `RenderEngine.prepareSource` and the existing
  neutral-develop parity assertion passes.
- [ ] Per-image decoder seeds land strictly inside their applicable slider ranges, or the control
  mapping is corrected so the decoder default is not pinned at maximum.
- [ ] The relevant optional RAW tests pass on a supported macOS 26+ toolchain with fixture details
  recorded; missing licensed fixtures remain the only reason to skip them.
- [ ] No retry loop or relaxed assertion masks decode/admission failures.

## Reproduction

`KROMORA_RAW_FIXTURE_DIR=<fixture-folder> scripts/ci-tests.sh optional`

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
