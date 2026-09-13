---
id: ADR-001
title: Portable library package sequencing and safety boundaries
date: 2026-09-12T19:22:29.306Z
status: approved
---

## Status

Approved by human decision on 2026-09-12.

## Context

KRMA-384's `docs/LIBRARY_PACKAGE_PLAN.md` describes a future local-only portable library package,
while the shipped product still uses referenced folders and a SwiftData `EditStore.store`. The plan
must be sequenced without changing KRMA-371 deletion behavior or silently discarding existing data.

## Decision

1. Sequence the work as five independently verifiable phases:
   - KRMA-389: scale generator, current-product baseline, and thumbnail-packing spike.
   - KRMA-390: portable opaque UUID identity, after the baseline is committed.
   - KRMA-391: package format, transactions, leases, import, and recovery, with no index rewrite.
   - KRMA-392: paged library queries, index projection, and one unified work scheduler.
   - KRMA-393: verified backup/restore, validation, quarantine/trash, and maintenance.
2. Keep the package local-only. iCloud/CloudKit sync is a separate future decision and is not a
   prerequisite or hidden compatibility target for phases 0–4.
3. Treat the package as the eventual canonical source of edits and metadata, while keeping derived
   thumbnails, previews, masks, analysis, and the local index rebuildable.
4. Preserve unknown JSON keys, use opaque UUIDs for durable identity, embed resolved Look bytes in
   immutable edit revisions, and use a single serialized package commit writer.
5. Require explicit approval of the current-user-data disposition before Phase 1 can rewrite identity
   or Phase 2 can demote the current SwiftData store. No implementation may silently delete or migrate
   current library data.
6. Keep referenced-asset fields as a schema capability only; no referenced-asset UI is part of v1.

## Consequences

The phase boundaries keep the high-risk identity, persistence, indexing, and backup rewrites
reviewable and allow the existing folder-backed editor to remain stable while the baseline is built.
Imports become more expensive once Phase 2 lands because originals are copied and hashed, but the
cost is explicit, cancellable, and measurable. Phase 3 cannot claim scale success until it compares
against KRMA-389's committed baseline.

## Approval needed

A human must approve (a) the no-shipped-user-data assumption or provide the migration/disposition for
current `EditStore` data, and (b) the local-only package/compatibility policy before implementation
phases that change identity or persistence are started.

## Approval record

On 2026-09-13, human approval was granted for the no-shipped-user-data clean-slate disposition for
KRMA-399. Existing local `EditStore` records may be discarded, with the associated data-loss risk
acknowledged. Human approval also covers the local-only package/compatibility policy.
