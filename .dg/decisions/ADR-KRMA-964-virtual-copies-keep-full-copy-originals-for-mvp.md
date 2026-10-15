---
id: ADR-KRMA-964
title: Virtual copies keep full-copy originals for MVP
date: 2026-10-15T06:19:29.065Z
status: accepted
---

Decision (KRMA-964): virtual copies keep duplicating the full original for MVP. Each copy has its own package asset, independent edits and history; it re-imports and hashes the embedded original, so a 100 MB RAW adds ~100 MB per copy. Rationale: per-asset ownership keeps delete, trash, reclaim, quarantine, backup/restore and integrity validation simple. Sharing would need a package-format change (assets referencing another asset's original), migration of existing copies, last-dependent-wins retention on delete/trash/quarantine, and backup/restore/validation of shared references. No shared-original design is planned; revisit on concrete user demand.
