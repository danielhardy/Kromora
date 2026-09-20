#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
report_path=${KROMORA_PHOTO_INTELLIGENCE_REPORT_PATH:-artifacts/photo-intelligence/report.html}

cd "$repo_dir"
KROMORA_PHOTO_INTELLIGENCE_REPORT_PATH="$report_path" \
  swift test --filter PhotoIntelligenceRealCorpusTests.testGenerateVisualRegressionReport

case "$report_path" in
  /*) absolute_path=$report_path ;;
  *) absolute_path=$repo_dir/$report_path ;;
esac
printf 'Photo-intelligence report written to %s\n' "$absolute_path"
