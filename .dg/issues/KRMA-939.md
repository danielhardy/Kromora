---
id: KRMA-939
title: Remove backup/restore and document-type claims from README, scope docs and Info.plist
type: task
status: backlog
priority: medium
human_review_required: false
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
updated: 2026-10-13T14:48:32.509Z
parent: KRMA-922
depends_on:
  - KRMA-936
blockers: []
order: nomqiy3a
board: product
---

## Objective

If KRMA-936 decided NOT to ship backup/restore and/or Open Library, make the product materials stop
promising them.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M6. Only do the parts the KRMA-936 decision selected.

- `README.md` and `docs/PRODUCT_SCOPE.md` list "verified backup/restore" in the MVP and release bar.
- `App/Info.plist` declares `CFBundleDocumentTypes` / exported type for `com.kromora.kromoralibrary`
  (role Editor, rank Owner). Removing the document-type entry (keep the exported UTI declaration if
  other code relies on the type) means Finder stops offering Kromora as the opener.
- Structural tests may pin Info.plist contents: `grep -rn "CFBundleDocumentTypes\|kromoralibrary"
  Tests Xcode scripts docs`; `scripts/verify-library-package-metadata.sh` verifies package metadata.
- Keep the model code (`PortableLibraryBackup`/`Restore`); only claims change.

## Acceptance criteria

- [ ] README/PRODUCT_SCOPE (and any other doc found by `grep -rniE "backup|restore" README.md docs`)
      no longer list backup/restore as shipped; they list it as post-MVP with a pointer to the dormant
      model code.
- [ ] (If decided) the `CFBundleDocumentTypes` entry is removed and any test/script that asserted it is
      updated accordingly.
- [ ] `scripts/ci-tests.sh fast` exits 0; `scripts/verify-library-package-metadata.sh` still passes
      (if it can run without a signed build; otherwise say so).
- [ ] The release bar in `docs/PRODUCT_SCOPE.md` is internally consistent after the edit (no dangling
      references to the removed items).
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
