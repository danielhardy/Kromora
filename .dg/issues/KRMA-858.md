---
id: KRMA-858
title: Replace brittle source-text inspector assertions with behavioral tests
type: task
status: backlog
priority: low
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:08:35.833Z
updated: 2026-10-11T13:11:12.832Z
depends_on:
  - KRMA-853
blockers: []
order: zzzh
board: product
---

## Objective

Several inspector tests assert on the literal text of Swift source files (`inspectorSource(named:)`, `lightInspectorSource()`, `source.contains("...")`). They broke when KRMA-844 renamed an accessibility-label expression and have broken before (KRMA-844, KRMA-846). KRMA-846's verifier called them brittle. Replace them with behavioral or presentation-model assertions so refactors that keep behavior stop failing CI.

## Scope

Audit `Tests/KromoraKitTests/LightInspectorTests.swift`, `CropInspectorTests.swift`, `InfoInspectorPresentationTests.swift`, `MenuCommandTests.swift` (and any other file using `inspectorSource`). For each source-text assertion decide: (a) express it through an existing presentation model or a small test seam; (b) assert the accessibility contract via the view's exposed label/action values; or (c) delete it if it only restates the implementation. Record the decision per assertion in the ticket.

## Acceptance criteria

1. No remaining test depends on exact spelling of a modifier chain or argument list; a grep for `inspectorSource(named:` in the audited files returns only deliberate structural invariants (documented in a comment).
2. Behavior previously guarded is still guarded: reset controls expose a label and a trailing-disclosure action; headings follow the shared hierarchy; the crop reset keeps its semantic accent and link accessibility.
3. Renaming `ResetIconButton`'s internal label helper does not fail any test.
4. `scripts/ci-tests.sh fast` and `serial` pass.

Depends on KRMA-853 (immediate repair of the currently failing assertion). Related: KRMA-844, KRMA-846.


### Comment — claude @ 2026-10-11T13:11:12.832Z

Scope trimmed (2026-10-11): only LightInspectorTests still uses inspectorSource/lightInspectorSource; audit that file first. Depends on KRMA-853, which is still failing at LightInspectorTests.swift:160.
