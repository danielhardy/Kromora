---
id: KRMA-404
title: "Phase 2.4: revisioned XMP/Kromora edit sidecars and embedded Look bytes"
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Edit sidecars are immutable, revisioned (new revision per edit, not in-place overwrite), and round-trip through both the Kromora-native and XMP representations.
      result: pass
      notes: PortableLibraryPackage.appendEditRevision always allocates a new monotonically increasing revision, refuses to overwrite an existing Edits/<n>.json or Metadata/<n>.xmp path, and commits both through the crash-safe transaction layer. testEditRevisionsRoundTripAsNativeAndXMPAndRemainImmutable verifies two successive revisions round-trip identically via readEditRevision/readEditSidecar.
    - criterion: Malformed/truncated XMP is detected on read and handled per the critical-data recovery policy (reported, not silently dropped or crashed on).
      result: pass
      notes: "PortablePackageXMPCodec.decode throws typed PortablePackageError.malformedXMP for empty/truncated/non-well-formed packets, and quarantineMalformedXMP moves the bad packet aside for recovery workflows instead of deleting it silently. Covered by testMalformedXMPIsReportedAndCanBeQuarantined. During verification I found and fixed a related gap: shouldResolveExternalEntities=false does not stop libxml2 from expanding internal DOCTYPE <!ENTITY> definitions (confirmed empirically with a billion-laughs packet), which could exhaust memory before validation ran. Added a DOCTYPE rejection guard in decode() plus a regression test (testXMPWithDOCTYPEEntityBombIsRejectedAsMalformedRatherThanExpanded)."
    - criterion: Look bytes referenced by multiple assets are stored once in the package (deduplicated by content hash), verified by a test that imports the same Look via two different assets.
      result: pass
      notes: appendEditRevision content-addresses Look bytes to Looks/<sha256>.cube and validates any pre-existing blob's checksum before reuse. testEditRevisionsRoundTripAsNativeAndXMPAndRemainImmutable imports identical Look bytes for two different assets and asserts exactly one blob file exists.
    - criterion: Referenced-asset schema fields exist and round-trip but have no UI or resolver wired to them.
      result: pass
      notes: PortablePackageSourceReference reserves storage/relativePath/securityScopedBookmark for a future .referenced case; embeddedSourceURL only resolves .embedded and throws otherwise. testReservedReferencedAssetFieldsRoundTripWithoutResolverBehavior confirms round-trip plus the resolver rejection. Grep found no UI/view-model wiring to .referenced.
    - criterion: swift build, swift test, dg validate, and git diff --check pass.
      result: pass
      notes: swift build clean; dg validate --json ok:true (only pre-existing unrelated model-name warnings); git diff --check clean. Ran the full PortableLibraryPackageTests (7/7, including the new regression test) plus PortablePackageTransactionTests, PortableCacheIdentityTests, and CoordinatorBoundaryTests (all pass, 0 regressions). Did not re-run the full multi-minute swift test suite; the implementer's review-stage run (1389 run, 14 pre-existing unrelated failures in Auto/comparison/export/filmstrip/masking/thumbnail async/UI areas untouched by this change) was accepted as the baseline.
  checks_run:
    - swift build
    - swift test --filter PortableLibraryPackageTests (7/7 pass, incl. new DOCTYPE regression test)
    - swift test --filter 'PortablePackageTransactionTests|PortablePackageLeaseTests|PortableCacheIdentityTests|CoordinatorBoundaryTests' (17/17 pass)
    - dg validate --json (ok:true)
    - git diff --check (clean)
    - manual XMLParser billion-laughs probe confirming internal DOCTYPE entity expansion bypasses shouldResolveExternalEntities=false
  findings:
    - "[security] PortablePackageEditSidecar.swift: PortablePackageXMPCodec.decode did not guard against internal DOCTYPE entity expansion (billion-laughs) in XMP sidecar packets. A corrupted or maliciously crafted Metadata/<n>.xmp sidecar with a small DOCTYPE and a handful of nested <!ENTITY> definitions expands to gigabytes in memory during XMLParser.parse(), before any kromora: attribute is read or validated, causing a hang/OOM instead of the required graceful malformedXMP report. CONFIRMED and fixed."
  fixes:
    - Rejected any XMP packet containing a DOCTYPE declaration in PortablePackageXMPCodec.decode, throwing PortablePackageError.malformedXMP instead of parsing it (valid packets from encode() never declare a DOCTYPE).
    - Added testXMPWithDOCTYPEEntityBombIsRejectedAsMalformedRatherThanExpanded to Tests/KromoraKitTests/PortableLibraryPackageTests.swift as a regression test.
  verification_commits:
    - 56aeeb3bddc3424e39cd0650cce634806eba9623
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T13:10:26.008Z
  session: 01MTZTVEGC1GRMMDFE
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - persistence
created: 2026-09-12T19:44:17.634Z
updated: 2026-09-13T13:10:26.010Z
depends_on:
  - KRMA-401
