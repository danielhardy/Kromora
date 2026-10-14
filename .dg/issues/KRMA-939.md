---
id: KRMA-939
title: Remove backup/restore and document-type claims; document manual copy as the supported path
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: README, PRODUCT_SCOPE, and current-facing supporting documentation describe verified backup/restore as post-MVP and point to the unwired model code.
      result: pass
      notes: Reviewed all README.md and docs backup/restore hits. Clarified the engineering guide, documentation map, historical plan, and package format; preserved historical design material with an explicit unwired-code notice.
    - criterion: STORAGE_POLICY.md documents the supported manual copy path and marks backup/restore semantics as unwired model code.
      result: pass
      notes: The guide says to quit Kromora, copy the package, use Time Machine for ~/Pictures, and use the default path or Settings > Choose Library… to use a copy.
    - criterion: CFBundleDocumentTypes is absent, the package UTI declaration remains, and metadata assertions/documentation reflect that.
      result: pass
      notes: The metadata script verifies document registration stays absent while checking the exported package UTI; the script index now states that accurately.
    - criterion: The PRODUCT_SCOPE.md release bar is internally consistent with the post-MVP backup/restore boundary.
      result: pass
      notes: The MVP workflow uses quit-and-copy and Choose Library; verified package backup/restore appears under post-MVP boundaries.
    - criterion: scripts/verify-library-package-metadata.sh passes.
      result: pass
      notes: Passed with exit status 0.
    - criterion: swift build is warning-free and Swift 6 mode remains clean.
      result: pass
      notes: Build completed with zero diagnostics. The fast lane passed its package settings invariant tests; no prohibited Swift 6 escape hatches or availability branches were found in production sources.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: Passed with exit status 0; all 1,882 selected tests completed.
  checks_run:
    - zsh scripts/verify-library-package-metadata.sh — passed (exit 0)
    - swift build — passed without warnings or diagnostics (exit 0)
    - scripts/ci-tests.sh fast — passed, 1,882/1,882 selected tests (exit 0)
    - rg documentation and plist structural audits — reviewed all relevant current-facing matches; no stale shipped-feature claim remains
    - git diff --check — passed (exit 0)
  findings: []
  fixes:
    - Clarified that backup/restore references in supporting documentation describe unwired model code, and corrected the metadata script index to say the Finder document type is absent.
  verification_commits:
    - ad1cbaa2
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T01:14:38.345Z
  session: 01MV7EXLL7GK31FRSP
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - docs
  - library
created: 2026-10-13T14:47:49.189Z
updated: 2026-10-14T01:14:38.348Z
parent: KRMA-922
depends_on:
  - KRMA-936
blockers: []
order: z
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T00:55:26.485Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - ad1cbaa2
---

## Objective

Implement ADR-936: the MVP no longer promises verified backup/restore or Finder-open of a library.
Make the product materials match, and document the manual copy path.

## Context

Decision: `.dg/decisions/ADR-936-*.md` (supersedes the conditional wording of KRMA-936). Review finding M6 in
`.context/2026-10-13-release-readiness-review.md`. Both parts of this ticket are selected.

- `README.md` (~L47, ~L67) and `docs/PRODUCT_SCOPE.md` (~L29, ~L44, ~L63, ~L79) list "verified
  backup/restore" / "package backup/restore". `docs/STORAGE_POLICY.md` has a "Backup and restore
  semantics" section (~L97) describing the dormant model code.
- `App/Info.plist` declares `CFBundleDocumentTypes` (~L21, role Editor, rank Owner) for
  `com.kromora.kromoralibrary`. Remove that array entry; KEEP the exported/imported UTI declaration
  (~L55-60) because the package type is still used.
- Structural tests may pin Info.plist contents: `grep -rn "CFBundleDocumentTypes\|kromoralibrary"
  Tests Xcode scripts docs`; `scripts/verify-library-package-metadata.sh` verifies package metadata.
