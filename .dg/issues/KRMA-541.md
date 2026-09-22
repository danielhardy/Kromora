---
id: KRMA-541
title: Fix PortablePackageEndToEndRegressionTests data-preservation failure
type: task
status: ready
priority: high
agent: codex
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - fast-lane
  - regression
  - package
created: 2026-09-22T17:35:56.844Z
updated: 2026-09-22T17:36:27.480Z
estimate: 3
order: zv
board: product
---

## Objective

Restore package end-to-end preservation of current deletion data and unrelated user data.

## Evidence

The fast lane failed PortablePackageEndToEndRegressionTests.testPackageWorkflowLeavesCurrentDeletionDataAndUnrelatedUserDataUntouched. The expected file resource was missing after the workflow and the preservation assertion was false.

## Acceptance criteria

- [ ] The focused PortablePackageEndToEndRegressionTests suite passes.
- [ ] Current deletion data survives the package workflow.
- [ ] Unrelated user data remains present and unchanged.
- [ ] The fast lane no longer reports this suite.
