---
id: KRMA-741
title: Fix stable Xcode 27 Release XCTest bundle linking
type: bug
status: backlog
priority: urgent
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
  - build
created: 2026-10-01T00:57:06.326Z
updated: 2026-10-01T00:57:06.326Z
blockers: []
order: t
board: product
---

## Objective

Make the Release `KromoraKitTests.xctest` bundle link successfully with stable Xcode 27.0 so the
KRMA-734 Release drawable benchmark can run.

## Context

On stable Xcode 27.0 (27A266a) with the macOS 27.0 SDK, `swift test -c release --filter
MetalPresentationBenchmark/testRealMetalPresentationBenchmark` compiles the test target but fails
at link time. The linker reports unresolved SwiftUI opaque type descriptors for
`View.tag(_:includeOptional:)` and `View.task(name:priority:file:line:_:)`, missing `CoreAudioTypes`,
and rejects direct linking to `SwiftUICore.tbd`. Reproduced in KRMA-738 on an Apple M1 Pro running
macOS 27.0 build 26A428. The 30-iteration capture never launches.

## Acceptance criteria

- [ ] The Release XCTest bundle links with stable Xcode 27.0 without private-framework linkage or
      compatibility workarounds.
- [ ] The metal-presentation capture launches from the Release test bundle and emits benchmark
      samples on a logged-in macOS display.
- [ ] Record the diagnosis, fix, and verification command/results in the issue.

## Implementation notes

Keep the product deployment target at macOS 26 and preserve Swift 6 checks and the no-private-API
policy. Investigate SwiftPM test product linkage and target dependencies before changing source.
The reproduction summary from KRMA-738 is at
`/tmp/kromora-capture/KRMA-738-stable-xcode-27-DSC01019-20260930-185223-summary.txt`.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
