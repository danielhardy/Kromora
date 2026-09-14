---
id: KRMA-429
title: Make the temperature slider non-linear for practical Kelvin adjustment
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ui
  - white-balance
created: 2026-09-14T02:17:51.506Z
updated: 2026-09-14T03:54:04.651Z
order: a0
board: product
---

## Objective
Make temperature adjustment easier to control across the useful photographic range without removing the existing high-end RAW capability.

## Problem
The temperature slider spans 2,000–50,000 K for RAW white balance, but the vast majority of useful work happens between roughly 2,000 and 10,000 K. With a linear mapping, that practical range occupies too little of the track, making precise everyday adjustments difficult while still requiring access to the full 50,000 K range.

## Proposed direction
Use a non-linear slider-space mapping for temperature so the 2,000–10,000 K region receives substantially more physical track length, while the upper range remains reachable and reversible. Keep the underlying persisted/rendered value in Kelvin; only the UI position-to-value mapping should change. Consider a monotonic piecewise or logarithmic mapping, with a smooth transition and a clearly defined neutral/as-shot point.

## Display precision
Color-setting readouts do not need decimal precision; display them rounded to the nearest whole number wherever decimals do not convey useful information. Preserve any underlying precision required for editing, persistence, rendering, or control semantics.

## Acceptance criteria
- [ ] The temperature slider gives materially finer control across 2,000–10,000 K.
- [ ] Values above 10,000 K remain reachable through the slider up to the existing 50,000 K RAW maximum.
- [ ] Mapping is monotonic, continuous, reversible, and does not introduce a jump around the practical-range boundary.
- [ ] Underlying Kelvin values, persistence, rendering, reset/as-shot behavior, direct entry, keyboard interaction, and accessibility value announcements remain correct.
- [ ] Apply the behavior consistently to every temperature slider that uses the 2,000–50,000 K RAW range; evaluate whether the standard-image 2,000–11,000 K control should share the mapping without changing its range.
- [ ] Color-setting readouts that currently show unnecessary decimals are rounded to the nearest whole number, while internal values and interactions retain required precision.
- [ ] Add focused mapping, formatting, and interaction regression coverage, including representative temperature values near 2,000 K, 6,500 K, 10,000 K, and 50,000 K.
