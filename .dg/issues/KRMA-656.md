---
id: KRMA-656
title: Improve the About screen
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Place the app icon at the top of the About window, with the app name directly beneath it.
      result: pass
    - criterion: Show the app version and append the current Git commit identifier when build metadata makes it available; omit the commit identifier cleanly when unavailable.
      result: pass
      notes: KromoraAboutMetadata reads KromoraGitCommit from Info.plist; build-macos-app.sh injects git rev-parse --short=12 HEAD, or removes the key when git is unavailable. versionLabel omits the separator/id cleanly when nil.
    - criterion: Remove the full license text and the individual included LUT listing; show a concise statement that all included LUTs are released under the MIT License.
      result: pass
      notes: View now shows a single concise MIT statement plus an external license link; no per-LUT GroupBox/listing remains.
    - criterion: Keep the About window readable and visually balanced at its existing window size.
      result: pass
      notes: Window frame (minWidth 360/idealWidth 420, minHeight 440/idealHeight 520) in KromoraApp.swift is unchanged.
  checks_run:
    - swift build
    - swift test --filter KromoraAboutTests (5/5 passed)
    - scripts/ci-tests.sh fast (1277/1277 passed)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T17:45:37.035Z
  session: 01MUK3UIKZONRHOKIK
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
created: 2026-09-27T17:17:48.860Z
updated: 2026-09-27T17:45:37.037Z
blockers: []
order: a0
board: product
---

## Objective

Make the About window a concise, polished identity and build information screen.

## Context

The current About window shows the full MIT license text and a per-LUT listing. The included starter LUTs all use the project MIT license, so the full text and inventory add unnecessary detail.

## Acceptance criteria

- [ ] Place the app icon at the top of the About window, with the app name directly beneath it.
- [ ] Show the app version and append the current Git commit identifier when build metadata makes it available; omit the commit identifier cleanly when unavailable.
- [ ] Remove the full license text and the individual included LUT listing; show a concise statement that all included LUTs are released under the MIT License.
- [ ] Keep the About window readable and visually balanced at its existing window size.

## Implementation notes

- Main view: `Sources/KromoraKit/Views/KromoraAboutView.swift`.
- Check the app's build settings and packaging path for a reliable commit identifier source, with a development-build fallback.


### Comment — codex @ 2026-09-27T17:40:59.785Z

Implemented and committed as baddfc6. The About window now shows the app icon, name, version, and optional Git commit ID; it replaces the full license and LUT inventory with a concise MIT statement. Packaged builds inject the short commit ID from Git; development runs omit it cleanly. Verification: swift build passed; test suite not run.

## Agent log

- 2026-09-27T17:45:37.035Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Place the app icon at the top of the About window, with the app name directly beneath it. (pass)
- [x] Show the app version and append the current Git commit identifier when build metadata makes it available; omit the commit identifier cleanly when unavailable. (pass) — KromoraAboutMetadata reads KromoraGitCommit from Info.plist; build-macos-app.sh injects git rev-parse --short=12 HEAD, or removes the key when git is unavailable. versionLabel omits the separator/id cleanly when nil.
- [x] Remove the full license text and the individual included LUT listing; show a concise statement that all included LUTs are released under the MIT License. (pass) — View now shows a single concise MIT statement plus an external license link; no per-LUT GroupBox/listing remains.
- [x] Keep the About window readable and visually balanced at its existing window size. (pass) — Window frame (minWidth 360/idealWidth 420, minHeight 440/idealHeight 520) in KromoraApp.swift is unchanged.
Checks run:
- swift build
- swift test --filter KromoraAboutTests (5/5 passed)
- scripts/ci-tests.sh fast (1277/1277 passed)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUK3UIKZONRHOKIK
Summary: Verified About window changes: icon/name layout, version+commit label with clean omission, concise MIT LUT statement, unchanged window size. swift build and full fast test lane (1277 tests) pass; no fixes needed.
