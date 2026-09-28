---
id: KRMA-687
title: Investigate AppKit constraint exception during SwiftUI scroll view updates
type: bug
status: ready
priority: medium
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
thinking: xhigh
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - crash
  - ui
  - scrollview
created: 2026-09-28T16:41:27.392Z
updated: 2026-09-28T17:29:04.860Z
blockers: []
order: a0
board: product
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
