---
id: KRMA-493
title: "Test coverage for selective copy: filmstrip Shift-range, remembered defaults, key routing"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Tests for the three gaps pass in scripts/ci-tests.sh fast / serial
      result: pass
      notes: Reviewed the new tests; re-ran CopyPasteTests and KeyMonitorTests (21 tests, 0 failures). Implementer reported fast 1103 and serial 398 passing; I did not re-run the full lanes.
    - criterion: NSControl-focus Cmd-C behavior documented or fixed
      result: pass
      notes: Documented by a comment in KeyMonitor and pinned by a test asserting the event passes through when an NSButton is first responder.
  checks_run:
    - swift test --filter CopyPasteTests|KeyMonitorTests (21 tests, 0 failures)
    - code review of f50c81b diff
  findings: []
  fixes: []
  verification_commits:
    - f50c81b
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T00:00:24.457Z
  session: 01MUAHAT96GMEBYP7H
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - tests
created: 2026-09-20T23:01:36.497Z
updated: 2026-09-21T00:00:24.458Z
parent: KRMA-492
order: a0
board: product
commits:
  - f50c81b
---

## Objective

Close the test gaps left by KRMA-492 (verification finding, non-blocking).

## Context

- No VM-level test that `presentSelectiveCopyDialog()` seeds `selectiveCopyCategories` from `settings.lastCopyCategories` and `confirmSelectiveCopy()` persists it (only the raw `KromoraSettings` round-trip is tested).
- No test that `selectCollectionImage(at:modifiers:[.shift])` builds a range selection from the filmstrip path and that paste then covers that range.
- No `KeyMonitor` test that plain ⌘C/⌘V route to the copy dialog/paste and are ignored when an `NSText` is first responder (pattern after the existing `KeyMonitorPolicy` tests).
- Behavior note: when an `NSControl` is first responder, plain ⌘C/⌘V fall through to the menu, which has no plain-⌘C binding. Toolbar and the "Copy Edits…" menu item still work.

## Acceptance criteria

- [ ] Tests for the three gaps above pass in `scripts/ci-tests.sh fast` / `serial`.
- [ ] NSControl-focus ⌘C behavior documented or fixed.

### Comment — codex @ 2026-09-20T23:59:51.087Z

Implemented and committed as f50c81b. Added VM-level selective-copy remembered-default seeding/persistence coverage, filmstrip Shift-range selection plus range paste coverage, and KeyMonitor plain Cmd-C/V routing coverage for global, NSText, and NSControl focus. Documented that NSControl focus intentionally passes plain Cmd-C/V through to AppKit/menu; explicit Copy Edits actions remain available. Verification: focused copy/keyboard tests pass; scripts/ci-tests.sh fast passed 1,103 tests with 0 failures; serial passed 398 tests with 1 documented RAW-fixture skip and 0 failures; dg validate passed with pre-existing unknown-model warnings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-21T00:00:24.457Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Tests for the three gaps pass in scripts/ci-tests.sh fast / serial (pass) — Reviewed the new tests; re-ran CopyPasteTests and KeyMonitorTests (21 tests, 0 failures). Implementer reported fast 1103 and serial 398 passing; I did not re-run the full lanes.
- [x] NSControl-focus Cmd-C behavior documented or fixed (pass) — Documented by a comment in KeyMonitor and pinned by a test asserting the event passes through when an NSButton is first responder.
Checks run:
- swift test --filter CopyPasteTests|KeyMonitorTests (21 tests, 0 failures)
- code review of f50c81b diff
Findings:
- None
Fixes:
- None
Verification commits:
- f50c81b
Actor: claude
Resolved model: sonnet
Pickup session: 01MUAHAT96GMEBYP7H
Summary: Verified: tests for VM selective-copy seeding/persistence, filmstrip Shift-range paste, and KeyMonitor plain Cmd-C/V routing are correct and pass; NSControl-focus behavior documented.
