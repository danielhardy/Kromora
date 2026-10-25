#!/bin/zsh
# Run only the XCTest suites that cover what you changed. This is the inner-loop command; the
# full `scripts/ci-tests.sh fast|serial` lanes are the pre-handoff and CI gates, not an edit loop.
#
# How suites are chosen (no hand-kept table):
#   1. Changed test files contribute their own XCTestCase classes.
#   2. A changed Sources/KromoraKit/**/Foo.swift contributes test files named Foo*Tests.swift
#      (name match). If none match, it falls back to test files that mention a type declared in
#      Foo.swift, kept only when they are few. --wide always adds the mention matches.
#   Benchmark and performance suites are never selected; they are opt-in.
#
# `swift test --filter` runs serially, so real-engine and AppKit suites are safe to include.

set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

tests_dir="Tests/KromoraKitTests"
mention_cap=8
base_ref="HEAD"
wide=0
list_only=0
typeset -a explicit_suites

usage() {
    print -u2 "Usage: $0 [--base <ref>] [--wide] [--list] [SuiteName[/testMethod] ...]"
    print -u2 "  --base <ref>  diff against <ref> instead of HEAD (e.g. main)"
    print -u2 "  --wide        also include suites that merely mention a changed type"
    print -u2 "  --list        print the selected filter and exit without running"
    print -u2 "  Names given explicitly bypass change detection."
}

while (( $# )); do
    case "$1" in
        --base) base_ref="${2:?--base needs a ref}"; shift 2 ;;
        --wide) wide=1; shift ;;
        --list) list_only=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) usage; exit 2 ;;
        *) explicit_suites+=("$1"); shift ;;
    esac
done

# XCTestCase subclasses declared in a test file.
suites_in_file() {
    grep -hoE '^[[:space:]]*(@MainActor[[:space:]]+)?(final[[:space:]]+)?class[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[[:space:]]*XCTestCase' "$1" \
        | sed -E 's/.*class[[:space:]]+([A-Za-z0-9_]+).*/\1/' || true
}

is_selectable_test_file() {
    [[ "$1" == $tests_dir/*.swift && "$1" != *Benchmark* && "$1" != *Performance* ]]
}

typeset -aU selected
typeset -a notes

if (( ${#explicit_suites} )); then
    selected=("${explicit_suites[@]}")
else
    typeset -a changed
    changed=("${(@f)$( { git diff --name-only "$base_ref" -- Sources Tests; git ls-files -o --exclude-standard -- Sources Tests; } | sort -u )}")
    changed=(${changed:#})

    if (( ${#changed} == 0 )); then
        print "No changes under Sources/ or Tests/ relative to $base_ref; nothing to run."
        exit 0
    fi

    for file in "${changed[@]}"; do
        [[ -f "$file" ]] || continue
        if [[ "$file" == $tests_dir/*.swift ]]; then
            is_selectable_test_file "$file" && selected+=("${(@f)$(suites_in_file "$file")}")
            continue
        fi
        [[ "$file" == Sources/KromoraKit/*.swift ]] || continue

        stem="${file:t:r}"
        typeset -a name_matches
        name_matches=($tests_dir/${stem}*Tests.swift(N))
        name_matches=(${name_matches:#})
        for match in "${name_matches[@]}"; do
            is_selectable_test_file "$match" && selected+=("${(@f)$(suites_in_file "$match")}")
        done

        if (( wide || ${#name_matches} == 0 )); then
            typeset -a types mentions
            types=("${(@f)$(grep -hoE '^[[:space:]]*((public|internal|private|fileprivate|final)[[:space:]]+)*(struct|class|enum|actor|protocol)[[:space:]]+[A-Z][A-Za-z0-9_]+' "$file" \
                | sed -E 's/.*(struct|class|enum|actor|protocol)[[:space:]]+//' | sort -u || true)}")
            types=(${types:#})
            mentions=()
            for type_name in "${types[@]}" "$stem"; do
                mentions+=("${(@f)$(grep -rlw --include='*.swift' -- "$type_name" $tests_dir 2>/dev/null || true)}")
            done
            mentions=(${(u)mentions:#})
            typeset -a usable
            usable=()
            for match in "${mentions[@]}"; do
                is_selectable_test_file "$match" && [[ -n "$(suites_in_file "$match")" ]] && usable+=("$match")
            done
            if (( wide || ${#usable} <= mention_cap )); then
                for match in "${usable[@]}"; do selected+=("${(@f)$(suites_in_file "$match")}"); done
                (( ${#name_matches} == 0 )) && notes+=("$file: no ${stem}*Tests.swift; used ${#usable} suite file(s) that mention it")
            else
                notes+=("$file: no ${stem}*Tests.swift and ${#usable} files mention it (cap $mention_cap); name suites explicitly or use --wide")
            fi
        fi
    done
fi

selected=(${selected:#})

# Drop whole-suite entries that ci-tests.sh lists as optional (RAW fixtures, benchmarks).
optional_line="$(grep -E '^optional_filter=' scripts/ci-tests.sh || true)"
typeset -a kept
for suite in "${selected[@]}"; do
    if [[ "$suite" != */* ]] && print -r -- "$optional_line" | grep -qE "[(|]${suite}[|)]"; then
        notes+=("$suite is an optional-lane suite; skipped")
    else
        kept+=("$suite")
    fi
done
selected=("${kept[@]}")

for note in "${notes[@]}"; do print -u2 "note: $note"; done

if (( ${#selected} == 0 )); then
    print -u2 "No covering suites found. Pass suite names explicitly, e.g. $0 CropTests"
    exit 3
fi

filter="(${(j:|:)selected})"
print "Suites (${#selected}): ${(j:, :)selected}"
print "Rerun: swift test --filter '$filter'"
(( list_only )) && exit 0

exec swift test --filter "$filter"
