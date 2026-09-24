---
id: KRMA-561
title: Bound asynchronous import waits in KeyMonitorTests
type: bug
status: claimed
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-09-24T03:11:17.182Z
updated: 2026-09-24T03:14:31.779Z
blockers: []
order: y
board: product
claim:
  actor: codex
  session: 01MUEYGZ84SVD5HOPU
  claimed_at: 2026-09-24T03:11:45.748Z
  expires_at: 2026-09-24T04:11:45.748Z
---

## Objective
Make the asynchronous photo-open setup in `KeyMonitorTests.testPlainCommandCopyAndPasteRouteOnlyWhenGlobalSurfaceOwnsKeyboard` isolated and bounded so it cannot hang the serial test lane.

## Acceptance criteria
- Each view model in the test uses an independent temporary package and writer lease.
- Each source wait has its own bounded timeout and reports which source failed to open.
- Timeout exits the test instead of repeatedly recording assertions while continuing to wait.
- The focused KeyMonitor test passes.

## Findings
The serial XCTest process was sampled in this test at the wait for `keyboard-text-focus.png`. All three view models used the same default `Test Library.kromoralibrary` path from `makeAppViewModel`, while the first view model remained alive and held its writer lease. The second view model therefore could not open the package. The old `XCTAssertLessThan(Date(), deadline)` only recorded failures and did not stop the loop; the single deadline was also shared by all three imports.

## Files and checks
- `Tests/KromoraKitTests/KeyMonitorTests.swift`
- Focused `KeyMonitorTests.testPlainCommandCopyAndPasteRouteOnlyWhenGlobalSurfaceOwnsKeyboard` passed.
