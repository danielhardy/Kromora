import Foundation

/// Production orchestration for one content-aware Auto invocation. All image work stays behind
/// the existing RenderEngine/PhotoAnalysis seams; the returned result is value-only and can be
/// applied atomically by the editor.
struct ContentAwareAutoEngine: Sendable {
    let engine: any RenderEngining & CurrentEditSampling
    let analysisCoordinator: PhotoAnalysisCoordinator
    let maskStore: MaskStore

    init(
        engine: any RenderEngining & CurrentEditSampling,
        analysisCoordinator: PhotoAnalysisCoordinator,
        maskStore: MaskStore
    ) {
        self.engine = engine
        self.analysisCoordinator = analysisCoordinator
        self.maskStore = maskStore
    }

    func run(
        source: ImageSource,
        assetID: PhotoAssetID,
        current: EditDocument,
        lut: CubeLUT? = nil
    ) async -> AutoEnhancementResult {
        if let fingerprint = current.lastAutoRunFingerprint,
           fingerprint.matches(source: source, document: current) {
            return AutoEnhancementResult(
                status: .unchanged, proposedDocument: current,
                algorithmVersion: AutoEnhancementPolicy.algorithmVersion,
                reasons: ["No further improvement found; the current Auto result is unchanged."],
                fingerprint: fingerprint
            )
        }
        let expectedHash = current.editHash
        let sourceKind: AutoSourceKind = source.kind == .raw ? .raw : .standard
        let sourceAnalysis = try? await analysisCoordinator.analyze(
            assetID: assetID, source: source, level: .standard
        )

        guard !Task.isCancelled else {
            return AutoEnhancementResult(
                status: .cancelled, proposedDocument: current,
                reasons: ["Auto was cancelled during analysis."]
            )
        }

        // Rehydrate only the already-known semantic references. This reuses MaskStore rather than
        // creating a second mask subsystem, and a missing individual mask merely lowers evidence.
        let masks = sourceAnalysis?.regions.map { region in
            RegionMask(
                id: region.id, kind: region.kind,
                bounds: region.bounds ?? NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                quality: region.mask.quality, reference: region.mask,
                confidence: region.confidence, coverage: region.coverage
            )
        } ?? []

        let measurer = CurrentEditMeasurer(engine: engine, store: maskStore)
        let measurement: CurrentEditMeasurement
        do {
            measurement = try await measurer.measure(
                source: source, assetID: assetID, document: current,
                expectedDocumentHash: expectedHash, lut: lut,
                configuration: .default, masks: masks
            )
        } catch is CancellationError {
            return AutoEnhancementResult(
                status: .cancelled, proposedDocument: current,
                reasons: ["Auto was cancelled while measuring the current edit."]
            )
        } catch {
            return AutoEnhancementResult(
                status: .renderUnavailable, proposedDocument: current,
                reasons: [error.localizedDescription]
            )
        }

        let classifications = sourceAnalysis?.sceneClassifications
        let scene = SceneCharacteristicsAnalyzer.analyze(
            measurement: measurement, classifications: classifications
        )
        let primarySubject = PrimarySubjectSelector.select(from: measurement.regions)
        let signalConfidence = AutoSignalConfidence.make(
            globalToneAvailable: true,
            color: SceneColorFacts.from(measurement.color),
            sceneConfidence: scene.sceneConfidence,
            regions: measurement.regions,
            primarySubject: primarySubject,
            classifications: classifications,
            detailAvailable: measurement.detail.available,
            failedMaskCount: measurement.failedMaskCount
        )
        let facts = AutoEnhancementFacts(
            measurement: measurement,
            scene: scene,
            signalConfidence: signalConfidence,
            asShotTemperature: current.rawDevelop.neutralTemperature,
            asShotTint: current.rawDevelop.neutralTint
        )
        let native = AutoEnhancementPolicy.propose(
            facts: facts, current: current, sourceKind: sourceKind
        )

        let apple = await AppleEnhancementReferenceAdapter(
            engine: engine, space: .sRGB
        ).referenceProposal(
            source: source, document: current, lut: lut, sourceKind: sourceKind,
            scene: scene, signalConfidence: signalConfidence,
            asShotTemperature: facts.asShotTemperature, asShotTint: facts.asShotTint
        ).proposal

        let coordinator = AutoEnhancementCoordinator(engine: engine)
        let selected = await coordinator.run(
            source: source, current: current, expectedDocumentHash: expectedHash,
            facts: facts, regions: measurement.regions, native: native, apple: apple,
            sourceKind: sourceKind, lut: lut
        )
        return .from(
            selected, current: current,
            confidence: max(native.confidence, signalConfidence.overall),
            source: source
        )
    }
}
