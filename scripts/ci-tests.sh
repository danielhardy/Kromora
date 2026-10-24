#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

# Keep these expressions at the test-suite level where possible. A few suites contain both
# deterministic model assertions and real-RAW methods, so the latter are listed by method below.
# The verify mode treats optional methods as optional before assigning an overlapping method to the
# serialized render/UI lane.
# This one ThumbnailSwitchLifecycle test compares real GPU rasters. Keep its pixel parity check
# out of the parallel model/fake-engine lane, where concurrent Core Image work makes byte-level
# results nondeterministic; the other lifecycle tests remain parallel.
# Real Core Image and real-engine classes belong here: any class that builds a CIContext, runs
# RetouchRenderer, or drives the production RenderEngine (not FakeRenderEngine) shares GPU and Core
# Image state, so it must not run in the parallel fast lane. Mixed classes are listed by method.
# Real AppKit window/responder tests also run here so parallel tests cannot steal WindowServer focus.
serial_filter='(AnalysisDebugPanelTests|AutoCandidateEvaluationTests|AutoEnhancementCoordinatorTests/testRealEngineCoordinatorRunOnGradientFixture|AutoPerformanceDiagnosticsTests|AutoQualityRegressionTests|CanonicalPreviewRasterEdgeCoverageTests|ContentAwareAutoEngineTests|CropROITests|CropKeyboardWindowTests|EditedThumbnailCoordinatorTests|ExportCutoverTests|ExportOptionsTests|ImageRotationTests|PortableCacheIdentityTests/testRenderCacheHitsAfterRelocationWithTheSamePortableIdentity|PreviewTextureEdgeCoverageTests|RenderEngineProcessingPrefixAcceptanceTests|RenderRequestTests|RetouchCameraScaleDiagnosticsTests|RetouchQualityEvaluationTests|RAWCapabilitiesTests/testProbingAStandardImageReturnsNil|CubeLUTTests/(testDomainIsNormalizedToUnitRange|testIndexOrderingIsRedFastest|testWriteThenParseRoundTrips|testIntensityBlendsBetweenOriginalAndGraded|testIntensityIsClampedToUnitRange|testIntensityPathStillEqualsGradeThenDissolve|testPassingACachedFilterMatchesBuildingOneInline)|ExportCoordinatorTests/testBatchExportHonorsTheDocumentsIntensity|LatestPreviewFrameStoreTests/testRoundTripUsesARealCanonicalRasterAcrossInstances|LUTFilterCacheTests/testOutputImageSnapshotsItsInputsRatherThanReadingThemLater|RawOrientationTests/testOrientationThreeFlipsPixelsEndForEnd|ExportStreamingTests|ObservationAuxiliaryStateTests|ObservationBodyBaselineTests|FocusedSceneValueTests|BundledLookTests|ColorGradingTests|ColorMixerTests|ColorPipelineTests|CollectionProjectionPerformanceTests|CropPipelineTests|EditorCanvasViewportTests|EffectsPipelineTests|FilmstripThumbnailTests|HistogramTests|IdentityRegressionGateTests|ImageLoadingTests|InfoSemanticMaskRenderingTests|InspectorScrollCrashPathTests|KeyboardCommandRouterTests|KeyboardShortcutCatalogTests|KeyboardSurfaceWindowTests|KeyRoutingProbeTests|LibraryCellClickTests|LocalMaskRenderingTests|LookInspectorViewTests|LookLUTExportTests|LookPreviewTests|KromoraWindowAppearanceControllerTests|MenuCommandTests|MetalKernelParityTests|NeutralOriginSliderTests|PersonSignalWarmingTests|PhotoIntelligenceRealCorpusTests|PhotosDeliveryTests|PhotosImportTests|PreviewCutoverTests|PreviewSurfaceTests|PresentationBudgetTests|RelaunchParityTests|RenderCacheTests|RenderEngineInteractivePrecisionTests|RenderEngineTests|RenderPipelineTests|RenderStackTests|ThumbnailTests|VisionSemanticMaskProviderTests|WorkingSpaceTests|ThumbnailSwitchLifecycleTests/testFilmstripAndGridPublishCropAwareSettledThumbnails)'
identity_filter='IdentityRegressionGateTests'

