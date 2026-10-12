---
id: KRMA-858
title: Replace brittle source-text inspector assertions with behavioral tests
type: task
status: done
priority: low
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: No audited test depends on exact modifier-chain spelling or source text; the inspectorSource(named:) grep is empty except deliberate documented structural invariants.
      result: pass
      notes: No inspectorSource(named:) or lightInspectorSource() references remain in LightInspectorTests.swift, CropInspectorTests.swift, InfoInspectorPresentationTests.swift, or MenuCommandTests.swift.
    - criterion: "Previously guarded behavior remains covered: reset controls expose labels and trailing-disclosure actions, headings use the shared hierarchy, and crop reset retains its semantic accent and link accessibility."
      result: pass
      notes: Behavior and presentation tests cover reset label/hint/action, red and blue disclosure actions, shared panel/section/nested heading levels, and the crop reset semanticLink appearance with its accessibility label and hint.
    - criterion: Renaming ResetIconButton internal label helper does not fail tests.
      result: pass
      notes: Tests assert the accessibility presentation values and do not reference the prior resolved-label helper names.
    - criterion: scripts/ci-tests.sh fast and serial pass.
      result: pass
      notes: Fast passed 1,707 tests and serial passed 514 tests, both with zero failures.
  checks_run:
    - Structural scan of audited inspector tests (passed; no source helper matches)
    - git diff --check b0bc72fe^ b0bc72fe (passed, exit 0)
    - scripts/ci-tests.sh fast (passed; 1,707 tests, 0 failures, exit 0)
    - scripts/ci-tests.sh serial (passed; 514 tests, 0 failures, exit 0)
    - Independent review of commit b0bc72fe for correctness, maintainability, security, and performance (completed; no findings)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T21:33:19.824Z
  session: 01MV4C2ZYGN6CCV46Y
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:08:35.833Z
updated: 2026-10-11T21:33:19.827Z
depends_on:
  - KRMA-853
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T21:26:46.596Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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


### Comment — codex @ 2026-10-11T21:26:46.128Z

Implementation complete and committed as b0bc72fe (KRMA-858: replace brittle inspector source assertions).

Assertion decisions:
- LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction: replaced source scanning with the InspectorDisclosure trailing button presentation and invoked its action for red and blue channels.
- testAdvancedCurveControlsAreCollapsedUntilExpanded: removed source spellings, private type boundaries, and literal control-name arrays; retained an NSHostingView expansion-height assertion with the real ParametricToneCurveControls.
- testToneCurveGraphPinsItsVerticalSizeInsideTheScrollingInspector and testInspectorRetainsViewportWidthDuringUnspecifiedScrollMeasurements: deleted because they asserted exact SwiftUI layout/cache implementation details rather than a rendered behavior.
- testToneCurveEndHandlesDrawAboveInteriorHandles: removed the literal zIndex chain; testVisibleEndpointsWinOverCloserInteriorHandles retains the hit-test behavior contract. testDoubleClickEndpointResetPreservesInteriorPointsAndGroupsUndo still checks reset and undo behavior; its handler-spelling assertions were removed.
- CropInspectorTests: replaced resolved-helper checks with ResetIconButton.AccessibilityPresentation, semanticLink appearance, and invocation of the wired reset action. The semanticLink presentation renders with .link and KromoraTheme.primaryAccent.
- InfoInspectorPresentationTests: replaced the source-based heading checks with the shared InspectorHeadingLevel presentation component, now used for Look and Histogram headings. Removed source checks for Edit History and Heal composition/default state; disclosure expansion remains behavior-tested and edit-history actions have coordinator coverage.
- MenuCommandTests: audited; it has no inspectorSource(named:) helper. Its remaining source reads guard native scene, command routing, and toolbar composition, outside the narrowed inspector accessibility assertion scope.

Verification: focused inspector suites passed (31 tests); scripts/ci-tests.sh fast passed (1,707 tests); scripts/ci-tests.sh serial passed (514 tests); scoped diff check and focused strict-format checks passed.

## Agent log

- 2026-10-11T21:33:19.824Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] No audited test depends on exact modifier-chain spelling or source text; the inspectorSource(named:) grep is empty except deliberate documented structural invariants. (pass) — No inspectorSource(named:) or lightInspectorSource() references remain in LightInspectorTests.swift, CropInspectorTests.swift, InfoInspectorPresentationTests.swift, or MenuCommandTests.swift.
- [x] Previously guarded behavior remains covered: reset controls expose labels and trailing-disclosure actions, headings use the shared hierarchy, and crop reset retains its semantic accent and link accessibility. (pass) — Behavior and presentation tests cover reset label/hint/action, red and blue disclosure actions, shared panel/section/nested heading levels, and the crop reset semanticLink appearance with its accessibility label and hint.
- [x] Renaming ResetIconButton internal label helper does not fail tests. (pass) — Tests assert the accessibility presentation values and do not reference the prior resolved-label helper names.
- [x] scripts/ci-tests.sh fast and serial pass. (pass) — Fast passed 1,707 tests and serial passed 514 tests, both with zero failures.
Checks run:
- Structural scan of audited inspector tests (passed; no source helper matches)
- git diff --check b0bc72fe^ b0bc72fe (passed, exit 0)
- scripts/ci-tests.sh fast (passed; 1,707 tests, 0 failures, exit 0)
- scripts/ci-tests.sh serial (passed; 514 tests, 0 failures, exit 0)
- Independent review of commit b0bc72fe for correctness, maintainability, security, and performance (completed; no findings)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV4C2ZYGN6CCV46Y
Summary: Verification passed: all acceptance criteria and both required CI lanes passed; no findings or verification fixes.
