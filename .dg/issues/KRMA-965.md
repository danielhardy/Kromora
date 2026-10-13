---
id: KRMA-965
title: "Fix documentation drift: CIImage Sendable statement in CLAUDE.md vs engine behavior"
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - docs
parent: KRMA-922
created: 2026-10-13T14:48:15.142Z
updated: 2026-10-13T14:48:24.385Z
blockers: []
order: zzzq
board: product
---

## Objective

Make `CLAUDE.md` and `docs/ENGINEERING_GUIDE.md` say what is true about `CIImage` and `Sendable`, and
confirm the engine's actual boundary.

## Context

Review `.context/2026-10-13-release-readiness-review.md` "Nice to have: Doc drift". `CLAUDE.md` (~L74) says "`CIImage`, `CIFilter` and
`CIContext` are not `Sendable` and must stay inside `RenderEngine`". The review observed the engine
returns `CIImage` from detached tasks. `docs/ENGINEERING_GUIDE.md` ~L61 states the same boundary. On the
macOS 26 SDK `CIImage` may have gained `Sendable` conformance, or the engine may truly be leaking a
non-`Sendable` value. Determine which BEFORE editing docs.

## Acceptance criteria

- [ ] A quick check: does `CIImage` conform to `Sendable` in the SDK in use (a scratch file in the
      scratchpad: `func f<T: Sendable>(_: T.Type) {}; f(CIImage.self)` compiles or not; same for
      `CIFilter`, `CIContext`)? Report results.
- [ ] Find the `Task.detached`/`@concurrent` sites in `RenderEngine.swift` that return or capture
      `CIImage`, and state whether each is correct under Swift 6 mode (it compiles with zero diagnostics,
      so it must be; say why).
- [ ] Update the sentences in `CLAUDE.md` and `docs/ENGINEERING_GUIDE.md` so they match reality
      (keeping any rule that is still a good design constraint, e.g. "keep CI graph construction inside
      `RenderEngine`", worded as a design rule rather than a compiler fact).
- [ ] Only documentation changes; `swift build` unchanged.