# These tests need a licensed external RAW/JPG, a logged-in display, or deliberately opt-in
# benchmark settings. They are not part of the required CI gate. Keep the method-level entries
# narrow so the pure RAW value/model tests remain in the deterministic lane.
optional_filter='(ShareCopyMemoryTests/testMeasurePeakFootprintForMultiPhotoCopy|WarmNavigationProfileBenchmark|PortablePackageImportPerformanceTests|ConcurrentExportEditingBenchmark|StoredEditAdoptionBenchmark|DeriveInvarianceTests|LibraryScanPerformanceTests|LibraryFolderBaselinePerformanceTests|LibraryScaleRegressionPerformanceTests|SyntheticLibraryGeneratorPerformanceTests|PackedThumbnailPerformanceTests|LargeImportLibraryGridBenchmark|HealSourceTimingBenchmark|MaskResamplingPerformanceTests|MetalPresentationBenchmark|PhotoAnalysisPerformanceTests|PhotosImportPerformanceTests|PreviewCostBenchmark|RenderKeyHashingBenchmark|TracingOverheadBenchmark|TextureAllocationBenchmark|AutoPerformanceDiagnosticsTests/testAutoEndToEndBenchmark|EmbeddedFirstFrameTests/testOptInRealEngineEmbeddedFirstFrameTiming|LastKnownFrameReleaseBenchmark|SingleViewLatencyBenchmark/testOptInRealEngineSingleViewLatencyBaseline|LocalMaskRenderingTests/testSemanticPreviewMaskWorkingResolutionBenchmark|PreviewCoordinatorTests/testLargePreviewInteractiveLatencyBenchmark|RAWCapabilitiesTests/(testProbingARealRAWReportsItsDecodersFlags|testProbingARealRAWReportsItsDecodersSeeds|testEveryPerImageSeedLandsStrictlyInsideItsSliderRange|testWritingTheAsShotValuesMatchesLeavingThemUnset|testAValueWrittenToAnUnsupportedAdjustmentChangesNothing|testRaisingNeutralTemperatureWarmsTheImage|testRawTintDirectionMatchesGreenToMagentaTrack)|RAWDevelopSettingsTests/(testApplyPushesEverySupportedKnobOntoARealFilter|testApplyingNeutralChangesNothingOnARealFilter)|RawOrientationTests/testLocalPortraitRAWDevelopMatchesThumbnailAxes|ImageLoadingTests/testLoadingARAWGoesThroughCIRAWFilter|ImageSourceTests/testRAWBytesAreDetectedWithoutAFilename|DevelopInspectorTests/(testARAWStaysOnProbingUntilTheProbeAnswers|testAsShotRestoresTheActualRAWDecoderSeed)|RenderCacheTests/testAboveBudgetRAWSessionDoesNotMaterializeOnEveryEdit|RenderPipelineTests/(testRAWDevelopAndScaleReachTheDecoder|testNeutralRAWMatchesTheExistingNeutralBaseline)|RenderEngineTests/(testCompletedRAWPreviewReflectsDevelopSettings|testInteractiveSessionDoesNotLeakSettingsAcrossTicks|testInteractiveRAWDownstreamEditsReuseTheCompletedOutput)|PreviewCutoverTests/testRAWDevelopReachesThePreview)'

