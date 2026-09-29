---
id: KRMA-699
title: Drop Intel and universal builds; ship Apple Silicon only
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: scripts/release-dmg.sh builds and verifies an arm64-only app; rejects x86_64 or universal slice pair
      result: pass
      notes: KROMORA_BUILD_ARCHS x86_64 and arm64,x86_64 both rejected with exit 1; verified lipo -archs check requires exact arm64 match (release-dmg.sh:166-169)
    - criterion: scripts/build-macos-app.sh no longer accepts arm64,x86_64 and no longer calls lipo
      result: pass
      notes: Universal branch removed; only single arm64 swift build path remains; no lipo invocation in build-macos-app.sh
    - criterion: docs/PACKAGING.md and scripts/README.md describe an Apple Silicon release with no universal-binary instructions
      result: pass
      notes: Both docs updated to arm64-only language; no remaining universal-build instructions
    - criterion: rg -n "x86_64|lipo" scripts docs/PACKAGING.md returns nothing except deliberate rejection/historical note
      result: pass
      notes: "Only matches: release-dmg.sh:43 rejection message and release-dmg.sh:166 arm64-only verification lipo -archs call"
    - criterion: Local KROMORA_SKIP_NOTARIZE=1 dry run confirms built executable is arm64 only
      result: pass
      notes: Ran KROMORA_SKIP_NOTARIZE=1 scripts/release-dmg.sh 9.9.9-verify; build succeeded, internal arch assertion passed, and lipo -archs .build/Kromora.app/Contents/MacOS/Kromora printed 'arm64'; test DMG removed after verification
  checks_run:
    - zsh -n scripts/build-macos-app.sh
    - zsh -n scripts/release-dmg.sh
    - git diff --check 1e26938 1728134 -- scripts/build-macos-app.sh scripts/release-dmg.sh docs/PACKAGING.md scripts/README.md
    - rg -n "x86_64|lipo" scripts docs/PACKAGING.md
    - KROMORA_BUILD_ARCHS=x86_64 scripts/build-macos-app.sh (expect rejection)
    - KROMORA_BUILD_ARCHS=arm64,x86_64 scripts/build-macos-app.sh (expect rejection)
    - KROMORA_BUILD_ARCHS=x86_64 scripts/release-dmg.sh 9.9.9 (expect rejection)
    - KROMORA_SKIP_NOTARIZE=1 scripts/release-dmg.sh 9.9.9-verify (full local dry-run build/sign/dmg)
    - lipo -archs .build/Kromora.app/Contents/MacOS/Kromora
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T00:39:12.308Z
  session: 01MULY5KUIIGTN8HGH
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - tahoe
  - build
  - packaging
created: 2026-09-28T22:41:47.613Z
updated: 2026-09-29T00:39:12.310Z
blockers: []
order: a0
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

### Comment — codex @ 2026-09-29T00:37:08.351Z

Implemented arm64-only app and DMG packaging, removed the universal lipo build path, added explicit rejection of non-arm64 build requests, and updated packaging docs. Verification: zsh syntax check and git diff --check passed; x86_64 and universal requests were rejected; KROMORA_SKIP_NOTARIZE=1 dry run completed, and lipo -archs reported arm64. The only remaining x86_64/lipo references are the deliberate rejection and arm64-only verification. Commit: 1728134.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T00:39:12.308Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] scripts/release-dmg.sh builds and verifies an arm64-only app; rejects x86_64 or universal slice pair (pass) — KROMORA_BUILD_ARCHS x86_64 and arm64,x86_64 both rejected with exit 1; verified lipo -archs check requires exact arm64 match (release-dmg.sh:166-169)
- [x] scripts/build-macos-app.sh no longer accepts arm64,x86_64 and no longer calls lipo (pass) — Universal branch removed; only single arm64 swift build path remains; no lipo invocation in build-macos-app.sh
- [x] docs/PACKAGING.md and scripts/README.md describe an Apple Silicon release with no universal-binary instructions (pass) — Both docs updated to arm64-only language; no remaining universal-build instructions
- [x] rg -n "x86_64|lipo" scripts docs/PACKAGING.md returns nothing except deliberate rejection/historical note (pass) — Only matches: release-dmg.sh:43 rejection message and release-dmg.sh:166 arm64-only verification lipo -archs call
- [x] Local KROMORA_SKIP_NOTARIZE=1 dry run confirms built executable is arm64 only (pass) — Ran KROMORA_SKIP_NOTARIZE=1 scripts/release-dmg.sh 9.9.9-verify; build succeeded, internal arch assertion passed, and lipo -archs .build/Kromora.app/Contents/MacOS/Kromora printed 'arm64'; test DMG removed after verification
Checks run:
- zsh -n scripts/build-macos-app.sh
- zsh -n scripts/release-dmg.sh
- git diff --check 1e26938 1728134 -- scripts/build-macos-app.sh scripts/release-dmg.sh docs/PACKAGING.md scripts/README.md
- rg -n "x86_64|lipo" scripts docs/PACKAGING.md
- KROMORA_BUILD_ARCHS=x86_64 scripts/build-macos-app.sh (expect rejection)
- KROMORA_BUILD_ARCHS=arm64,x86_64 scripts/build-macos-app.sh (expect rejection)
- KROMORA_BUILD_ARCHS=x86_64 scripts/release-dmg.sh 9.9.9 (expect rejection)
- KROMORA_SKIP_NOTARIZE=1 scripts/release-dmg.sh 9.9.9-verify (full local dry-run build/sign/dmg)
- lipo -archs .build/Kromora.app/Contents/MacOS/Kromora
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULY5KUIIGTN8HGH
Summary: Verified arm64-only packaging: build-macos-app.sh and release-dmg.sh reject x86_64/universal requests, no lipo combine path remains, docs updated, and a live KROMORA_SKIP_NOTARIZE=1 dry run produced an arm64-only signed .app/DMG.
