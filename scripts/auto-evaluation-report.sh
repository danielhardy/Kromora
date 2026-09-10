#!/bin/zsh
set -euo pipefail

# KRMA-342 — generate a renderer-backed Auto candidate evaluation artifact.
#
# Usage:
#   scripts/auto-evaluation-report.sh [output-dir]
#
# Renders a representative fixture (gradient PNG, unchanged vs. +1 EV proposal) through the real
# `RenderEngine` seam and writes unchanged.png, proposed.png, diff.png, report.json, and
# report.md under <output-dir>/real-gradient/ (default: artifacts/auto-evaluation/). The
# artifact directory is gitignored; nothing here commits generated pixels.
#
# The focused evaluation/report tests also run first so a missing render can never be mistaken
# for a successful candidate without the suite noticing.

project_root="${0:A:h}/.."
cd "$project_root"

output_dir="${1:-artifacts/auto-evaluation}"

swift test --filter AutoCandidateEvaluationTests
KROMORA_AUTO_EVAL_ARTIFACT_DIR="$output_dir" swift test --filter 'AutoCandidateEvaluationTests/testRealEngineDiffAndParityOnGradientFixture'

print "Artifact: $output_dir/real-gradient/ (unchanged.png, proposed.png, diff.png, report.json, report.md)"
