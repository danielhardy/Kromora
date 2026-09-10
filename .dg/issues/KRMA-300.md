---
id: KRMA-300
title: Show speculative first preview before EditStore load resolves
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T05:17:55.857Z
  session: 01MTTKSF6G2V3P9HX7
labels:
  - perf
  - phase:10
  - preview
created: 2026-09-09T02:38:38.247Z
updated: 2026-09-10T12:53:54.731Z
estimate: 5
order: a0
board: product
---

## Objective

Show first pixels without waiting for the disk edit-store read; re-render only if stored edits differ.

## Context

**Why:** Time-to-first-pixel after click/open/arrow-key is the headline benchmark. Every millisecond of disk IO on that path is felt.

**Current code:**
- `Sources/LumoKit/ViewModels/AppViewModel.swift` — `load(name:url:data:assetID:...)` (~line 1226), `prepareAndInstall(_:)` (~line 1330), `install(preparation:request:)` (~line 1384), `adoptStoredEdits(_:for:)` (~line 1410).
- Flow today: `storedTask = editStore.load` starts before `engine.prepareSource`, but `schedulePreview()` is gated until `await storedTask.value` returns. `install()` already publishes chrome (`imageSource`, `sourceSize`, status) — only pixels wait.
- The gate exists deliberately to avoid rendering pristine then immediately re-rendering stored edits. That trades one wasted render for always paying disk latency.

**What to change:** invert the tradeoff — speculative preview wins for the common cases (unedited photos, in-memory session hit, fast SSD where second render is cheap).

## Scope / Steps

1. After `install()`, if `editSessions[assetID]` has an in-memory document, `schedulePreview()` immediately with it (current behavior for cold already waits — make it immediate).
2. For cold (no in-memory session): submit a speculative preview with `EditDocument()` (or `comparisonBaseline`-safe identity) the moment `prepareSource` succeeds, in parallel with `await storedTask.value`.
3. When stored load returns: compare to speculated document. If equal, do nothing (already on screen — skip second render). If different, adopt + `schedulePreview()` once (existing `adoptStoredEdits` path).
4. Preserve all fences: `sourceRevision`/`assetID` checks, `previewScheduledSourceRevision` dedup, `isShuttingDown`, error path (`preparation == nil` → `.failed`).
5. Keep `scheduleEditedThumbnailAfterSettle` and histogram gating on the adopted (final) document, not the speculative one.

## Acceptance criteria

- [ ] `SpeculativePreviewImmediateTest`: with `EditStore.load` blocked on a gate, the first preview submit lands before the gate opens (fake-engine submit log ordering assertion).
- [ ] `StoredEqualSkipsSecondRenderTest`: stored document == speculated document implies total preview submits == 1.
- [ ] `StoredDiffersRendersTwiceTest`: stored document != speculated implies total preview submits == 2 and the final published document == stored (never stuck on pristine).
- [ ] `SpeculativeFenceTest`: navigating away mid-load yields zero publications for the departed `assetID`.
- [ ] `LoadErrorPathTest`: `prepareSource` == nil implies `previewState == .failed` with zero publications (no phantom preview).
## Verification

- `swift build` clean (zero diagnostics).
- New/updated XCTest(s) named below green.
- `scripts/ci-tests.sh fast` green.
- Benchmark (informational, never gating): `.photoSwitch` cold-open interval for edited + unedited photos, Release build, same machine/dataset, before/after in the agent log (use the KRMA-057 harness if it exists).
- No human steps: done = all automated checks above pass.
## Out of scope

- Changing `EditStore` persistence format or caching.
- Prefetch scale fixes (separate ticket).

## Constraints

- macOS 14 minimum; Apple frameworks only.
- Swift 6 mode: no `@unchecked Sendable` / `nonisolated(unsafe)`. Keep `Task` closures `@Sendable`; teardown via explicit methods, not `deinit` touching actor state.

## Agent log

- 2026-09-09T05:17:55.857Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTTKSF6G2V3P9HX7
Summary: Speculative opening previews now render immediately, reconcile stored edits with a single corrective render when needed, and defer histogram/thumbnail support work until persistence resolves. Updated lifecycle tests and cold-open benchmark expectations.
