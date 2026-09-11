#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

# Keep these expressions at the test-suite level where possible. A few suites contain both
# deterministic model assertions and real-RAW methods, so the latter are listed by method below.
# The verify mode treats optional methods as optional before assigning an overlapping method to the
# serialized render/UI lane.
serial_filter='(AnalysisDebugPanelTests|BundledLookTests|ColorGradingTests|ColorMixerTests|ColorPipelineTests|CollectionProjectionPerformanceTests|CropPipelineTests|EffectsPipelineTests|HistogramTests|ImageLoadingTests|InfoSemanticMaskRenderingTests|KeyMonitorTests|LocalMaskRenderingTests|LookInspectorViewTests|LookLUTExportTests|LookPreviewTests|KromoraWindowAppearanceControllerTests|MenuCommandTests|PersonSignalWarmingTests|PhotoIntelligenceCorpusTests|PhotosDeliveryTests|PhotosImportTests|PreviewCutoverTests|PreviewSurfaceTests|RenderCacheTests|RenderEngineInteractivePrecisionTests|RenderEngineTests|RenderPipelineTests|RenderStackTests|ThumbnailTests|VisionSemanticMaskProviderTests|WorkingSpaceTests)'

# These tests need a licensed external RAW/JPG, a logged-in display, or deliberately opt-in
# benchmark settings. They are not part of the required CI gate. Keep the method-level entries
# narrow so the pure RAW value/model tests remain in the deterministic lane.
optional_filter='(ConcurrentExportEditingBenchmark|DeriveInvarianceTests|LibraryScanPerformanceTests|MaskOverlayPerformanceBenchmark|MaskResamplingPerformanceTests|MetalPresentationBenchmark|PhotoAnalysisPerformanceTests|PhotosImportPerformanceTests|PreviewCostBenchmark|TracingOverheadBenchmark|AutoPerformanceDiagnosticsTests/testAutoEndToEndBenchmark|LocalMaskRenderingTests/testSemanticPreviewMaskWorkingResolutionBenchmark|PreviewCoordinatorTests/testLargePreviewInteractiveLatencyBenchmark|RAWCapabilitiesTests/(testProbingARealRAWReportsItsDecodersFlags|testProbingARealRAWReportsItsDecodersSeeds|testEveryPerImageSeedLandsStrictlyInsideItsSliderRange|testWritingTheAsShotValuesMatchesLeavingThemUnset|testAValueWrittenToAnUnsupportedAdjustmentChangesNothing|testRaisingNeutralTemperatureWarmsTheImage)|RAWDevelopSettingsTests/(testApplyPushesEverySupportedKnobOntoARealFilter|testApplyingNeutralChangesNothingOnARealFilter)|ImageLoadingTests/testLoadingARAWGoesThroughCIRAWFilter|ImageSourceTests/testRAWBytesAreDetectedWithoutAFilename|DevelopInspectorTests/(testARAWStaysOnProbingUntilTheProbeAnswers|testAsShotRestoresTheActualRAWDecoderSeed)|RenderCacheTests/testAboveBudgetRAWSessionDoesNotMaterializeOnEveryEdit|RenderPipelineTests/(testRAWDevelopAndScaleReachTheDecoder|testNeutralRAWMatchesTheExistingNeutralBaseline)|RenderEngineTests/(testCompletedRAWPreviewReflectsDevelopSettings|testInteractiveSessionDoesNotLeakSettingsAcrossTicks|testInteractiveRAWDownstreamEditsReuseTheCompletedOutput)|PreviewCutoverTests/testRAWDevelopReachesThePreview)'

usage() {
    print -u2 "Usage: $0 {verify|fast|serial|optional}"
    print -u2 "  verify    audit that every discovered test belongs to exactly one lane"
    print -u2 "  fast      run required deterministic/model/fake-engine tests in parallel"
    print -u2 "  serial    run required Core Image/render/AppKit/UI tests serially"
    print -u2 "  optional  run RAW-fixture and benchmark tests (set their documented env vars)"
}

audit_lanes() {
    local counts
    counts="$(swift test list | awk -v serial="$serial_filter" -v optional="$optional_filter" '
        /^KromoraKitTests\..+\// {
            total++
            if ($0 ~ optional) {
                optional_count++
            } else if ($0 ~ serial) {
                serial_count++
            } else {
                fast_count++
            }
        }
        END {
            printf "%d %d %d %d\n", total, fast_count, serial_count, optional_count
        }
    ' )"

    local total fast serial optional
    read -r total fast serial optional <<< "$counts"
    if (( total == 0 || fast + serial + optional != total )); then
        print -u2 "CI lane audit failed: test list was empty or did not partition cleanly"
        print -u2 "total=$total fast=$fast serial=$serial optional=$optional"
        return 1
    fi

    print "CI lane coverage: total=$total required_fast=$fast required_serial=$serial optional=$optional"
    print "Required lanes are disjoint; optional tests are intentionally excluded from the required gate."
}

run_lane() {
    local lane="$1"
    local command_display="$2"
    shift
    shift
    print "CI_TEST_LANE=$lane"
    print "Focused rerun: $command_display"
    "$@" || {
        local lane_status=$?
        print -u2 "FAILED CI_TEST_LANE=$lane"
        print -u2 "Focused rerun: $command_display"
        return "$lane_status"
    }
}

case "${1:-}" in
    verify)
        audit_lanes
        ;;
    fast)
        audit_lanes
        skip_filter="($serial_filter|$optional_filter)"
        run_lane "deterministic-parallel" \
            "swift test --parallel --skip '$skip_filter'" \
            env KROMORA_TEST_ISOLATION=1 swift test --parallel --skip "$skip_filter"
        ;;
    serial)
        audit_lanes
        run_lane "render-ui-serial" \
            "swift test --no-parallel --filter '$serial_filter' --skip '$optional_filter'" \
            env KROMORA_TEST_ISOLATION=1 \
            swift test --no-parallel --filter "$serial_filter" --skip "$optional_filter"
        ;;
    optional)
        audit_lanes
        print "Requirements: KROMORA_RAW_FIXTURE_DIR for RAW/JPG coverage; benchmark-specific KROMORA_* settings; a logged-in display for Metal/AppKit capture."
        run_lane "optional-raw-benchmarks" \
            "swift test --no-parallel --filter '$optional_filter'" \
            env KROMORA_TEST_ISOLATION=1 swift test --no-parallel --filter "$optional_filter"
        ;;
    *)
        usage
        exit 2
        ;;
esac
