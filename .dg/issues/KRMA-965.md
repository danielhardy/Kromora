---
id: KRMA-965
title: "Fix documentation drift: CIImage Sendable statement in CLAUDE.md vs engine behavior"
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Check Sendable conformance of CIImage, CIFilter, and CIContext against the current SDK with Swift 6 scratch typechecks.
      result: pass
      notes: CIImage and CIContext compiled as Sendable; CIFilter failed the Sendable constraint as expected.
    - criterion: Review all Task.detached/@concurrent sites in RenderEngine.swift that return or capture CIImage and explain their Swift 6 correctness.
      result: pass
      notes: No @concurrent sites. Task.detached at lines 1652 and 1691 return CIImage? from the standard-image developed-source path. Both capture only Sendable values (ImageSource, RAWDevelopSettings, RenderScale, ImageRotation); CIImage is Sendable in the current SDK, so the detached result transfer is valid. A clean Swift 6 build emitted no diagnostics.
    - criterion: Align CLAUDE.md and docs/ENGINEERING_GUIDE.md with SDK conformance and the engine boundary.
      result: pass
      notes: The docs identify CIImage/CIContext as Sendable and CIFilter as non-Sendable, retain the render-engine design constraint, and describe completed CIImage inputs and the GPU-backed makeCIImage output accurately.
    - criterion: Keep the change documentation-only and confirm swift build.
      result: pass
      notes: The verification fix changes only docs/ENGINEERING_GUIDE.md. swift build passed, including a clean scratch-path build.
  checks_run:
    - "Scratch swiftc typecheck against the macOS 27 SDK with macOS 26 deployment target: CIImage Sendable pass; CIContext Sendable pass; CIFilter Sendable negative control failed as expected."
    - swift build — pass.
    - swift build --scratch-path /tmp/krma965-swift-build — clean build pass, zero diagnostics.
    - git diff --check — pass.
  findings: []
  fixes:
    - "Clarified docs/ENGINEERING_GUIDE.md: corrected the RenderEngine boundary description, documented detached CIImage returns, and stated which completed CIImage values enter and leave the engine."
  verification_commits:
    - df5b2f7dc7b136e71075241e433a021362fae8e5
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T16:47:26.366Z
  session: 01MV8CC7078SU1626P
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - docs
created: 2026-10-13T14:48:15.142Z
updated: 2026-10-14T16:47:26.369Z
parent: KRMA-922
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T16:45:09.690Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - df5b2f7dc7b136e71075241e433a021362fae8e5
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

## Agent log

- 2026-10-14T16:47:26.366Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Check Sendable conformance of CIImage, CIFilter, and CIContext against the current SDK with Swift 6 scratch typechecks. (pass) — CIImage and CIContext compiled as Sendable; CIFilter failed the Sendable constraint as expected.
- [x] Review all Task.detached/@concurrent sites in RenderEngine.swift that return or capture CIImage and explain their Swift 6 correctness. (pass) — No @concurrent sites. Task.detached at lines 1652 and 1691 return CIImage? from the standard-image developed-source path. Both capture only Sendable values (ImageSource, RAWDevelopSettings, RenderScale, ImageRotation); CIImage is Sendable in the current SDK, so the detached result transfer is valid. A clean Swift 6 build emitted no diagnostics.
- [x] Align CLAUDE.md and docs/ENGINEERING_GUIDE.md with SDK conformance and the engine boundary. (pass) — The docs identify CIImage/CIContext as Sendable and CIFilter as non-Sendable, retain the render-engine design constraint, and describe completed CIImage inputs and the GPU-backed makeCIImage output accurately.
- [x] Keep the change documentation-only and confirm swift build. (pass) — The verification fix changes only docs/ENGINEERING_GUIDE.md. swift build passed, including a clean scratch-path build.
Checks run:
- Scratch swiftc typecheck against the macOS 27 SDK with macOS 26 deployment target: CIImage Sendable pass; CIContext Sendable pass; CIFilter Sendable negative control failed as expected.
- swift build — pass.
- swift build --scratch-path /tmp/krma965-swift-build — clean build pass, zero diagnostics.
- git diff --check — pass.
Findings:
- None
Fixes:
- Clarified docs/ENGINEERING_GUIDE.md: corrected the RenderEngine boundary description, documented detached CIImage returns, and stated which completed CIImage values enter and leave the engine.
Verification commits:
- df5b2f7dc7b136e71075241e433a021362fae8e5
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8CC7078SU1626P
Summary: Counterpoint verification passed. SDK conformance checks and clean Swift 6 build pass; clarified CIImage transfer directions in the engineering guide. No remaining findings.
