---
id: KRMA-879
title: Rebuild stale Core Image Metal library artifact
type: bug
status: backlog
priority: medium
agent: codex
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-10-11T14:27:34.527Z
updated: 2026-10-11T14:27:34.527Z
blockers: []
order: zzzy
board: product
parent: KRMA-841
---

## Objective

Rebuild the stale checked-in Core Image Metal library artifact so its recorded source checksum matches the bundled shader source.

## Context

The serial CI lane fails `MetalKernelParityTests.testCIMetallibMatchesBundledSources`: the SHA-256 stored for `KromoraCIKernels.ci.metallib` is `8319ef0b5617945623dceb8f6cec18a5cf984534095abbe9b230dc134489aeba`, while the bundled source hash is `99558961de5f240d0ba5da9f12948c7af560de3c62daa277285b54f4002587b7`. The source changed in KRMA-821 and the generated library appears not to have been rebuilt.

## Acceptance criteria

- [ ] Run `scripts/build-metal-libraries.sh` and commit the generated library and checksum.
- [ ] `scripts/build-metal-libraries.sh --check` passes.
- [ ] `swift test --no-parallel --filter MetalKernelParityTests` passes.

## Implementation notes

Use the repository build script to generate the artifact from source; do not hand-edit the binary or checksum.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
