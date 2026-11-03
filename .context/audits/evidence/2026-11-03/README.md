# November 3 code-quality audit evidence

These standalone probes reproduce audit findings without modifying product source or adding tests
to the shipping package. They use generated values, disposable temporary packages, and a fresh
UserDefaults suite. They do not open the user's photo library or existing preferences.

- [code-quality-probes.swift](code-quality-probes.swift): scheduler accounting/barrier, retained
  undo payload accounting, and named-snapshot versus newer-edit persistence.
- [additional-quality-probes.swift](additional-quality-probes.swift): detailed analysis after a
  global-only cache hit, retouch completion after navigation/shutdown, and embedded Look resolution
  and reference retention after removing an external cube.
- [results.txt](results.txt): recorded outputs, toolchain, and focused-test result.

Run from the repository root with Xcode 27. The object/resource paths below are those emitted by
the reviewed checkout's Xcode-backed SwiftPM build. If a different builder emits a different
products directory, use its freshly built Debug module/object and matching resource bundle; do not
link a stale Release artifact.

```sh
CLANG_MODULE_CACHE_PATH=/tmp/kromora-audit-module-cache \
swift build --disable-sandbox --cache-path /tmp/kromora-audit-swiftpm-cache \
  --manifest-cache local

audit_evidence=.context/audits/evidence/2026-11-03
for probe in code-quality-probes additional-quality-probes; do
  CLANG_MODULE_CACHE_PATH=/tmp/kromora-audit-module-cache \
  xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx26.0 \
    -I .build/out/Products/Debug "$audit_evidence/$probe.swift" \
    .build/out/Products/Debug/KromoraKit.o -o "/tmp/$probe"
  PACKAGE_RESOURCE_BUNDLE_PATH="$PWD/.build/out/Products/Debug" "/tmp/$probe"
done
```

The resource-bundle environment override is required for the additional standalone executable:
it creates a production renderer while exercising a cache hit. Missing that override causes
SwiftPM's generated bundle accessor to abort; that harness-setup failure is not a product finding.

The scheduler and retouch gates model framework calls that finish after cancellation. They
establish ownership and ordering defects, not a measured number of simultaneously running ImageIO
decoders. The retention probe sums production value-payload estimates rather than process RSS.
The snapshot and Look probes use the actual package transaction/edit store implementations with
synthetic source bytes; they test persistence semantics, not image decoding or photographic quality.

The recorded baseline command was:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/kromora-audit-module-cache \
swift test --disable-sandbox --cache-path /tmp/kromora-audit-swiftpm-cache \
  --manifest-cache local --no-parallel \
  --filter 'ImageWorkSchedulerTests|EditDocumentRetentionCostTests|EditHistoryCoordinatorTests|PhotoAnalysisCoordinatorTests|EditDocumentStoreTests|LookSelectionCoordinatorTests|RetouchWorkflowCoordinatorTests'
```

That command executed 72 tests with zero failures. No full lane or display-bound benchmark was run.
