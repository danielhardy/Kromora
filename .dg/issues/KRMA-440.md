---
id: KRMA-440
title: Hide photo names on thumbnails by default (library and filmstrip)
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Fresh install / no persisted preference: photo names are hidden by default in both the library grid and the filmstrip."
      result: pass
      notes: KromoraSettings.init falls back to false when Key.showPhotoNames is absent (lines 121, 128); both LibraryGridView.swift:231 and FilmstripView.swift:170 gate the name Text purely on settings.showPhotoNames, so both surfaces inherit the new default.
    - criterion: The 'Show Photo Names' menu toggle still works to turn names back on, and the preference persists across relaunch.
      result: pass
      notes: MenuCommands.swift:32 Toggle is unchanged; didSet on showPhotoNames persists to UserDefaults; testPhotoNameVisibilityPersistsAcrossRelaunch exercises exactly this path.
    - criterion: Existing users who never touched the setting default to off going forward, without silently overriding an explicit opt-in.
      result: pass
      notes: "preferences.object(forKey:) as? Bool ?? false only supplies the new default when the key is genuinely absent; an explicit stored true (or false) is read back unchanged. migrateValue(from: 'Lumo.settings.showPhotoNames', ...) still copies a legacy explicit value into the new key before this fallback runs, so legacy opt-ins/opt-outs also survive. Covered by testLegacySettingsAreCopiedIntoKromoraNamespace."
  checks_run:
    - Manual code review of KromoraSettings.swift default/migration logic (init, migrateValue)
    - Manual verification of both consumers (LibraryGridView.swift:231, FilmstripView.swift:170) and MenuCommands.swift:32
    - Reviewed existing test coverage in KromoraSettingsTests.swift (testPhotoNameVisibilityPersistsAcrossRelaunch, testLegacySettingsAreCopiedIntoKromoraNamespace)
    - git status --porcelain (attempted) and swift build/swift test (attempted) — both blocked by an unaccepted Xcode Command Line Tools license in this sandbox (sudo password required, non-interactive), consistent with the implementer's own report of the same environment blocker
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-18T15:18:10.642Z
  session: 01MU73QK5F61FCDDZE
labels:
  - ui
  - ux
  - library
created: 2026-09-18T02:23:00.510Z
updated: 2026-09-18T15:18:10.644Z
order: a0
board: product
---

## Objective

Photo names currently render under every thumbnail in both the library grid and the filmstrip by default. Change the default to hidden — names should be an opt-in, not the default, in both surfaces.

## Context

The toggle already exists end-to-end, so this is a default-value change plus verifying both consumers respect it:

- `Sources/KromoraKit/Models/KromoraSettings.swift` — `@Published public var showPhotoNames` (around line 86-89), currently defaulting to `true`, persisted under `Key.showPhotoNames` (line ~67), with migration from a legacy "Lumo" key (line ~316).
- `Sources/KromoraKit/Views/MenuCommands.swift:32` — `Toggle("Show Photo Names", isOn: $settings.showPhotoNames)` already exposes this in the menu.
- Consumers: `Sources/KromoraKit/Views/LibraryGridView.swift` (~line 230-238) and `Sources/KromoraKit/Views/FilmstripView.swift` (~line 170-178) both gate the name `Text` with `if settings.showPhotoNames { ... }`.

So the fix is: flip the stored default to `false` (and decide whether existing users' persisted `true` value should be respected or reset — likely just change the default for new installs, since it's a `@Published`/`UserDefaults`-backed setting already migrated once before).

## Acceptance criteria

- [ ] Fresh install / no persisted preference: photo names are hidden by default in both the library grid and the filmstrip.
- [ ] The "Show Photo Names" menu toggle still works to turn names back on, and the preference persists across relaunch.
- [ ] Existing users who never touched the setting see it default to off going forward (confirm intended migration behavior with a short note in the PR — don't silently break users who explicitly turned it on if that's distinguishable from the default).

## Out of scope

- Any other thumbnail metadata overlays (ratings, flags, badges) — only photo name text.


### Comment — codex @ 2026-09-18T15:16:51.844Z

Implemented in commit 0375eae. KromoraSettings now defaults showPhotoNames to false when no preference exists; explicit persisted values, including true, remain unchanged, so untouched existing users and fresh installs default off without overriding opt-ins. Updated KromoraSettingsTests to cover the off-by-default and on-after-relaunch behavior. Verification: git show --check passed; dg validate passed with existing model-name warnings. swift test --filter KromoraSettingsTests could not complete because the current tree has an unrelated pre-existing ResolutionPlanner.roi compile error (the initial invocation also hit the unaccepted Xcode license).

## Agent log

- 2026-09-18T15:18:10.642Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Fresh install / no persisted preference: photo names are hidden by default in both the library grid and the filmstrip. (pass) — KromoraSettings.init falls back to false when Key.showPhotoNames is absent (lines 121, 128); both LibraryGridView.swift:231 and FilmstripView.swift:170 gate the name Text purely on settings.showPhotoNames, so both surfaces inherit the new default.
- [x] The 'Show Photo Names' menu toggle still works to turn names back on, and the preference persists across relaunch. (pass) — MenuCommands.swift:32 Toggle is unchanged; didSet on showPhotoNames persists to UserDefaults; testPhotoNameVisibilityPersistsAcrossRelaunch exercises exactly this path.
- [x] Existing users who never touched the setting default to off going forward, without silently overriding an explicit opt-in. (pass) — preferences.object(forKey:) as? Bool ?? false only supplies the new default when the key is genuinely absent; an explicit stored true (or false) is read back unchanged. migrateValue(from: 'Lumo.settings.showPhotoNames', ...) still copies a legacy explicit value into the new key before this fallback runs, so legacy opt-ins/opt-outs also survive. Covered by testLegacySettingsAreCopiedIntoKromoraNamespace.
Checks run:
- Manual code review of KromoraSettings.swift default/migration logic (init, migrateValue)
- Manual verification of both consumers (LibraryGridView.swift:231, FilmstripView.swift:170) and MenuCommands.swift:32
- Reviewed existing test coverage in KromoraSettingsTests.swift (testPhotoNameVisibilityPersistsAcrossRelaunch, testLegacySettingsAreCopiedIntoKromoraNamespace)
- git status --porcelain (attempted) and swift build/swift test (attempted) — both blocked by an unaccepted Xcode Command Line Tools license in this sandbox (sudo password required, non-interactive), consistent with the implementer's own report of the same environment blocker
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU73QK5F61FCDDZE
