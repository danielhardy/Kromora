---
id: KRMA-699
title: Drop Intel and universal builds; ship Apple Silicon only
type: task
status: backlog
priority: high
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - tahoe
  - build
  - packaging
created: 2026-09-28T22:41:47.613Z
updated: 2026-09-28T22:41:47.613Z
blockers: []
order: zh
board: product
---

## Objective

Stop shipping and documenting Intel (`x86_64`) and universal binaries. Kromora is Apple Silicon only, matching the macOS 26 baseline. Release packaging, the app bundler, and packaging docs should produce and describe an arm64 app, with no `lipo` universal path and no Intel fallback.

Parent: KRMA-693. Sequencing: after KRMA-694 (floor raise, done). Do not mix this with availability-guard deletion (KRMA-695) or toolbar/layout work (KRMA-696, KRMA-697).

## Context

The deployment floor is already macOS 26, but distribution still defaults to a universal binary:

- `scripts/release-dmg.sh:23` and `:117` — default `KROMORA_BUILD_ARCHS=arm64,x86_64`; `:159-160` — `lipo -archs` requires both `arm64` and `x86_64`.
- `scripts/build-macos-app.sh:14` and `:38-57` — `native` or `arm64,x86_64`; the second mode builds both slices and `lipo -create`s them.
- `docs/PACKAGING.md:98` and `:139` — "arm64 + x86_64 release" and "universal builds".
- `scripts/README.md:11` — `release-dmg.sh` described as a universal DMG.

Agent guidance now says Apple Silicon only (`CLAUDE.md`, `AGENTS.md`). This ticket makes the packaging artifact match that policy. `#if os(macOS)` in the library package is a platform check, not an Intel fallback; leave it.

## Acceptance criteria

- [ ] `scripts/release-dmg.sh` builds and verifies an arm64-only app. It rejects a request for `x86_64` or a universal slice pair.
- [ ] `scripts/build-macos-app.sh` no longer accepts `arm64,x86_64`, and no longer calls `lipo` to combine architectures.
- [ ] `docs/PACKAGING.md` and `scripts/README.md` describe an Apple Silicon release. They do not tell a reader to produce a universal binary.
- [ ] `rg -n "x86_64|lipo" scripts docs/PACKAGING.md` returns nothing except a deliberate rejection or historical note, with that exception recorded in the handoff.
- [ ] A local `KROMORA_SKIP_NOTARIZE=1` dry run, or the closest available packaging check, confirms the built executable is arm64 only (`lipo -archs` prints `arm64`).

## Implementation notes

Delete the universal branch rather than leaving it behind a flag. Native `swift build` on an Apple Silicon machine already produces arm64; keep that as the only path. Do not add a Rosetta or Intel compatibility note that invites the path back.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
