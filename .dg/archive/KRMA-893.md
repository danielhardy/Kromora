---
id: KRMA-893
title: Give starter Looks a stable ID instead of an install path
type: bug
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Starter Looks have IDs independent of install location; user-imported Looks keep existing identity rules.
      result: pass
      notes: Bundled loading uses manifest IDs; user Looks still default to canonical file paths.
    - criterion: An edit saved by one build resolves its starter Look in another build of the app.
      result: pass
      notes: A second simulated resource directory resolves the saved manifest ID.
    - criterion: A test applies a starter Look, simulates a different bundle path, and asserts the render request still carries the Look.
      result: pass
      notes: Extended the relocation test to resolve a reloaded document and assert the preview render request retains its LUT ID and resolved LUT.
    - criterion: swift build and scripts/ci-tests.sh fast pass.
      result: pass
  checks_run:
    - swift test --filter BundledLookTests/testStarterLookIDIsIndependentOfInstallLocation (pass)
    - swift build (pass)
    - scripts/ci-tests.sh fast (pass; 1719 required fast tests)
  findings: []
  fixes:
    - Extended the relocation test to verify the render request carries the stable starter Look after library resolution.
  verification_commits:
    - dd32b25b988830e0dfce5c1204aa2adceed3a10f
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T19:33:29.187Z
  session: 01MV5NC1UD5GKX5B9O
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - looks
  - persistence
created: 2026-10-12T12:47:35.152Z
updated: 2026-10-12T19:33:29.190Z
blockers: []
order: w
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-12T19:25:51.222Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - dd32b25b988830e0dfce5c1204aa2adceed3a10f
---

## Objective

Give starter Looks a stable ID instead of an install path

## Context

Observed with `log stream` (category `photo-switch`): a saved edit's Look is `LUTID(raw: "/Applications/Kromora.app/Contents/Resources/Kromora_KromoraKit.bundle/.../StarterLooks/infrared-mono.cube")`. `CubeLUT.id` is the full file path, so a starter Look applied in one build (installed app) cannot be matched to the same Look in another build (`swift run`, TestFlight update, moved app). The render then gets `lut == nil` and draws the photo ungraded, which shows as a Look that flashes on photo switch and disappears. Confirmed by the maintainer in both builds. Related: KRMA-894.

## Acceptance criteria

- [ ] Starter (bundled) Looks have an ID independent of the install location (for example a stable name or content hash); user-imported Looks keep their existing identity rules.
- [ ] An edit saved by one build resolves its starter Look in another build of the app.
- [ ] A test applies a starter Look, simulates a different bundle path, and asserts the render request still carries the Look.
- [ ] `swift build` and `scripts/ci-tests.sh fast` pass.

## Implementation notes

No migration is required: only the maintainer has an install and will start over. Check `LUTID`, `CubeLUT.id`, `LookSignature`, and wherever a document's `LUTSettings.lutID` is resolved to a loaded `CubeLUT` for the render request. Keep the zero-third-party and macOS 26 constraints.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-12T19:33:29.187Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Starter Looks have IDs independent of install location; user-imported Looks keep existing identity rules. (pass) — Bundled loading uses manifest IDs; user Looks still default to canonical file paths.
- [x] An edit saved by one build resolves its starter Look in another build of the app. (pass) — A second simulated resource directory resolves the saved manifest ID.
- [x] A test applies a starter Look, simulates a different bundle path, and asserts the render request still carries the Look. (pass) — Extended the relocation test to resolve a reloaded document and assert the preview render request retains its LUT ID and resolved LUT.
- [x] swift build and scripts/ci-tests.sh fast pass. (pass)
Checks run:
- swift test --filter BundledLookTests/testStarterLookIDIsIndependentOfInstallLocation (pass)
- swift build (pass)
- scripts/ci-tests.sh fast (pass; 1719 required fast tests)
Findings:
- None
Fixes:
- Extended the relocation test to verify the render request carries the stable starter Look after library resolution.
Verification commits:
- dd32b25b988830e0dfce5c1204aa2adceed3a10f
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV5NC1UD5GKX5B9O
Summary: Verified stable starter Look identity across simulated bundle relocation; render request retains the resolved Look.
