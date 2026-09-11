#!/bin/zsh
set -euo pipefail

# KRMA-351 — generate the Auto quality corpus evaluation artifacts.
#
# Usage:
#   scripts/auto-quality-report.sh [output-dir]
#
# Runs the deterministic policy/preservation/lifecycle corpus plus the actual-render lane
# (AutoQualityRegressionTests, real RenderEngine at 96x64), then re-runs the render lane with
# KROMORA_AUTO_QUALITY_ARTIFACT_DIR set so every evaluated fixture writes unchanged.png,
# proposed.png, diff.png, report.json, and report.md under
# <output-dir>/auto-quality-<id>/. The artifact directory is gitignored (see .gitignore:
# artifacts/); nothing here commits generated pixels.
#
# report.json carries fixture identity, edit hashes, changed controls, diff measurements, and
# render failures — enough for an agent to diagnose a regression without opening an image.

project_root="${0:A:h}/.."
cd "$project_root"

output_dir="${1:-artifacts/auto-quality}"

swift test --filter AutoQualityRegressionTests
KROMORA_AUTO_QUALITY_ARTIFACT_DIR="$output_dir" swift test --filter 'AutoQualityRegressionTests/testActualRender'

print "Artifact: $output_dir/auto-quality-<id>/ (unchanged.png, proposed.png, diff.png, report.json, report.md)"
