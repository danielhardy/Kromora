---
id: KRMA-892
title: Replace com.kromora.app log subsystem with a single shared constant
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - observability
  - cleanup
created: 2026-10-12T12:42:03.669Z
updated: 2026-10-13T14:48:00.703Z
blockers: []
order: 3sf5omqg
board: product
---

## Objective

Replace com.kromora.app log subsystem with a single shared constant

## Context

The app's real bundle ID is `com.last8.kromora.photo` (`App/Info.plist`), but its os_log and signpost
subsystem is the hardcoded literal `com.kromora.app`, repeated in six places. The literal is only a log
label, so nothing is broken; the mismatch is confusing and the duplication makes a rename error-prone.

## Acceptance criteria

- [ ] One shared constant defines the log subsystem; no other `"com.kromora.app"` literal remains in `Sources/`.
- [ ] The subsystem stays a plain string, not `Bundle.main.bundleIdentifier`, so logs keep their label under `swift run` (no bundle).
- [ ] `docs/TESTING.md` `log stream --predicate` examples match the new value.
- [ ] `swift build` and `scripts/ci-tests.sh fast` pass.

## Implementation notes

Literals: `Observability.swift` (workflow signposter x2, mask-resolution, thumbnail-frames, photo-switch),
`PreviewPresentationCoordinator.swift:77` (presentation-session), `VisionSemanticMaskProvider.swift:402`
(vision-matte), and `docs/TESTING.md`.

Out of scope, and no migration is needed since only the maintainer has an install: the UTIs
`com.kromora.kromoralibrary` and `com.kromora.original-settings-bundle` in `App/Info.plist` and
`scripts/verify-library-package-metadata.sh`. Renaming them is a separate, deliberate change.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
