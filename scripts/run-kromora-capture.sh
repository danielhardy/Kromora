#!/bin/zsh
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/run-kromora-capture.sh --benchmark <name> [options] [source]

Run one of the supported Release xctrace captures. The source defaults to
KROMORA_RAW_FIXTURE_DIR/DSC07826.ARW (or realworldtest/DSC07826.ARW).

Benchmarks:
  metal-presentation          Real CAMetalLayer presentation latency
  concurrent-export-editing  Batch export while editing with real drawables

Options:
  --benchmark NAME   Required benchmark configuration
  --source PATH      RAW fixture path; may also be supplied as the final argument
  --capture-id ID    Capture ID written to the summary and output filenames
  --output-dir PATH  Directory for the trace and summary
  --time-limit DURATION       xctrace time limit (for example, 60s)
  --iterations COUNT          Metal presentation iterations
  --items COUNT               Concurrent export item count
  --gestures COUNT            Concurrent editing gesture count
  -h, --help         Show this help

The command requires a macOS display, xctrace, xctest, and a licensed RAW
fixture. It is intentionally opt-in and is not a CI gate.
USAGE
}

benchmark=""
source_path=""
capture_id=""
output_dir=""
time_limit=""
iteration_count="${KROMORA_METAL_BENCHMARK_ITERATIONS:-20}"
item_count="${KROMORA_CONCURRENT_CAPTURE_ITEMS:-6}"
gesture_count="${KROMORA_CONCURRENT_CAPTURE_GESTURES:-10}"

