import CoreGraphics
import Foundation
import XCTest
@testable import KromoraKit

/// KRMA-347: the asynchronous bounded candidate coordinator must generate the unchanged,
/// native, Apple-reference, and reduced-strength candidates in a stable order, evaluate them
/// against frozen targets within hard render budgets, reject guardrail violations, prefer the
/// simpler edit on ties, and leave the document untouched on cancellation, staleness, or
/// failure — all without a GPU.
final class AutoEnhancementCoordinatorTests: TempDirectoryTestCase {

    // MARK: - Helpers

    /// Deterministic sampler: solid gray whose brightness follows the document's exposure.
    /// Brightness slope (0.25/EV) keeps a +1 EV correction near the 0.48 placement target.
    private actor StubAutoSampler: CurrentEditSampling {
        var handler: @Sendable (EditDocument) -> RenderedPixelSamples?
        var requests: [EditDocument] = []

        init(handler: @escaping @Sendable (EditDocument) -> RenderedPixelSamples?) {
            self.handler = handler
        }

        func renderedSamples(
            source: ImageSource,
            document: EditDocument,
            lut: CubeLUT?,
            targetLongEdge: Int,
            space: WorkingSpace
        ) async -> RenderedPixelSamples? {
            requests.append(document)
            return handler(document)
        }

        func requestCount() -> Int { requests.count }
    }