usage() {
    print -u2 "Usage: $0 {verify|warning-gate|warning-gate-selftest|fast|serial|identity|optional}"
    print -u2 "  verify    audit that every discovered test belongs to exactly one lane"
    print -u2 "  warning-gate  build Sources and Tests; fail on any emitted Swift warning"
    print -u2 "  warning-gate-selftest  prove the gate rejects warnings, using stub builders"
    print -u2 "  fast      run required deterministic/model/fake-engine tests in parallel"
    print -u2 "  serial    run required Core Image/render/AppKit/UI tests serially"
    print -u2 "  identity  run the standing Phase 1 relocation/collision/stale-completion gate"
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

# Runs a build command, echoing all of its output unchanged, and fails when it exits nonzero or
# when it emitted a Swift source diagnostic (`path:line:col: warning:`). `-warnings-as-errors`
# promotes ordinary warnings, but the compiler still exits 0 for diagnostics it downgrades from
# errors (for example XCTest lifecycle actor-isolation in Swift 6 mode), so the output check is the
# backstop. It matches only compiler source locations, so linker, SDK, and packaging notes cannot
# trip it, and it never turns a failing build into a pass.
build_without_swift_warnings() {
    local log build_status=0 warning_count
    log="$(mktemp -t kromora-warning-gate)"
    "$@" 2>&1 | tee "$log" || build_status=$pipestatus[1]
    if (( build_status != 0 )); then
        rm -f "$log"
        return "$build_status"
    fi
    warning_count="$(sed $'s/\x1b\[[0-9;]*m//g' "$log" | grep -cE '^[^[:space:]].*:[0-9]+:[0-9]+: warning:' || true)"
    if (( warning_count > 0 )); then
        print -u2 "Swift warning gate failed: the build exited 0 but emitted $warning_count warning line(s)."
        sed $'s/\x1b\[[0-9;]*m//g' "$log" | grep -E '^[^[:space:]].*:[0-9]+:[0-9]+: warning:' >&2 || true
        rm -f "$log"
        return 1
    fi
    rm -f "$log"
}

warning_gate_selftest() {
    local dir stub name expected failures=0
    dir="$(mktemp -d -t kromora-warning-gate-selftest)"
    local -A bodies=(
        clean            'echo "Build complete!"'
        source-warning   'echo "Sources/KromoraKit/A.swift:3:9: warning: variable was never used"; echo "Build complete!"'
        test-warning     $'printf "Tests/KromoraKitTests/B.swift:4:43: \033[1;33mwarning: \033[1;39mmain actor-isolated property\033[0m\n"'
        compiler-failure 'echo "Sources/KromoraKit/A.swift:1:1: error: cannot find x in scope"; exit 1'
        linker-note      'echo "ld: warning: duplicate -rpath"; echo "Build complete!"'
    )
    local -A expectations=(clean 0 source-warning fail test-warning fail compiler-failure fail linker-note 0)
    for name in ${(k)bodies}; do
        stub="$dir/$name.sh"
        printf "#!/bin/zsh\n%s\n" "${bodies[$name]}" > "$stub"
        chmod +x "$stub"
        expected="${expectations[$name]}"
        if ( build_without_swift_warnings "$stub" ) > "$dir/$name.out" 2>&1; then
            [[ "$expected" == 0 ]] || { print -u2 "selftest FAILED: $name passed but must fail"; failures=$((failures + 1)); }
        else
            [[ "$expected" == fail ]] || { print -u2 "selftest FAILED: $name failed but must pass"; failures=$((failures + 1)); }
        fi
        # Full diagnostics must remain visible regardless of outcome.
        if [[ "$name" != clean && "$name" != linker-note ]] && ! grep -q "$name" "$dir/$name.out" 2>/dev/null; then
            grep -qE 'warning|error' "$dir/$name.out" || { print -u2 "selftest FAILED: $name diagnostics were hidden"; failures=$((failures + 1)); }
        fi
    done
    rm -rf "$dir"
    (( failures == 0 )) || return 1
    print "warning-gate selftest: clean passes; source/test warnings and compiler failures are rejected"
}

case "${1:-}" in
    verify)
        audit_lanes
        ;;
    warning-gate)
        run_lane "zero-warning-build" \
            "swift build --build-tests -Xswiftc -warnings-as-errors" \
            build_without_swift_warnings swift build --build-tests -Xswiftc -warnings-as-errors
        ;;
    warning-gate-selftest)
        warning_gate_selftest
        ;;
    fast)
        audit_lanes
        skip_filter="($serial_filter|$optional_filter)"
        run_lane "deterministic-parallel" \
            "swift test --parallel --skip '$skip_filter'" \
            swift test --parallel --skip "$skip_filter"
        ;;
    serial)
        audit_lanes
        run_lane "render-ui-serial" \
            "swift test --no-parallel --filter '$serial_filter' --skip '$optional_filter'" \
            swift test --no-parallel --filter "$serial_filter" --skip "$optional_filter"
        ;;
    identity)
        audit_lanes
        run_lane "identity-relocation-gate" \
            "swift test --no-parallel --filter '$identity_filter'" \
            swift test --no-parallel --filter "$identity_filter"
        ;;
    optional)
        audit_lanes
        print "Requirements: KROMORA_RAW_FIXTURE_DIR for RAW/JPG coverage; benchmark-specific KROMORA_* settings; a logged-in display for Metal/AppKit capture."
        run_lane "optional-raw-benchmarks" \
            "swift test --no-parallel --filter '$optional_filter'" \
            swift test --no-parallel --filter "$optional_filter"
        ;;
    *)
        usage
        exit 2
        ;;
esac
