---
id: KRMA-534
title: Centralize package path safety and shared serialization helpers
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-23T01:17:08.146Z
  session: 01MUDE8LJES6LEUCT4
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - security
  - package
created: 2026-09-21T20:33:13.935Z
updated: 2026-09-23T01:17:08.148Z
estimate: 5
order: zx
board: product
---

## Objective

Make package path validation symlink-safe and eliminate duplicated filename, clamp, and JSON-coder helpers without changing package compatibility.

## Context and evidence

PortableLibraryPackage.isSafeRelativePath rejects absolute paths, traversal, empty components, and backslashes, but accepts . components and does not resolve symlinks. A package could contain an Assets/.../Original symlink escaping the package root. The sandbox limits impact but validation should reject it and report a critical failure. The same concerns are implemented repeatedly through safeFilename, about 21 clamp variants, and repeated JSONEncoder configuration.

## Scope

- Add a PackagePath value type that validates components, resolves against the package root, and confirms the resolved path stays under the root without symlink escape.
- Use it consistently in package, sidecar, validation, restore, and backup code.
- Report symlink escapes as criticalFailures in PortableLibraryValidation.
- Consolidate filename sanitization and package JSON coding configuration.
- Consolidate clamp behavior into one Comparable.clamped(to:default:) helper that handles non-finite values as required by current callers.
- Preserve on-disk package naming and JSON compatibility.

## Acceptance criteria

- [ ] Tests cover a symlinked original, ./ component, absolute path, traversal attempt, and valid nested path.
- [ ] Validation classifies path/symlink violations as critical and restore/backup/import fail closed.
- [ ] There is one shared helper per filename, clamp, and package JSON-coder concern; callers retain their existing semantics.
- [ ] Package compatibility fixtures and persistence tests pass.
- [ ] Security-sensitive path operations are reviewed for TOCTOU and root containment assumptions.

## Dependencies and coordination

Independent, but coordinate with CQ-05/CQ-16 if those remove callers. Keep this ticket focused on shared safety/helper behavior and avoid unrelated formatting churn.

## Likely files and checks

PortableLibraryPackage.swift, PortablePackageValidation/Restore/Backup/Import/Transaction files, PortableLibrarySession.swift, LocalMaskModels and other clamp callers, JSON coder definitions, and security/package tests.

## Agent log

- 2026-09-23T01:17:08.146Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUDE8LJES6LEUCT4
Summary: Implemented root-aware PackagePath validation with symlink containment checks across package reads/writes, transactions, validation, import, backup, restore, sidecars, trash, and browsing locators. Added critical validation coverage for symlink escapes and lexical path cases, centralized package JSON coding, centralized finite-aware clamping while preserving local quantization, and centralized filename sanitization.
