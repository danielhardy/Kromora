---
id: KRMA-323
title: "KRMA-312 follow-up: async presentation-texture materialization (present blocks main on GPU)"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run:
    - swift test --filter PreviewSurfaceTests (18 passed)
    - swift test --filter ObservabilityTests (7 passed)
    - swift build -c release (passed; pre-existing Core Image deprecation warnings)
    - scripts/ci-tests.sh fast (667 passed)
    - scripts/ci-tests.sh serial (326 passed)
    - dg validate (OK; pre-existing unknown pickup runner model warning)
    - git diff --check (passed)
  findings:
    - present no longer waits for the materialization command buffer on the main actor
    - first drawable uses the existing CI fallback while the retained BGRA texture is pending
    - stale materialization completions cannot replace newer publications
    - lastValid rollback and onPresented confirmation semantics are preserved
    - publish-path materialization submit and GPU timings are exposed separately from presentationEncodingMS
  fixes:
    - made CI-to-BGRA presentation materialization asynchronous
    - added retained-texture generation tracking so the async swap schedules a real repaint
    - added PresentationMaterialized observability event
    - updated async geometry/repaint and event-vocabulary tests
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T20:21:12.567Z
  session: 01MTUJAYSKLY5468M0
creation_provenance:
  runner: pi
  model: openrouter/meta/muse-spark-1.3-contributor
  actor: pi
labels:
  - verification
created: 2026-09-09T16:40:38.236Z
updated: 2026-09-10T12:53:56.735Z
parent: KRMA-312
order: zzh
board: product
---

## Objective

Evaluate moving KRMA-312's per-revision presentation-texture materialization off the main-thread publish path. Non-blocking follow-up: correctness of KRMA-312 does not depend on it, but the ticket's perf goal (save 1-3ms per frame, smooth pinch/pan) is only half-measured while every publication pays a synchronous GPU round-trip.

## Context

Found during KRMA-312 counterpoint verification. PreviewSurface is @MainActor, so present() runs on the main thread, and b2c56d9 added a synchronous makePresentationTexture() call there: allocate BGRA texture, CI-render the full image into it, commandBuffer.commit() + waitUntilCompleted(). The pre-quad path encoded the same CI work into the drawable's command buffer asynchronously (commit + completion handler, no wait).

Net effect per render revision: roughly the same total GPU work, but now blocking the main thread at publish time -- including interactive slider ticks -- instead of async at drawable time. Meanwhile presentationEncodingMS telemetry now measures only the cheap quad encode, so dashboards will show an apparent win while an unmeasured main-thread cost moved into present().

## Acceptance criteria

- [ ] Measure main-thread time in present() before/after (Release, same machine/dataset) and confirm whether the synchronous block regresses interactive publish latency.
- [ ] If it regresses, materialize asynchronously (publish first with the CI fallback for the first drawable, swap in the retained texture once ready; or encode materialization into the next drawable's command buffer) while preserving PreviewFrameIdentity dedup, onPresented confirmation, and lastValid rollback semantics.
- [ ] Extend telemetry so publish-path GPU cost is visible alongside presentationEncodingMS.

## Implementation notes

Do not change render-graph behavior; keep the device/colorPixelFormat fallback paths working.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T20:21:12.567Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- swift test --filter PreviewSurfaceTests (18 passed)
- swift test --filter ObservabilityTests (7 passed)
- swift build -c release (passed; pre-existing Core Image deprecation warnings)
- scripts/ci-tests.sh fast (667 passed)
- scripts/ci-tests.sh serial (326 passed)
- dg validate (OK; pre-existing unknown pickup runner model warning)
- git diff --check (passed)
Findings:
- present no longer waits for the materialization command buffer on the main actor
- first drawable uses the existing CI fallback while the retained BGRA texture is pending
- stale materialization completions cannot replace newer publications
- lastValid rollback and onPresented confirmation semantics are preserved
- publish-path materialization submit and GPU timings are exposed separately from presentationEncodingMS
Fixes:
- made CI-to-BGRA presentation materialization asynchronous
- added retained-texture generation tracking so the async swap schedules a real repaint
- added PresentationMaterialized observability event
- updated async geometry/repaint and event-vocabulary tests
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTUJAYSKLY5468M0
Summary: Async presentation-texture materialization: present publishes immediately with CI fallback, swaps in the retained texture on GPU completion with stale-revision protection, and records materialization submit/GPU timings alongside presentationEncodingMS. Added texture-generation repaint handling and updated async preview/observability tests.