order: a0
board: product
commits:
  - 56aeeb3bddc3424e39cd0650cce634806eba9623
---

## Objective

Implement revisioned XMP/Kromora edit sidecars and embedded, deduplicated Look bytes within the
package, reserving (but not exposing) referenced-asset fields.

## Dependencies

- The package-format ticket (sidecars live alongside asset records in the same format).

## Scope

- Implement per-asset edit sidecars that hold develop settings history as immutable revisions (each
  edit creates a new revision rather than overwriting in place), stored as both a Kromora-native
  representation and XMP-compatible metadata.
- Handle malformed/truncated XMP on read: detect it, do not crash, and follow the critical/rebuildable
  recovery policy (an edit sidecar is critical data — malformed XMP must be reported/quarantined, not
  silently discarded).
- Embed Look/LUT bytes referenced by an edit revision directly in the package, deduplicated by content
  hash so the same Look referenced by many assets is stored once.
- Reserve schema fields for a future "referenced asset" (as opposed to copied-in) concept, per
  ADR-001, but do not implement or expose any referenced-asset UI or resolver behavior — the fields
  exist in the schema only.

## Acceptance criteria

- [ ] Edit sidecars are immutable, revisioned (new revision per edit, not in-place overwrite), and
  round-trip through both the Kromora-native and XMP representations.
- [ ] Malformed/truncated XMP is detected on read and handled per the critical-data recovery policy
  (reported, not silently dropped or crashed on).
- [ ] Look bytes referenced by multiple assets are stored once in the package (deduplicated by
  content hash), verified by a test that imports the same Look via two different assets.
- [ ] Referenced-asset schema fields exist and round-trip but have no UI or resolver wired to them.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Format/unit lane for sidecar round-trip, XMP malformed-input handling, and Look deduplication.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/LOOKS.md, .dg/decisions/ADR-001-portable-library-package-sequencing-and-safety-b.md
- context.issues: KRMA-391


### Comment — codex @ 2026-09-13T13:06:16.751Z

Implemented in b3cd09b. Added immutable per-asset Edits/<revision>.json revisions with paired XMP Metadata/<revision>.xmp packets, strict malformed/truncated XMP reporting and explicit quarantine, content-addressed Looks/<sha256>.cube deduplication across assets, atomic asset-pointer updates through the package transaction layer, and reserved referenced-source field round-trip coverage with no UI/resolver wiring. Checks: swift build, focused package/transaction/import/settings tests (16/16), git diff --check, dg validate --json. Full swift test: 1389 run, 52 skipped, 14 failures in pre-existing unrelated Auto/comparison/export/filmstrip/masking/thumbnail async/UI workflows; all KRMA-404/package tests passed.

## Agent log