    private static func solidSamples(
        gray: Double, width: Int = 16, height: Int = 16
    ) -> RenderedPixelSamples {
        let byte = UInt8(min(max(gray, 0), 1) * 255)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            bytes[index * 4] = byte
            bytes[index * 4 + 1] = byte
            bytes[index * 4 + 2] = byte
        }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: .sRGB)
    }

    private static func exposureDrivenSampler(
        base: Double = 0.22, slope: Double = 0.25
    ) -> StubAutoSampler {
        StubAutoSampler { document in
            solidSamples(gray: base + document.light.exposure * slope)
        }
    }

    private static func testEvidence() -> AutoEvidenceUsed {
        AutoEvidenceUsed(
            toneMedian: 0.25, highlightClipping: 0, shadowClipping: 0,
            neutralConfidence: 0.8, recommendsNeutralCorrection: false,
            hueMixed: false, overallSignalConfidence: 0.9
        )
    }

    private static func darkFacts() -> AutoEnhancementFacts {
        var facts = AutoEnhancementFacts()
        facts.tonePerceptual = ToneStatistics(
            variant: .perceptual, mean: 0.25, p05: 0.1, p10: 0.15, p50: 0.25, p90: 0.4, p95: 0.45
        )
        facts.signalConfidence = AutoSignalConfidence(
            globalTone: 1, colorNeutral: 0.9, scene: 0.9, subjectRegions: 0,
            detail: nil, providers: .unavailable, overall: 0.9
        )
        return facts
    }

    private static func exposureProposal(
        current: EditDocument, exposure: Double, extraChanges: [AutoControlChange] = []
    ) -> AutoEnhancementProposal {
        var document = current
        document.light.exposure = exposure
        var changes = [AutoControlChange(
            control: .exposure, previous: current.light.exposure, proposed: exposure,
            confidence: 0.9, reason: "test placement", evidence: "test"
        )]
        for change in extraChanges {
            var applied = document
            applyTestChange(change, to: &applied)
            document = applied
            changes.append(change)
        }
        return AutoEnhancementProposal(
            document: document, changes: changes, confidence: 0.9,
            evidence: testEvidence(), notes: "test native"
        )
    }

    private static func applyTestChange(_ change: AutoControlChange, to document: inout EditDocument) {
        switch change.control {
        case .vibrance: document.color.vibrance = change.proposed
        case .saturation: document.color.saturation = change.proposed
        case .exposure: document.light.exposure = change.proposed
        default: break
        }
    }

    private static func appleProposal(
        current: EditDocument, exposure: Double, extraChanges: [AutoControlChange] = []
    ) -> AppleReferenceProposal {
        var document = current
        document.light.exposure = exposure
        var changes = [AutoControlChange(
            control: .exposure, previous: current.light.exposure, proposed: exposure,
            confidence: 0.6, reason: "test reference", evidence: "test"
        )]
        for change in extraChanges {
            var applied = document
            applyTestChange(change, to: &applied)
            document = applied
            changes.append(change)
        }
        let provenance = AppleReferenceProvenance(
            sourceKind: .standard, space: .sRGB, fitMethod: .renderCompare
        )
        return AppleReferenceProposal(
            document: document, changes: changes, confidence: 0.6,
            provenance: provenance, residualError: 0
        )
    }

    private static func standardSource() -> ImageSource {
        ImageSource(
            backing: .data(Data("stub-source".utf8)), kind: .standard,
            nativeExtent: CGSize(width: 64, height: 64)
        )
    }

    private static func rawSource() -> ImageSource {
        ImageSource(
            backing: .data(Data("stub-raw".utf8)), kind: .raw,
            nativeExtent: CGSize(width: 64, height: 64)
        )
    }

    // MARK: - Pure generation: ordering and provenance

    func testCandidateOrderingIsUnchangedNativeAppleReduced() {
        let current = EditDocument()
        let native = Self.exposureProposal(current: current, exposure: 1.0)
        let apple = Self.appleProposal(current: current, exposure: 0.8)

        let candidates = AutoCandidateGenerator.generate(
            current: current, native: native, apple: apple, sourceKind: .standard
        )

        XCTAssertEqual(candidates.map(\.provenance), [
            .unchanged, .native, .reducedNative(scale: 0.5),
            .appleReference, .reducedApple(scale: 0.5),
        ])
        // Reduced-strength documents interpolate halfway toward the current values.
        XCTAssertEqual(candidates[2].document.light.exposure, 0.5, accuracy: 1e-9)
        XCTAssertEqual(candidates[4].document.light.exposure, 0.4, accuracy: 1e-9)
        // Reduced change maps carry the reduced deltas so movement penalties see them.
        XCTAssertEqual(
            candidates[2].changes[.exposure]?.proposed ?? -1, 0.5, accuracy: 1e-9
        )
    }

    func testNoOpProposalsContributeNoCandidates() {
        let current = EditDocument()
        let noOpNative = AutoEnhancementProposal(
            document: current, changes: [], confidence: 0.9,
            evidence: Self.testEvidence()
        )
        XCTAssertTrue(noOpNative.isNoOp)

        let candidates = AutoCandidateGenerator.generate(
            current: current, native: noOpNative, apple: nil, sourceKind: .standard
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].provenance, .unchanged)
    }

    func testScaledDocumentClampsToControlRanges() {
        let current = EditDocument()
        let change = AutoControlChange(
            control: .exposure, previous: 0, proposed: 99,
            confidence: 1, reason: "test", evidence: "test"
        )
        let scaled = AutoCandidateGenerator.scaledDocument(
            current: current, changes: [.exposure: change],
            sourceKind: .standard, scale: 1
        )
        XCTAssertEqual(scaled.light.exposure, LightAdjustments.exposureRange.upperBound)
    }

    // MARK: - Frozen targets and pure scoring

    func testFrozenTargetsPreserveLowKeyIntent() {
        var facts = Self.darkFacts()
        facts.scene = SceneCharacteristics(lowKeyLikelihood: 1)
        let targets = AutoEvaluationTargets.frozen(facts: facts, regions: [])
        // Full low-key intent pins the target to the baseline median rather than 0.48.
        XCTAssertEqual(targets.globalTargetMedian, 0.25, accuracy: 1e-6)
    }

    func testFrozenTargetsDefaultToMiddleGrayPlacement() {
        let targets = AutoEvaluationTargets.frozen(facts: Self.darkFacts(), regions: [])
        XCTAssertEqual(targets.globalTargetMedian, 0.48, accuracy: 1e-6)
        XCTAssertTrue(targets.regions.isEmpty)
    }

    func testMissingRegionalEvidenceDegradesRatherThanFabricating() {
        let targets = AutoEvaluationTargets.frozen(facts: Self.darkFacts(), regions: [])
        let current = EditDocument()
        let unchanged = AutoCandidate(provenance: .unchanged, document: current)
        let samples = Self.solidSamples(gray: 0.25)
        let baseline = AutoPixelBaseline.frozen(samples: samples)
        let score = AutoCandidateScoring.score(
            samples: samples, candidate: unchanged,
            targets: targets, baseline: baseline, isUnchanged: true
        )
        // No regions and no neutral reference: explicit degradation penalties apply.
        XCTAssertEqual(score.missingEvidencePenalty, 0.05, accuracy: 1e-9)
        XCTAssertFalse(score.rejected)
    }

    func testUnmeasurableRenderScoresPenalizedAndRejectsChangedCandidates() {
        let targets = AutoEvaluationTargets.frozen(facts: Self.darkFacts(), regions: [])
        let changed = AutoCandidate(
            provenance: .native, document: EditDocument(),
            changes: [.exposure: AutoControlChange(
                control: .exposure, previous: 0, proposed: 1,
                confidence: 1, reason: "t", evidence: "t"
            )]
        )
        let empty = RenderedPixelSamples(width: 0, height: 0, bytes: [], space: .sRGB)
        let baseline = AutoPixelBaseline(
            localContrast: 0, noise: 0
        )
        let score = AutoCandidateScoring.score(
            samples: empty, candidate: changed,
            targets: targets, baseline: baseline, isUnchanged: false
        )
        XCTAssertTrue(score.rejected)
        XCTAssertTrue(score.rejectionReasons.contains("render-unmeasurable"))
    }

    func testGuardrailThresholdsRejectClippingAndExtremeSaturation() {
        XCTAssertGreaterThan(AutoCandidateScoring.absoluteClippingCap, 0)
        XCTAssertGreaterThan(
            AutoCandidateScoring.absoluteSaturationCap,
            AutoCandidateScoring.absoluteClippingCap
        )
        let targets = AutoEvaluationTargets.frozen(facts: Self.darkFacts(), regions: [])
        let white = Self.solidSamples(gray: 1.0)
        let baseline = AutoPixelBaseline.frozen(samples: Self.solidSamples(gray: 0.25))
        let candidate = AutoCandidate(
            provenance: .native, document: EditDocument(),
            changes: [.exposure: AutoControlChange(
                control: .exposure, previous: 0, proposed: 2,
                confidence: 1, reason: "t", evidence: "t"
            )]
        )
        let score = AutoCandidateScoring.score(
            samples: white, candidate: candidate,
            targets: targets, baseline: baseline, isUnchanged: false
        )
        XCTAssertTrue(score.rejected)
        XCTAssertTrue(score.rejectionReasons.contains("clipping"))
        // The same white render as the status quo is never rejected.
        let unchanged = AutoCandidate(provenance: .unchanged, document: EditDocument())
        let baselineScore = AutoCandidateScoring.score(
            samples: white, candidate: unchanged,
            targets: targets, baseline: baseline, isUnchanged: true
        )
        XCTAssertFalse(baselineScore.rejected)
    }

    func testMaskEdgeGuardrailRejectsSpikyContrastWhenMasksWereAdded() {
        let targets = AutoEvaluationTargets.frozen(facts: Self.darkFacts(), regions: [])
        // Flat baseline: local contrast is zero, so any adjacent-block spike is amplified.
        let baseline = AutoPixelBaseline(localContrast: 0, noise: 0)
        // 64x64 half-dark/half-bright checkerboard of blocks produces a strong local-contrast
        // spike (`RenderedPixelAnalyzer.localContrast` compares 32px block means).
        let width = 64, height = 64
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let bright = ((x / 32) + (y / 32)).isMultiple(of: 2)
                let byte: UInt8 = bright ? 255 : 0
                let offset = (y * width + x) * 4
                bytes[offset] = byte
                bytes[offset + 1] = byte
                bytes[offset + 2] = byte
            }
        }
        let spiky = RenderedPixelSamples(width: width, height: height, bytes: bytes, space: .sRGB)
        let candidateWithMask = AutoCandidate(
            provenance: .native, document: EditDocument(), addedMaskCount: 1
        )
        let score = AutoCandidateScoring.score(
            samples: spiky, candidate: candidateWithMask,
            targets: targets, baseline: baseline, isUnchanged: false
        )
        XCTAssertTrue(score.rejected)
        XCTAssertTrue(score.rejectionReasons.contains("mask-edge"), "reasons: \(score.rejectionReasons)")

        // The identical render costs the same contrast spike, but the candidate touched no
        // masks: the mask-edge guardrail does not fire (spike still counts toward the score
        // at reduced weight, but it is not a rejection reason).
        let candidateNoMask = AutoCandidate(provenance: .native, document: EditDocument())
        let unguardedScore = AutoCandidateScoring.score(
            samples: spiky, candidate: candidateNoMask,
            targets: targets, baseline: baseline, isUnchanged: false
        )
        XCTAssertFalse(unguardedScore.rejectionReasons.contains("mask-edge"))
    }

    // MARK: - End-to-end selection

    func testImprovedCandidateSelectedOverUnchanged() async {
        let current = EditDocument()
        let sampler = Self.exposureDrivenSampler()
        let coordinator = AutoEnhancementCoordinator(engine: sampler)
        let native = Self.exposureProposal(current: current, exposure: 1.0)

        let result = await coordinator.run(
            source: Self.standardSource(), current: current,
            expectedDocumentHash: current.editHash, facts: Self.darkFacts(),
            native: native, apple: nil, sourceKind: .standard
        )

        XCTAssertEqual(result.status, .improved)
        XCTAssertEqual(result.provenance, .native)
        XCTAssertFalse(result.leavesDocumentUnchanged)
        XCTAssertEqual(result.document.light.exposure, 1.0)
        XCTAssertEqual(result.budget.smallRenders, 3) // unchanged + native + reduced
        XCTAssertEqual(result.budget.rawRedevelopments, 0)
        XCTAssertEqual(result.evaluatedDocumentHash, current.editHash)
        // The input value is never mutated.
        XCTAssertEqual(current, EditDocument())
        // Budget counters stay within the hard bounds.
        XCTAssertLessThanOrEqual(result.budget.smallRenders, 24)
        XCTAssertLessThanOrEqual(result.budget.rawRedevelopments, 4)
    }

    func testUnchangedWinsWhenImprovementIsNegligible() async {
        let current = EditDocument()
        let sampler = Self.exposureDrivenSampler()
        let coordinator = AutoEnhancementCoordinator(engine: sampler)
        let native = Self.exposureProposal(current: current, exposure: 0.06)

        let result = await coordinator.run(
            source: Self.standardSource(), current: current,
            expectedDocumentHash: current.editHash, facts: Self.darkFacts(),
            native: native, apple: nil, sourceKind: .standard
        )

        XCTAssertEqual(result.status, .unchanged)
        XCTAssertTrue(result.leavesDocumentUnchanged)
        XCTAssertEqual(result.document, current)
        XCTAssertTrue(result.message.contains("no further improvement"))
    }

    func testGuardrailRejectionAcrossAllChangedCandidatesYieldsNoCandidate() async {
        let current = EditDocument()
        // Every changed render clips to white; the baseline stays dark gray.
        let sampler = StubAutoSampler { document in
            document.light.exposure > 0.1
                ? Self.solidSamples(gray: 1.0)
                : Self.solidSamples(gray: 0.25)
        }
        let coordinator = AutoEnhancementCoordinator(engine: sampler)
        let native = Self.exposureProposal(current: current, exposure: 0.5)

        let result = await coordinator.run(
            source: Self.standardSource(), current: current,
            expectedDocumentHash: current.editHash, facts: Self.darkFacts(),
            native: native, apple: nil, sourceKind: .standard
        )

        XCTAssertEqual(result.status, .noCandidate)
        XCTAssertTrue(result.leavesDocumentUnchanged)
        XCTAssertEqual(result.document, current)
        XCTAssertTrue(
            (result.candidateNotes["native"] ?? "").contains("clipping"),
            "notes: \(result.candidateNotes)"
        )
    }

    func testTieBreakPrefersSimplerCandidateWithinEpsilon() async {
        let current = EditDocument()
        let sampler = Self.exposureDrivenSampler()
        var configuration = AutoCoordinatorConfiguration.default
        configuration.tieEpsilon = 0.05
        let coordinator = AutoEnhancementCoordinator(engine: sampler, configuration: configuration)
        // Native moves one control; Apple lands negligibly closer on pixels but moves two.
        let native = Self.exposureProposal(current: current, exposure: 1.0)
        let apple = Self.appleProposal(
            current: current, exposure: 1.02,
            extraChanges: [AutoControlChange(
                control: .vibrance, previous: 0, proposed: 2,
                confidence: 0.6, reason: "test", evidence: "test"
            )]
        )

        let result = await coordinator.run(
            source: Self.standardSource(), current: current,
            expectedDocumentHash: current.editHash, facts: Self.darkFacts(),
            native: native, apple: apple, sourceKind: .standard
        )

        XCTAssertEqual(result.status, .improved)
        XCTAssertEqual(result.provenance, .native)
    }

    // MARK: - Budgets

    func testSmallRenderBudgetIsHardBounded() async {
        let current = EditDocument()
        let sampler = Self.exposureDrivenSampler()
        var configuration = AutoCoordinatorConfiguration.default
        configuration.maxSmallRenders = 2
        let coordinator = AutoEnhancementCoordinator(engine: sampler, configuration: configuration)
        let native = Self.exposureProposal(current: current, exposure: 1.0)
        let apple = Self.appleProposal(current: current, exposure: 0.8)

        let result = await coordinator.run(
            source: Self.standardSource(), current: current,
            expectedDocumentHash: current.editHash, facts: Self.darkFacts(),
            native: native, apple: apple, sourceKind: .standard
        )

        XCTAssertEqual(result.budget.smallRenders, 2)
        XCTAssertEqual(result.budget.evaluated, 2)
        XCTAssertEqual(result.budget.skipped, 3)
        let requestCount = await sampler.requestCount()
        XCTAssertEqual(requestCount, 2)
    }

    func testRAWRecoveryBudgetCapsRedevelopments() async {
        let current = EditDocument()
        let sampler = Self.exposureDrivenSampler()
        var configuration = AutoCoordinatorConfiguration.default
        configuration.maxRAWRedevelopments = 1
        let coordinator = AutoEnhancementCoordinator(engine: sampler, configuration: configuration)
        let native = Self.exposureProposal(current: current, exposure: 1.0)

        let result = await coordinator.run(
            source: Self.rawSource(), current: current,
            expectedDocumentHash: current.editHash, facts: Self.darkFacts(),
            native: native, apple: nil, sourceKind: .raw
        )

        XCTAssertEqual(result.budget.rawRedevelopments, 1)
        XCTAssertEqual(result.budget.smallRenders, 1)
        XCTAssertEqual(result.budget.evaluated, 1)
        XCTAssertEqual(result.budget.skipped, 2)
        XCTAssertEqual(result.status, .unchanged)
        XCTAssertTrue(result.leavesDocumentUnchanged)
    }

    func testTimeBudgetStopsAfterBaseline() async {
        let current = EditDocument()
        let sampler = Self.exposureDrivenSampler()
        var configuration = AutoCoordinatorConfiguration.default
        configuration.timeBudgetSeconds = 0
        let coordinator = AutoEnhancementCoordinator(engine: sampler, configuration: configuration)
        let native = Self.exposureProposal(current: current, exposure: 1.0)

        let result = await coordinator.run(
            source: Self.standardSource(), current: current,
            expectedDocumentHash: current.editHash, facts: Self.darkFacts(),
            native: native, apple: nil, sourceKind: .standard
        )

        // The baseline always renders; the time budget stops everything after it.
        XCTAssertEqual(result.budget.evaluated, 1)
        XCTAssertEqual(result.budget.skipped, 2)
        XCTAssertEqual(result.status, .unchanged)
    }

    // MARK: - Cancellation and revision guards

    func testStaleRevisionRendersNothing() async {
        let current = EditDocument()
        let sampler = Self.exposureDrivenSampler()
        let coordinator = AutoEnhancementCoordinator(engine: sampler)
        let native = Self.exposureProposal(current: current, exposure: 1.0)

        let result = await coordinator.run(
            source: Self.standardSource(), current: current,
            expectedDocumentHash: "stale-hash", facts: Self.darkFacts(),
            native: native, apple: nil, sourceKind: .standard
        )

        XCTAssertEqual(result.status, .staleRevision)
        XCTAssertTrue(result.leavesDocumentUnchanged)
        XCTAssertEqual(result.document, current)
        let requestCount = await sampler.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testCancellationDuringEvaluationReturnsWithoutApplying() async {
        let current = EditDocument()
        let gate = GatedAutoSampler()
        let coordinator = AutoEnhancementCoordinator(engine: gate)
        let native = Self.exposureProposal(current: current, exposure: 1.0)

        let runSource = Self.standardSource()
        let runHash = current.editHash
        let runFacts = Self.darkFacts()
        let runCoordinator = coordinator
        let runNative = native
        let task = Task.detached { @Sendable in
            await runCoordinator.run(
                source: runSource, current: current,
                expectedDocumentHash: runHash, facts: runFacts,
                native: runNative, apple: nil, sourceKind: .standard
            )
        }
        // Wait until the baseline render is parked inside the sampler, then cancel.
        while await gate.requestCount() == 0 { await Task.yield() }
        task.cancel()
        await gate.release()
        let result = await task.value

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertTrue(result.leavesDocumentUnchanged)
        XCTAssertEqual(result.document, current)
    }

    // MARK: - Real renderer evidence (representative fixture)

    /// One run through the actual `RenderEngine` proves the coordinator drives the real
    /// pipeline seam; pixel assertions about the pipeline itself belong to engine tests.
    func testRealEngineCoordinatorRunOnGradientFixture() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "auto-coord.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let coordinator = AutoEnhancementCoordinator(engine: RenderEngine())
        let current = EditDocument()
        let native = Self.exposureProposal(current: current, exposure: 0.5)

        let result = await coordinator.run(
            source: source, current: current,
            expectedDocumentHash: current.editHash, facts: AutoEnhancementFacts(),
            native: native, apple: nil, sourceKind: .standard
        )

        XCTAssertTrue(
            [.improved, .unchanged, .noCandidate].contains(result.status),
            "unexpected status: \(result.status) message: \(result.message)"
        )
        XCTAssertLessThanOrEqual(result.budget.smallRenders, 24)
        XCTAssertLessThanOrEqual(result.budget.rawRedevelopments, 4)
        XCTAssertGreaterThan(result.budget.evaluated, 0)
        XCTAssertEqual(current, EditDocument())
    }
}

/// Sampler that parks the first render until the test releases it, so mid-run cancellation is
/// deterministic rather than a race between task start and `cancel()`.
private actor GatedAutoSampler: CurrentEditSampling {
    private var requests = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func requestCount() -> Int { requests }

    func release() {
        let parked = continuations
        continuations.removeAll()
        for continuation in parked { continuation.resume() }
    }

    func renderedSamples(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        targetLongEdge: Int,
        space: WorkingSpace
    ) async -> RenderedPixelSamples? {
        requests += 1
        await withCheckedContinuation { continuations.append($0) }
        guard !Task.isCancelled else { return nil }
        let byte: UInt8 = 64
        var bytes = [UInt8](repeating: 255, count: 16 * 16 * 4)
        for index in 0..<(16 * 16) {
            bytes[index * 4] = byte
            bytes[index * 4 + 1] = byte
            bytes[index * 4 + 2] = byte
        }
        return RenderedPixelSamples(width: 16, height: 16, bytes: bytes, space: space)
    }
}
