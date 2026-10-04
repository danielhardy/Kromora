---
id: KRMA-804
title: Document the build architecture invariant for agents in CLAUDE.md and AGENTS.md
type: task
status: ready
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - docs
  - agents
created: 2026-10-03T19:24:42.131Z
updated: 2026-10-03T19:25:53.852Z
depends_on:
  - KRMA-802
  - KRMA-803
blockers: []
order: zzzy
board: product
---

## Objective

Make the new two-launcher architecture explicit so agents never turn the Xcode project into a second source tree.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, Workstream 8; its "Build architecture" snippet is the starting text). `CLAUDE.md` is the canonical agent guidance; root `AGENTS.md` points to it. CLAUDE.md currently describes `swift build`/`swift run`/`swift test` and the Layout, and says "Full app (icon + App Sandbox): open `Package.swift` in Xcode and Run." Earlier tickets already updated the Layout bullets for `Sources/Kromora/` and `App/`; read the current file first and avoid duplicating them.

## Scope

- Add a "Build architecture" section to `CLAUDE.md`: SwiftPM is the primary development build system; all application functionality belongs in `KromoraKit`; the Xcode project exists only to package KromoraKit as the signed, sandboxed Mac App Store app; the SwiftPM `Kromora` executable is the development launcher and the Xcode `Kromora` target is the production launcher; do not add implementation files to the Xcode target (guarded by `XcodeProjectInvariantTests`, if that ticket has landed; otherwise omit the mention); verify the production app with `scripts/app-store-build.sh`.
- Replace the "Full app (icon + App Sandbox): open `Package.swift` in Xcode and Run" line with the new instruction (`open Xcode/Kromora.xcodeproj`, scheme Kromora).
- Add the distribution model (Mac App Store, TestFlight, source builds only; no DMG or updater) in two sentences.
- Check `AGENTS.md` still just points to CLAUDE.md; change nothing else.

## Acceptance criteria

- [ ] `CLAUDE.md` contains the new section with the invariant and the correct commands; no stale references to opening `Package.swift` for the sandboxed app, DMGs, or the updater.
- [ ] Every command and path mentioned exists in the repository (check each).
- [ ] No source or script changes.

## Verification

- Read the diff once and run each documented command that is cheap (`xcodebuild -list`).

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