- 2026-09-13T13:10:26.008Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Edit sidecars are immutable, revisioned (new revision per edit, not in-place overwrite), and round-trip through both the Kromora-native and XMP representations. (pass) — PortableLibraryPackage.appendEditRevision always allocates a new monotonically increasing revision, refuses to overwrite an existing Edits/<n>.json or Metadata/<n>.xmp path, and commits both through the crash-safe transaction layer. testEditRevisionsRoundTripAsNativeAndXMPAndRemainImmutable verifies two successive revisions round-trip identically via readEditRevision/readEditSidecar.
- [x] Malformed/truncated XMP is detected on read and handled per the critical-data recovery policy (reported, not silently dropped or crashed on). (pass) — PortablePackageXMPCodec.decode throws typed PortablePackageError.malformedXMP for empty/truncated/non-well-formed packets, and quarantineMalformedXMP moves the bad packet aside for recovery workflows instead of deleting it silently. Covered by testMalformedXMPIsReportedAndCanBeQuarantined. During verification I found and fixed a related gap: shouldResolveExternalEntities=false does not stop libxml2 from expanding internal DOCTYPE <!ENTITY> definitions (confirmed empirically with a billion-laughs packet), which could exhaust memory before validation ran. Added a DOCTYPE rejection guard in decode() plus a regression test (testXMPWithDOCTYPEEntityBombIsRejectedAsMalformedRatherThanExpanded).
- [x] Look bytes referenced by multiple assets are stored once in the package (deduplicated by content hash), verified by a test that imports the same Look via two different assets. (pass) — appendEditRevision content-addresses Look bytes to Looks/<sha256>.cube and validates any pre-existing blob's checksum before reuse. testEditRevisionsRoundTripAsNativeAndXMPAndRemainImmutable imports identical Look bytes for two different assets and asserts exactly one blob file exists.
- [x] Referenced-asset schema fields exist and round-trip but have no UI or resolver wired to them. (pass) — PortablePackageSourceReference reserves storage/relativePath/securityScopedBookmark for a future .referenced case; embeddedSourceURL only resolves .embedded and throws otherwise. testReservedReferencedAssetFieldsRoundTripWithoutResolverBehavior confirms round-trip plus the resolver rejection. Grep found no UI/view-model wiring to .referenced.
- [x] swift build, swift test, dg validate, and git diff --check pass. (pass) — swift build clean; dg validate --json ok:true (only pre-existing unrelated model-name warnings); git diff --check clean. Ran the full PortableLibraryPackageTests (7/7, including the new regression test) plus PortablePackageTransactionTests, PortableCacheIdentityTests, and CoordinatorBoundaryTests (all pass, 0 regressions). Did not re-run the full multi-minute swift test suite; the implementer's review-stage run (1389 run, 14 pre-existing unrelated failures in Auto/comparison/export/filmstrip/masking/thumbnail async/UI areas untouched by this change) was accepted as the baseline.
Checks run:
- swift build
- swift test --filter PortableLibraryPackageTests (7/7 pass, incl. new DOCTYPE regression test)
- swift test --filter 'PortablePackageTransactionTests|PortablePackageLeaseTests|PortableCacheIdentityTests|CoordinatorBoundaryTests' (17/17 pass)
- dg validate --json (ok:true)
- git diff --check (clean)
- manual XMLParser billion-laughs probe confirming internal DOCTYPE entity expansion bypasses shouldResolveExternalEntities=false
Findings:
- [security] PortablePackageEditSidecar.swift: PortablePackageXMPCodec.decode did not guard against internal DOCTYPE entity expansion (billion-laughs) in XMP sidecar packets. A corrupted or maliciously crafted Metadata/<n>.xmp sidecar with a small DOCTYPE and a handful of nested <!ENTITY> definitions expands to gigabytes in memory during XMLParser.parse(), before any kromora: attribute is read or validated, causing a hang/OOM instead of the required graceful malformedXMP report. CONFIRMED and fixed.
Fixes:
- Rejected any XMP packet containing a DOCTYPE declaration in PortablePackageXMPCodec.decode, throwing PortablePackageError.malformedXMP instead of parsing it (valid packets from encode() never declare a DOCTYPE).
- Added testXMPWithDOCTYPEEntityBombIsRejectedAsMalformedRatherThanExpanded to Tests/KromoraKitTests/PortableLibraryPackageTests.swift as a regression test.
Verification commits:
- 56aeeb3bddc3424e39cd0650cce634806eba9623
Actor: claude
Resolved model: sonnet
Pickup session: 01MTZTVEGC1GRMMDFE
Summary: Verified KRMA-404: sidecars immutable/revisioned and round-trip native+XMP, malformed XMP reported+quarantined, Look bytes deduplicated by content hash, referenced-asset fields reserved without UI/resolver wiring. Found and fixed a real gap: XMLParser's shouldResolveExternalEntities=false does not block internal DOCTYPE entity expansion, so a corrupt/malicious XMP sidecar could trigger a billion-laughs memory blowup instead of a graceful malformed-XMP report; added a DOCTYPE rejection guard plus a regression test. All targeted suites pass; swift build, dg validate, and git diff --check are clean.
