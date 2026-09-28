---
id: KRMA-687
title: Investigate AppKit constraint exception during SwiftUI scroll view updates
type: bug
status: done
priority: medium
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
thinking: xhigh
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Establish reproducible steps or a deterministic regression harness for the crash path.
      result: pass
      notes: InspectorScrollCrashPathTests.swift adds a deterministic harness driving a real NSWindow/NSHostingView through AppKit's display-cycle (window resize + disclosure toggle storms interleaved) that would abort the test process if the app-owned layout invariants regressed. The report's own Last Exception Backtrace has no exception name/reason and no app frames below main, so the exact race (SwiftUI scroll transaction racing AppKit's display-cycle drag-margin flush) cannot itself be reproduced deterministically; the commit and the test docstring say so explicitly rather than overclaiming.
    - criterion: Identify the responsible view/update and the exception or constraint invariant that fails; record whether the trigger is app-owned layout behavior or an OS-specific SwiftUI/AppKit defect.
      result: pass
      notes: "Verified both .ips crash reports (krma-687-incident-58cc0232.ips, krma-687-sibling-a80dd347.ips) directly: the lastExceptionBacktrace confirms the described path -- NSHostingView.responderNode getter -> AttributeGraph update -> ScrollViewHelper.updateGraphState -> NSHostingView.beginTransaction/setNeedsUpdateConstraints -> _postWindowNeedsUpdateConstraints, invoked from _resetDragMarginsIfNeeded inside NSDisplayCycleFlush. Neither report includes an exception reason, so the fix correctly targets the two concrete app-owned contributors that can schedule an extra scroll-view transaction during that window (a duplicated animation source in InspectorDisclosure.toggle, and a measure/place proposal mismatch in FitsProposedWidth) rather than asserting a specific constraint failure. Whether an OS-level SwiftUI/AppKit re-entrancy defect also underlies this is explicitly left open in the code comments, consistent with the evidence."
    - criterion: Implement a focused fix or documented workaround that prevents the exception during the affected scroll-view, inspector, and window-drag interactions.
      result: pass
      notes: "InspectorDisclosure.swift: removed the duplicate `.animation(value: isExpanded)` modifier (toggle() already applies withAnimation, so the modifier only stacked a second transaction on the scroll view's content size) and made FitsProposedWidth cache and reuse the exact ProposedViewSize from sizeThatFits in placeSubviews, eliminating a measure/place mismatch that could otherwise keep the scroll content size churning. Both changes are localized and consistent with the crash's mechanism."
    - criterion: Add regression coverage for the identified app-side trigger where it can be exercised deterministically, and verify the affected flow on macOS 27.2 or a matching runtime.
      result: pass
      notes: "InspectorScrollCrashPathTests covers both fixed invariants: stable FitsProposedWidth sizing across repeated layout passes, and a disclosure toggle storm interleaved with window resizes settling back to the original collapsed size in a real hosted NSWindow. Ran locally on macOS 27.2 (this verification's runtime); both tests pass."
  checks_run:
    - swift build
    - swift test --filter InspectorScrollCrashPathTests (pass, 2/2)
    - swift test --no-parallel --filter InspectorScrollCrashPathTests (pass, 2/2, post-fix)
    - "scripts/ci-tests.sh verify (lane partition reconciles: total=1822 fast=1330 serial=442 optional=50)"
    - scripts/ci-tests.sh serial (13 pre-existing KeyMonitorTests failures, reproduced identically on the pre-fix parent commit dd9effb^ in an isolated worktree; unrelated to this change)
    - scripts/ci-tests.sh fast, run twice (each run failed exactly one ThumbnailSwitchLifecycleTests test, a different one each time; both pass standalone with swift test --filter; this file doesn't reference InspectorDisclosure/FitsProposedWidth -- pre-existing parallel-lane flakiness, filed as KRMA-688)
    - Manual review of .dg/assets/KRMA-687/krma-687-incident-58cc0232.ips and krma-687-sibling-a80dd347.ips lastExceptionBacktrace against the fix's mechanism
  findings:
    - "scripts/ci-tests.sh: InspectorScrollCrashPathTests drives real NSWindow/NSHostingView display cycles (layoutIfNeeded/displayIfNeeded, RunLoop pumps) but was left out of serial_filter, so scripts/ci-tests.sh fast would run it under swift test --parallel instead of the serial Core Image/render/AppKit lane CLAUDE.md specifies for this class of test -- risking CI flakiness in exactly the AppKit display-cycle machinery this suite exists to exercise deterministically. Fixed by adding it to serial_filter."
  fixes:
    - "scripts/ci-tests.sh: added InspectorScrollCrashPathTests to serial_filter so it runs in the required serial AppKit/UI lane instead of the parallel fast lane."
  verification_commits:
    - 8d5d194
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T20:38:22.365Z
  session: 01MULOY6JWKLA0G82P
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - crash
  - ui
  - scrollview
created: 2026-09-28T16:41:27.392Z
updated: 2026-09-28T20:38:22.367Z
blockers: []
order: a0
board: product
commits:
  - 8d5d194
---

## Objective

Reproduce and resolve the AppKit constraint exception that terminated Kromora while SwiftUI was
updating a hosted scroll view.

## Context

Crash report: 2026-09-28 10:39:59 MDT, Kromora 0.1 (build 1), Apple Silicon Mac16,11,
macOS 27.2 (26B5091g). The process aborted on the main thread after an `NSException` escaped
AppKit's `-[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints]`.

The stack narrows the failure to a SwiftUI/AppKit layout and hit-testing update: AppKit asks
`NSHostingView` to begin a transaction; SwiftUI updates `ScrollViewHelper` and
`HostingScrollView`; AttributeGraph then resolves the hosting view's responder during AppKit's
opaque-region / window-drag-margin calculation. AppKit is already flushing a display-cycle
transaction. The report does not include the exception reason, any Auto Layout constraint details,
or app frames below `main`, so it does not identify the exact scroll view or prove an app-side
constraint cycle.

Leading area to investigate: the editor's vertically scrolling inspector surfaces
(`InspectorScrollingContent` in `InspectorDisclosure.swift`, which wraps content in `FitsProposedWidth`)
and their updates while AppKit recalculates draggable window regions. The Photos state-capture
thread is unrelated to the crashing main-thread stack. No evidence in this report points to the
render or Metal pipeline.

The exact user action immediately before the crash and a symbolic app backtrace are not available;
capture both if the crash can be reproduced.

## Acceptance criteria

- [ ] Establish reproducible steps or a deterministic regression harness for the crash path.
- [ ] Identify the responsible view/update and the exception or constraint invariant that fails;
      record whether the trigger is app-owned layout behavior or an OS-specific SwiftUI/AppKit defect.
- [ ] Implement a focused fix or documented workaround that prevents the exception during the
      affected scroll-view, inspector, and window-drag interactions.
- [ ] Add regression coverage for the identified app-side trigger where it can be exercised
      deterministically, and verify the affected flow on macOS 27.2 or a matching runtime.

## Implementation notes

Use the supplied incident `58CC0232-D467-44FA-89FA-3729C5939231` as the crash reference. Preserve
the full report with the issue or attach it if local workflow supports attachments. Do not claim a
specific constraint failure from this report alone: the `Last Exception Backtrace` omits the
exception name/reason. Compare inspector tabs and disclosure states, source-switch updates, and
window dragging while a sidebar scroll view is hosted. If a runtime capture is available, collect
the exception reason and symbolicate against the exact distributed binary before changing layout
behavior.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-28T20:38:22.365Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Establish reproducible steps or a deterministic regression harness for the crash path. (pass) — InspectorScrollCrashPathTests.swift adds a deterministic harness driving a real NSWindow/NSHostingView through AppKit's display-cycle (window resize + disclosure toggle storms interleaved) that would abort the test process if the app-owned layout invariants regressed. The report's own Last Exception Backtrace has no exception name/reason and no app frames below main, so the exact race (SwiftUI scroll transaction racing AppKit's display-cycle drag-margin flush) cannot itself be reproduced deterministically; the commit and the test docstring say so explicitly rather than overclaiming.
- [x] Identify the responsible view/update and the exception or constraint invariant that fails; record whether the trigger is app-owned layout behavior or an OS-specific SwiftUI/AppKit defect. (pass) — Verified both .ips crash reports (krma-687-incident-58cc0232.ips, krma-687-sibling-a80dd347.ips) directly: the lastExceptionBacktrace confirms the described path -- NSHostingView.responderNode getter -> AttributeGraph update -> ScrollViewHelper.updateGraphState -> NSHostingView.beginTransaction/setNeedsUpdateConstraints -> _postWindowNeedsUpdateConstraints, invoked from _resetDragMarginsIfNeeded inside NSDisplayCycleFlush. Neither report includes an exception reason, so the fix correctly targets the two concrete app-owned contributors that can schedule an extra scroll-view transaction during that window (a duplicated animation source in InspectorDisclosure.toggle, and a measure/place proposal mismatch in FitsProposedWidth) rather than asserting a specific constraint failure. Whether an OS-level SwiftUI/AppKit re-entrancy defect also underlies this is explicitly left open in the code comments, consistent with the evidence.
- [x] Implement a focused fix or documented workaround that prevents the exception during the affected scroll-view, inspector, and window-drag interactions. (pass) — InspectorDisclosure.swift: removed the duplicate `.animation(value: isExpanded)` modifier (toggle() already applies withAnimation, so the modifier only stacked a second transaction on the scroll view's content size) and made FitsProposedWidth cache and reuse the exact ProposedViewSize from sizeThatFits in placeSubviews, eliminating a measure/place mismatch that could otherwise keep the scroll content size churning. Both changes are localized and consistent with the crash's mechanism.
- [x] Add regression coverage for the identified app-side trigger where it can be exercised deterministically, and verify the affected flow on macOS 27.2 or a matching runtime. (pass) — InspectorScrollCrashPathTests covers both fixed invariants: stable FitsProposedWidth sizing across repeated layout passes, and a disclosure toggle storm interleaved with window resizes settling back to the original collapsed size in a real hosted NSWindow. Ran locally on macOS 27.2 (this verification's runtime); both tests pass.
Checks run:
- swift build
- swift test --filter InspectorScrollCrashPathTests (pass, 2/2)
- swift test --no-parallel --filter InspectorScrollCrashPathTests (pass, 2/2, post-fix)
- scripts/ci-tests.sh verify (lane partition reconciles: total=1822 fast=1330 serial=442 optional=50)
- scripts/ci-tests.sh serial (13 pre-existing KeyMonitorTests failures, reproduced identically on the pre-fix parent commit dd9effb^ in an isolated worktree; unrelated to this change)
- scripts/ci-tests.sh fast, run twice (each run failed exactly one ThumbnailSwitchLifecycleTests test, a different one each time; both pass standalone with swift test --filter; this file doesn't reference InspectorDisclosure/FitsProposedWidth -- pre-existing parallel-lane flakiness, filed as KRMA-688)
- Manual review of .dg/assets/KRMA-687/krma-687-incident-58cc0232.ips and krma-687-sibling-a80dd347.ips lastExceptionBacktrace against the fix's mechanism
Findings:
- scripts/ci-tests.sh: InspectorScrollCrashPathTests drives real NSWindow/NSHostingView display cycles (layoutIfNeeded/displayIfNeeded, RunLoop pumps) but was left out of serial_filter, so scripts/ci-tests.sh fast would run it under swift test --parallel instead of the serial Core Image/render/AppKit lane CLAUDE.md specifies for this class of test -- risking CI flakiness in exactly the AppKit display-cycle machinery this suite exists to exercise deterministically. Fixed by adding it to serial_filter.
Fixes:
- scripts/ci-tests.sh: added InspectorScrollCrashPathTests to serial_filter so it runs in the required serial AppKit/UI lane instead of the parallel fast lane.
Verification commits:
- 8d5d194
Actor: claude
Resolved model: sonnet
Pickup session: 01MULOY6JWKLA0G82P
Summary: Verified: fix matches the crash mechanism confirmed in both .ips reports, regression tests pass, lane-scheduling gap fixed (InspectorScrollCrashPathTests moved to the serial lane). Filed KRMA-688 for pre-existing, unrelated ThumbnailSwitchLifecycleTests parallel-lane flakiness.
