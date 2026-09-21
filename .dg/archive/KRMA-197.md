---
id: KRMA-197
title: Primary subject ensemble scoring
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Weighted scoring over named signal constants (attention overlap, foreground confidence, face presence, person presence, composition weight, relative size)
      result: pass
    - criterion: Output is a regionID reference plus confidence and a ranked list of secondary subjects
      result: pass
    - criterion: Every decision carries a confidence, clamped to [0,1]
      result: pass
    - criterion: Zero-subject case returns nil/very-low-confidence rather than a forced pick
      result: pass
    - criterion: Pure function over [AnalyzedRegion], no Vision/actors, unit-testable without async
      result: pass
    - criterion: Swift 6 clean, zero escape hatches
      result: pass
    - criterion: Continuous weighted-sum scoring, not nested if/else thresholds, stable pick on near-identical inputs
      result: pass
  checks_run:
    - swift build — clean, no new warnings
    - swift test --filter PrimarySubjectSelectorTests — 5/5 passed
    - swift test --filter PackageSettingsTests — 3/3 passed (Swift 6 mode, zero escape hatches)
    - swift format lint --strict -r PrimarySubjectSelector.swift — clean
    - dg validate — OK (pre-existing unrelated warnings only)
    - git status --porcelain — clean after commit, aside from pre-existing unrelated .dg bookkeeping diffs present before this session
  findings:
    - PrimarySubjectSelector exposed 5 equivalent select() entry points (2 instance methods, 3 static overloads) plus a dead single-candidate score(candidate:in:) overload, and PrimarySubjectSelection carried 3 unused aliases (rankedSecondarySubjects, rankedRegionIDs, primarySubjectID). Repo-wide grep confirmed only the static select(from:) form is ever called, in both LumoKit and its tests.
  fixes:
    - "Removed the 4 redundant select() overloads, the dead score(candidate:in:) overload, and the 3 unused PrimarySubjectSelection aliases from PrimarySubjectSelector.swift. No behavior change: all 5 selector tests and PackageSettingsTests still pass."
  verification_commits:
    - 25cb0d6
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-04T16:03:09.096Z
  session: 01MTN51YBJHUTNMA73
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:54.584Z
updated: 2026-09-10T12:53:46.358Z
depends_on:
  - KRMA-194
order: doha2vmb
board: product
commits:
  - 25cb0d6
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/PrimarySubjectSelector.swift`
**Depends on:** KRMA-194
**Epic:** KRMA-181 — see original proposal §18

## 1. Problem

Given `PhotoAnalysis.regions` (KRMA-194), decide which one (or combination) is "the" primary
subject — without hardcoding "subject = foreground instance #1", which breaks for multi-subject
photos (a couple, a person + dog, two children).

## 2. Requirement (acceptance criteria)

1. A scoring function combining signals already present on each `AnalyzedRegion`: attention
   overlap (from the `.subject`/saliency region), foreground confidence, face presence, person
   presence, composition weight (e.g. rule-of-thirds proximity), relative size — each a named,
   documented weight constant.
2. Output: primary subject as a reference/ID into `PhotoAnalysis.regions`, plus `confidence:
   Float`, and optionally a ranked list of secondary subjects.
3. Every decision carries a `confidence` — feeds KRMA-200's conservative-when-uncertain behavior.
4. Zero-subject case (no faces, no foreground, weak/no saliency) returns nil/very-low-confidence,
   not an arbitrary forced pick.
5. Pure function over `[AnalyzedRegion]` — no Vision, no actors, fully unit-testable without
   async.
6. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Continuous scoring (weighted sum → normalized), not nested if/else thresholds — avoid step-
  function instability where near-identical images flip the pick.

## 4. Where to look

- `docs/ENGINEERING_GUIDE.md, original proposal §18.
- KRMA-194's `PhotoAnalysis.regions` — the only input.

## 5. Testing

- `Tests/LumoKitTests/PrimarySubjectSelectorTests.swift` (new): single dominant region → high
  confidence, correct pick. Multiple similar-weight candidates → deterministic pick (order-
  independent), lower confidence. No candidates → nil/very-low-confidence. Repeated runs on
  near-identical inputs → stable pick.


### Comment — codex @ 2026-09-04T15:58:20.991Z

Implemented primary-subject ensemble scoring in commit fe8aa7b. Added bounds propagation from RegionMask into AnalyzedRegion, documented weighted attention/foreground/face/person/composition/size signals, deterministic order-independent ranking, confidence with runner-up separation, conservative zero/weak-evidence handling, and Codable decision/score values. Verification: selector tests (5/5) pass, PhotoAnalysis assembly tests (3/3) pass, strict Swift format, git diff check, swift build, and dg validate pass. Full swift test executed 785 tests; 15 unrelated timing/lifecycle failures remain as documented in the repository.

## Agent log

- 2026-09-04T16:03:09.097Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Weighted scoring over named signal constants (attention overlap, foreground confidence, face presence, person presence, composition weight, relative size) (pass)
- [x] Output is a regionID reference plus confidence and a ranked list of secondary subjects (pass)
- [x] Every decision carries a confidence, clamped to [0,1] (pass)
- [x] Zero-subject case returns nil/very-low-confidence rather than a forced pick (pass)
- [x] Pure function over [AnalyzedRegion], no Vision/actors, unit-testable without async (pass)
- [x] Swift 6 clean, zero escape hatches (pass)
- [x] Continuous weighted-sum scoring, not nested if/else thresholds, stable pick on near-identical inputs (pass)
Checks run:
- swift build — clean, no new warnings
- swift test --filter PrimarySubjectSelectorTests — 5/5 passed
- swift test --filter PackageSettingsTests — 3/3 passed (Swift 6 mode, zero escape hatches)
- swift format lint --strict -r PrimarySubjectSelector.swift — clean
- dg validate — OK (pre-existing unrelated warnings only)
- git status --porcelain — clean after commit, aside from pre-existing unrelated .dg bookkeeping diffs present before this session
Findings:
- PrimarySubjectSelector exposed 5 equivalent select() entry points (2 instance methods, 3 static overloads) plus a dead single-candidate score(candidate:in:) overload, and PrimarySubjectSelection carried 3 unused aliases (rankedSecondarySubjects, rankedRegionIDs, primarySubjectID). Repo-wide grep confirmed only the static select(from:) form is ever called, in both LumoKit and its tests.
Fixes:
- Removed the 4 redundant select() overloads, the dead score(candidate:in:) overload, and the 3 unused PrimarySubjectSelection aliases from PrimarySubjectSelector.swift. No behavior change: all 5 selector tests and PackageSettingsTests still pass.
Verification commits:
- 25cb0d6
Actor: claude
Resolved model: sonnet
Pickup session: 01MTN51YBJHUTNMA73
Summary: Verified primary-subject ensemble scoring: weighted continuous scoring, confidence, and zero-evidence handling all match acceptance criteria; tests and Swift 6 concurrency checks pass. Removed dead/duplicate API surface (unused select() overloads and result aliases) as a localized cleanup.