- Keep `PortableLibraryBackup` / `PortableLibraryRestore` and their tests unchanged; only claims change.
- KRMA-988 adds a Settings "Choose Library…" (relaunch-based); reference it as the way to use a copied
  library, but do not describe it as shipped until it lands.

## Acceptance criteria

- [ ] README, `docs/PRODUCT_SCOPE.md` and any other hit of `grep -rniE "backup|restore" README.md docs`
      list verified backup/restore as post-MVP with a pointer to the dormant model code, not as shipped.
- [ ] `docs/STORAGE_POLICY.md` gets a short "Moving or backing up a library" section: quit Kromora,
      copy the `.kromoralibrary` package (Time Machine covers `~/Pictures`), and to use a copy place it
      at the default path or (after KRMA-988) choose it in Settings. Mark the existing "Backup and
      restore semantics" section as describing unwired model code.
- [ ] The `CFBundleDocumentTypes` entry is removed from `App/Info.plist`; the UTI declaration stays; any
      test/script that asserted the document type is updated.
- [ ] The release bar in `docs/PRODUCT_SCOPE.md` is internally consistent (no dangling references).
- [ ] `scripts/verify-library-package-metadata.sh` still passes (if it needs a signed build, say so).
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).


### Comment — claude @ 2026-10-14T00:55:23.207Z

Removed CFBundleDocumentTypes (UTI export kept); verify-library-package-metadata.sh now asserts the document type stays absent and passes (run with zsh). README, PRODUCT_SCOPE, STORAGE_POLICY, LIBRARY_PACKAGE_FORMAT updated: backup/restore is post-MVP/unwired, new 'Moving or backing up a library' section (Settings > Choose Library… already exists in tree via KRMA-988). swift build clean; ci-tests.sh fast exit 0 on re-run (first run flaked once on DeriveCoordinatorTests.testStaleSuccessAfterDismissDoesNotPublish, passes alone and on re-run).

## Agent log

- 2026-10-14T01:14:38.345Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] README, PRODUCT_SCOPE, and current-facing supporting documentation describe verified backup/restore as post-MVP and point to the unwired model code. (pass) — Reviewed all README.md and docs backup/restore hits. Clarified the engineering guide, documentation map, historical plan, and package format; preserved historical design material with an explicit unwired-code notice.
- [x] STORAGE_POLICY.md documents the supported manual copy path and marks backup/restore semantics as unwired model code. (pass) — The guide says to quit Kromora, copy the package, use Time Machine for ~/Pictures, and use the default path or Settings > Choose Library… to use a copy.
- [x] CFBundleDocumentTypes is absent, the package UTI declaration remains, and metadata assertions/documentation reflect that. (pass) — The metadata script verifies document registration stays absent while checking the exported package UTI; the script index now states that accurately.
- [x] The PRODUCT_SCOPE.md release bar is internally consistent with the post-MVP backup/restore boundary. (pass) — The MVP workflow uses quit-and-copy and Choose Library; verified package backup/restore appears under post-MVP boundaries.
- [x] scripts/verify-library-package-metadata.sh passes. (pass) — Passed with exit status 0.
- [x] swift build is warning-free and Swift 6 mode remains clean. (pass) — Build completed with zero diagnostics. The fast lane passed its package settings invariant tests; no prohibited Swift 6 escape hatches or availability branches were found in production sources.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — Passed with exit status 0; all 1,882 selected tests completed.
Checks run:
- zsh scripts/verify-library-package-metadata.sh — passed (exit 0)
- swift build — passed without warnings or diagnostics (exit 0)
- scripts/ci-tests.sh fast — passed, 1,882/1,882 selected tests (exit 0)
- rg documentation and plist structural audits — reviewed all relevant current-facing matches; no stale shipped-feature claim remains
- git diff --check — passed (exit 0)
Findings:
- None
Fixes:
- Clarified that backup/restore references in supporting documentation describe unwired model code, and corrected the metadata script index to say the Finder document type is absent.
Verification commits:
- ad1cbaa2
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7EXLL7GK31FRSP
Summary: Pass: documentation, metadata, build, and fast-lane verification succeeded; clarified unwired backup/restore references.