while (( $# > 0 )); do
    case "$1" in
        --benchmark)
            (( $# >= 2 )) || { print -u2 -- "--benchmark requires a value"; exit 2; }
            benchmark="$2"
            shift 2
            ;;
        --source)
            (( $# >= 2 )) || { print -u2 -- "--source requires a path"; exit 2; }
            source_path="$2"
            shift 2
            ;;
        --capture-id)
            (( $# >= 2 )) || { print -u2 -- "--capture-id requires a value"; exit 2; }
            capture_id="$2"
            shift 2
            ;;
        --output-dir)
            (( $# >= 2 )) || { print -u2 -- "--output-dir requires a path"; exit 2; }
            output_dir="$2"
            shift 2
            ;;
        --time-limit)
            (( $# >= 2 )) || { print -u2 -- "--time-limit requires a duration"; exit 2; }
            time_limit="$2"
            shift 2
            ;;
        --iterations)
            (( $# >= 2 )) || { print -u2 -- "--iterations requires a count"; exit 2; }
            iteration_count="$2"
            shift 2
            ;;
        --items)
            (( $# >= 2 )) || { print -u2 -- "--items requires a count"; exit 2; }
            item_count="$2"
            shift 2
            ;;
        --gestures)
            (( $# >= 2 )) || { print -u2 -- "--gestures requires a count"; exit 2; }
            gesture_count="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            print -u2 "unknown option: $1"
            usage >&2
            exit 2
            ;;
        *)
            if [[ -n "$source_path" ]]; then
                print -u2 "source path supplied more than once"
                exit 2
            fi
            source_path="$1"
            shift
            ;;
    esac
done

case "$benchmark" in
    metal-presentation)
        test_filter="MetalPresentationBenchmark/testRealMetalPresentationBenchmark"
        default_capture_id="KROMORA-metal-presentation"
        default_time_limit="60s"
        default_output_dir="/tmp/kromora-capture"
        ;;
    concurrent-export-editing)
        test_filter="ConcurrentExportEditingBenchmark/testRealConcurrentBatchExportAndEditing"
        default_capture_id="KROMORA-concurrent-export-editing"
        default_time_limit="600s"
        default_output_dir="/tmp/kromora-capture"
        ;;
    "")
        print -u2 -- "--benchmark is required"
        usage >&2
        exit 2
        ;;
    *)
        print -u2 "unsupported benchmark: $benchmark"
        usage >&2
        exit 2
        ;;
esac

repo_root="${0:A:h}/.."
fixture_root="${KROMORA_RAW_FIXTURE_DIR:-$repo_root/realworldtest}"
source_path="${source_path:-$fixture_root/DSC07826.ARW}"
capture_id="${capture_id:-${KROMORA_CAPTURE_ID:-$default_capture_id}}"
output_dir="${output_dir:-${KROMORA_CAPTURE_OUTPUT_DIR:-$default_output_dir}}"
time_limit="${time_limit:-${KROMORA_CAPTURE_TIME_LIMIT:-$default_time_limit}}"
swift_path="$(command -v swift || true)"
xctrace_path="$(command -v xctrace || true)"
xctest_path="$(xcrun --find xctest 2>/dev/null || true)"

if [[ "$source_path" != /* ]]; then
    source_path="$PWD/$source_path"
fi
cd "$repo_root"

if [[ ! -f "$source_path" ]]; then
    print -u2 "RAW source does not exist: $source_path"
    exit 2
fi
if [[ -z "$swift_path" || ! -x "$swift_path" ]]; then
    print -u2 "Swift executable could not be resolved"
    exit 2
fi
if [[ -z "$xctrace_path" || ! -x "$xctrace_path" ]]; then
    print -u2 "xctrace executable could not be resolved"
    exit 2
fi
if [[ -z "$xctest_path" || ! -x "$xctest_path" ]]; then
    print -u2 "xctest executable could not be resolved"
    exit 2
fi

mkdir -p "$output_dir"
source_stem="${source_path:t:r}"
stamp="$(date +%Y%m%d-%H%M%S)"
trace_path="$output_dir/${capture_id}-${source_stem}-${stamp}.trace"
summary_path="$output_dir/${capture_id}-${source_stem}-${stamp}-summary.txt"

case "$benchmark" in
    metal-presentation)
        benchmark_env=(
            --env KROMORA_METAL_BENCHMARK=1
            --env "KROMORA_METAL_BENCHMARK_RAW=$source_path"
            --env "KROMORA_METAL_BENCHMARK_ITERATIONS=$iteration_count"
        )
        ;;
    concurrent-export-editing)
        benchmark_env=(
            --env KROMORA_CONCURRENT_CAPTURE=1
            --env "KROMORA_CONCURRENT_CAPTURE_RAW=$source_path"
            --env "KROMORA_CONCURRENT_CAPTURE_ITEMS=$item_count"
            --env "KROMORA_CONCURRENT_CAPTURE_GESTURES=$gesture_count"
        )
        secondary="$fixture_root/DSC07241.ARW"
        secondary_env=()
        if [[ -f "$secondary" ]]; then
            secondary_env=(--env "KROMORA_CONCURRENT_CAPTURE_RAW_SECONDARY=$secondary")
        fi
        ;;
esac

{
    print "benchmark=$benchmark"
    print "capture=$capture_id"
    print "source=$source_path"
    print "configuration=Release"
    print "commit=$(git -C "$repo_root" rev-parse HEAD)"
    print "os=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    print "hardware=$(system_profiler SPHardwareDataType -detailLevel mini | tr '\n' ';')"
    print "raw_decoder=CIRAWFilter via ImageDecoder.load"
    print "raw_decoder_version=system Core Image; identify with the OS build above"
    if [[ "$benchmark" == "metal-presentation" ]]; then
        print "iterations=$iteration_count"
        print "supporting_work=not enabled by this representative capture"
        print "cache_state=single automated Release run; cold/warm comparison is optional follow-up"
    else
        print "batch_items=$item_count"
        print "editing_gestures=$gesture_count"
        print "supporting_work=histogram enabled per confirmed settled frame; comparison and prefetch disabled"
        print "cache_state=warm (settled preview develop completed before the measured phase)"
    fi
    print "trace=$trace_path"
    print ""
} > "$summary_path"

# Build the test bundle before tracing. Tracing `swift test` directly also traces compilation,
# producing a large system trace unrelated to the benchmark.
print "Preparing Release XCTest bundle..." >> "$summary_path"
"$swift_path" test -c release --filter "$test_filter" >> "$summary_path" 2>&1
bin_path="$($swift_path build -c release --show-bin-path)"
test_bundle="$bin_path/KromoraPackageTests.xctest"
if [[ ! -d "$test_bundle" ]]; then
    print -u2 "Release test bundle does not exist: $test_bundle"
    exit 2
fi
print "test_bundle=$test_bundle" >> "$summary_path"

xctrace_args=(
    record
    --template "Metal System Trace"
    --instrument "Points of Interest"
    --output "$trace_path"
    --time-limit "$time_limit"
    "${benchmark_env[@]}"
    --target-stdout -
    --launch --
    "$xctest_path" -XCTest "$test_filter" "$test_bundle"
)
if [[ "$benchmark" == "concurrent-export-editing" && ${#secondary_env[@]} -gt 0 ]]; then
    xctrace_args=(
        record
        --template "Metal System Trace"
        --instrument "Points of Interest"
        --output "$trace_path"
        --time-limit "$time_limit"
        "${benchmark_env[@]}"
        "${secondary_env[@]}"
        --target-stdout -
        --launch --
        "$xctest_path" -XCTest "$test_filter" "$test_bundle"
    )
fi
"$xctrace_path" "${xctrace_args[@]}" >> "$summary_path" 2>&1

print "trace=$trace_path"
print "summary=$summary_path"
