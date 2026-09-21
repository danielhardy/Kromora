import Foundation

/// Production orchestration for one content-aware Auto invocation. All image work stays behind
/// the existing RenderEngine/PhotoAnalysis seams; the returned result is value-only and can be
/// applied atomically by the editor.
struct ContentAwareAutoEngine: Sendable {
    let engine: any RenderEngining & CurrentEditSampling
    let analysisCoordinator: PhotoAnalysisCoordinator
    let maskStore: MaskStore

    func run(
        source: ImageSource,
        assetID: PhotoAssetID,
        current: EditDocument,
        lut: CubeLUT? = nil,
        onProgress: (@MainActor @Sendable (AutoEnhancementPhase) -> Void)? = nil
    ) async -> AutoEnhancementResult {
        // KRMA-352 telemetry: a few `ContinuousClock` reads plus signpost intervals.
        // Timings are recorded, never read by selection — attaching them cannot change
        // candidate behavior. Decode (image preparation) is separated from Auto work.
        let clock = ContinuousClock()
        let totalStart = clock.now
        var totalInterval = KromoraObservability.begin(.autoTotal, source: source)
        defer { totalInterval.end() }
        func partialTimings() -> AutoRunTimings {
            AutoRunTimings(
                totalSeconds: AutoTimingClock.seconds(totalStart.duration(to: clock.now))
            )
        }
        if let fingerprint = current.lastAutoRunFingerprint,
            fingerprint.matches(source: source, document: current)
        {
            return AutoEnhancementResult(
                status: .unchanged, proposedDocument: current,
                algorithmVersion: AutoEnhancementPolicy.algorithmVersion,
                reasons: ["No further improvement found; the current Auto result is unchanged."],
                fingerprint: fingerprint,
                timings: partialTimings()
            )
        }
        // Evaluate from a clean Auto-owned global baseline. The complete document is still used
        // by the caller for stale-revision protection and final application; this baseline only
        // prevents previous Light/Color values from suppressing a fresh Auto proposal.
        let autoBaseline = current.autoAdjustmentBaseline
        let expectedHash = autoBaseline.editHash
        await onProgress?(.analyzing)
        let sourceKind: AutoSourceKind = source.kind == .raw ? .raw : .standard
        let analysisStart = clock.now
        var analysisInterval = KromoraObservability.begin(
            .autoAnalysis, source: source, maskQuality: .analysis
        )
        let sourceAnalysis = try? await analysisCoordinator.analyze(
            assetID: assetID, source: source, level: .standard
        )
        analysisInterval.end()
        let analysisElapsed = AutoTimingClock.seconds(analysisStart.duration(to: clock.now))
        // Decode is the image-preparation portion of the analysis; everything else is Auto work.
        // Clamp to the measured analyze window so a cache-hit warm run (which performs no
        // decode) reports ~zero decode rather than the cached analysis's stale value.
        let rawDecode = sourceAnalysis.map { AutoTimingClock.decodeSeconds($0.timings) } ?? 0
        let decodeSeconds = min(rawDecode, analysisElapsed)
        let analysisSeconds = max(0, analysisElapsed - decodeSeconds)
        // A cache hit returns the original analysis timings, but no mask work ran during this
        // invocation. Bound the diagnostic subset to the current analysis window so warm runs do
        // not report stale mask-generation latency from the cached record.
        let rawMaskSeconds = sourceAnalysis.map { AutoTimingClock.maskSeconds($0.timings) } ?? 0
        let maskSeconds = min(rawMaskSeconds, analysisSeconds)

        guard !Task.isCancelled else {
            return AutoEnhancementResult(
                status: .cancelled, proposedDocument: current,
                reasons: ["Auto was cancelled during analysis."],
                timings: AutoRunTimings(
                    decodeSeconds: decodeSeconds, analysisSeconds: analysisSeconds,
                    maskSeconds: maskSeconds,
                    totalSeconds: AutoTimingClock.seconds(totalStart.duration(to: clock.now))
                )
            )
        }

        // Rehydrate only the already-known semantic references. This reuses MaskStore rather than
        // creating a second mask subsystem, and a missing individual mask merely lowers evidence.
        let masks =
            sourceAnalysis?.regions.map { region in
                RegionMask(
                    id: region.id, kind: region.kind,
                    bounds: region.bounds ?? NormalizedRect(x: 0, y: 0, width: 0, height: 0),
                    quality: region.mask.quality, reference: region.mask,
                    confidence: region.confidence, coverage: region.coverage
                )
            } ?? []

        await onProgress?(.renderingCandidates)
        let measurer = CurrentEditMeasurer(engine: engine, store: maskStore)
        let measurement: CurrentEditMeasurement
        let measurementStart = clock.now
        do {
            measurement = try await measurer.measure(
                source: source, assetID: assetID, document: autoBaseline,
                expectedDocumentHash: expectedHash, lut: lut,
                configuration: .default, masks: masks
            )
        } catch is CancellationError {
            return AutoEnhancementResult(
                status: .cancelled, proposedDocument: current,
                reasons: ["Auto was cancelled while measuring the current edit."],
                timings: AutoRunTimings(
                    decodeSeconds: decodeSeconds, analysisSeconds: analysisSeconds,
                    maskSeconds: maskSeconds,
                    measurementSeconds: AutoTimingClock.seconds(
                        measurementStart.duration(to: clock.now)),
                    totalSeconds: AutoTimingClock.seconds(totalStart.duration(to: clock.now))
                )
            )
        } catch {
            return AutoEnhancementResult(
                status: .renderUnavailable, proposedDocument: current,
                reasons: [error.localizedDescription],
                timings: AutoRunTimings(
                    decodeSeconds: decodeSeconds, analysisSeconds: analysisSeconds,
                    maskSeconds: maskSeconds,
                    measurementSeconds: AutoTimingClock.seconds(
                        measurementStart.duration(to: clock.now)),
                    totalSeconds: AutoTimingClock.seconds(totalStart.duration(to: clock.now))
                )
            )
        }
        let measurementSeconds = AutoTimingClock.seconds(
            measurementStart.duration(to: clock.now))

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
            asShotTemperature: autoBaseline.rawDevelop.neutralTemperature,
            asShotTint: autoBaseline.rawDevelop.neutralTint
        )
        let native = AutoEnhancementPolicy.propose(
            facts: facts, current: autoBaseline, sourceKind: sourceKind
        )

        // The Apple-reference adapter renders the analysis view through the sampler; that
        // render work belongs to the candidate-render stage, so it is clocked here.
        let appleReferenceStart = clock.now
        let apple = await AppleEnhancementReferenceAdapter(
            engine: engine, space: .sRGB
        ).referenceProposal(
            source: source, document: autoBaseline, lut: lut, sourceKind: sourceKind,
            scene: scene, signalConfidence: signalConfidence,
            asShotTemperature: facts.asShotTemperature, asShotTint: facts.asShotTint
        ).proposal
        let appleReferenceSeconds = AutoTimingClock.seconds(
            appleReferenceStart.duration(to: clock.now))

        let coordinator = AutoEnhancementCoordinator(engine: engine)
        var renderInterval = KromoraObservability.begin(.autoCandidateRender, source: source)
        let selected = await coordinator.run(
            source: source, current: autoBaseline, expectedDocumentHash: expectedHash,
            facts: facts, regions: measurement.regions, native: native, apple: apple,
            sourceKind: sourceKind, lut: lut, onProgress: onProgress
        )
        renderInterval.end()

        // Regional corrections are planned from the selected global candidate, not from the
        // source/current measurement above. This keeps a region that the global proposal already
        // fixed from earning a redundant local layer, while retaining the same renderer and
        // MaskStore seams for the post-global evidence.
        await onProgress?(.validating)
        let regionalStart = clock.now
        // Assemble the final timings from the frozen stage clocks and the coordinator
        // budget. Persistence stays zero here by design: the apply path owns async
        // coalesced persistence outside the engine, so the engine reports rather than guesses.
        func finalTimings(regionalSeconds: Double, budget: AutoRenderBudgetUsage)
            -> AutoRunTimings
        {
            AutoRunTimings(
                decodeSeconds: decodeSeconds,
                analysisSeconds: analysisSeconds,
                maskSeconds: maskSeconds,
                measurementSeconds: measurementSeconds,
                candidateRenderSeconds: budget.renderSeconds + appleReferenceSeconds,
                rawRedevelopmentSeconds: budget.rawRenderSeconds,
                validationSeconds: budget.scoringSeconds,
                regionalSeconds: regionalSeconds,
                totalSeconds: AutoTimingClock.seconds(totalStart.duration(to: clock.now)),
                candidateCount: budget.evaluated + budget.skipped,
                evaluatedCount: budget.evaluated,
                smallRenders: budget.smallRenders,
                rawRedevelopments: budget.rawRedevelopments
            )
        }
        let regionalPlan: AutoRegionalPlan
        switch selected.status {
        case .improved, .unchanged, .noCandidate:
            regionalPlan = await regionalCorrections(
                source: source,
                assetID: assetID,
                document: selected.document,
                masks: masks,
                lut: lut
            )
        case .cancelled, .staleRevision, .renderUnavailable:
            regionalPlan = AutoRegionalCorrections.plan(
                AutoRegionalPlanInput(
                    existingLayerNames: selected.document.localAdjustments.map(\.name)
                )
            )
        }
        guard !Task.isCancelled else {
            return AutoEnhancementResult(
                status: .cancelled,
                proposedDocument: current,
                reasons: ["Auto was cancelled while planning regional corrections."],
                timings: finalTimings(
                    regionalSeconds: AutoTimingClock.seconds(
                        regionalStart.duration(to: clock.now)),
                    budget: selected.budget
                )
            )
        }

        var selectedWithRegionalCorrections = selected
        let regionalDocument = AutoRegionalCorrections.applying(
            regionalPlan, to: selected.document
        )
        if regionalDocument != selected.document {
            // A regional-only improvement is still an accepted Auto result. The global
            // coordinator may have found no worthwhile global slider change, but the measured
            // conflict is independently actionable and must remain atomic/undoable.
            selectedWithRegionalCorrections = AutoEnhancementCoordinatorResult(
                status: .improved,
                document: regionalDocument,
                provenance: selected.provenance,
                message: selected.status == .improved
                    ? selected.message
                    : "Regional corrections added after the global Auto evaluation.",
                budget: selected.budget,
                candidateNotes: selected.candidateNotes,
                selectedScore: selected.selectedScore,
                evaluatedDocumentHash: selected.evaluatedDocumentHash,
                sourceFingerprint: selected.sourceFingerprint
            )
        }
        if selectedWithRegionalCorrections.status == .unchanged,
            selectedWithRegionalCorrections.document != current
        {
            // Candidates are evaluated from the clean Auto baseline, so "unchanged" means Auto's
            // answer is the neutral baseline. When the current document carries Auto-owned values
            // that differ from it, keeping them would be the silent no-op this run must replace.
            selectedWithRegionalCorrections = AutoEnhancementCoordinatorResult(
                status: .improved,
                document: selectedWithRegionalCorrections.document,
                provenance: selectedWithRegionalCorrections.provenance,
                message: "Auto replaced existing adjustments with a neutral result.",
                budget: selectedWithRegionalCorrections.budget,
                candidateNotes: selectedWithRegionalCorrections.candidateNotes,
                selectedScore: selectedWithRegionalCorrections.selectedScore,
                evaluatedDocumentHash: selectedWithRegionalCorrections.evaluatedDocumentHash,
                sourceFingerprint: selectedWithRegionalCorrections.sourceFingerprint
            )
        }
        return .from(
            selectedWithRegionalCorrections, current: current,
            confidence: max(native.confidence, signalConfidence.overall),
            source: source,
            regionalNotes: regionalPlan.notes,
            timings: finalTimings(
                regionalSeconds: AutoTimingClock.seconds(
                    regionalStart.duration(to: clock.now)),
                budget: selected.budget
            )
        )
    }

    /// Measure the accepted global document through the existing regional mask seam and turn the
    /// resulting facts into the pure KRMA-348 planner input. Missing pixels or post-global render
    /// failures deliberately become planner notes rather than guessed corrections.
    private func regionalCorrections(
        source: ImageSource,
        assetID: PhotoAssetID,
        document: EditDocument,
        masks: [RegionMask],
        lut: CubeLUT?
    ) async -> AutoRegionalPlan {
        let existingLayerNames = document.localAdjustments.map(\.name)
        guard !masks.isEmpty else {
            return AutoRegionalCorrections.plan(
                AutoRegionalPlanInput(existingLayerNames: existingLayerNames)
            )
        }

        let measurer = CurrentEditMeasurer(engine: engine, store: maskStore)
        let postGlobal: CurrentEditMeasurement
        do {
            postGlobal = try await measurer.measure(
                source: source,
                assetID: assetID,
                document: document,
                expectedDocumentHash: document.editHash,
                lut: lut,
                configuration: .default,
                masks: masks
            )
        } catch is CancellationError {
            return AutoRegionalCorrections.plan(
                AutoRegionalPlanInput(existingLayerNames: existingLayerNames)
            )
        } catch {
            var plan = AutoRegionalCorrections.plan(
                AutoRegionalPlanInput(existingLayerNames: existingLayerNames)
            )
            plan.notes.insert(
                "Regional corrections skipped: post-global regional measurement was unavailable.",
                at: 0
            )
            return plan
        }

        let regionsByID = Dictionary(uniqueKeysWithValues: masks.map { ($0.id, $0) })
        let postRegions = postGlobal.regions
        let primary = PrimarySubjectSelector.select(from: postRegions)
        let subjectRegion = primary.primaryRegionID.flatMap { id in
            postRegions.first { $0.id == id }
        }
        let backgroundRegion = postRegions.first { $0.kind == .background }

        let subjectEvidence = await regionalEvidence(
            for: subjectRegion, masksByID: regionsByID
        )
        let backgroundEvidence = await regionalEvidence(
            for: backgroundRegion, masksByID: regionsByID
        )

        let overlap: Float?
        if let subjectPixels = subjectEvidence?.pixels,
            let backgroundPixels = backgroundEvidence?.pixels
        {
            overlap = AutoRegionalCorrections.intersectionOverUnion(
                subjectPixels, backgroundPixels
            )
        } else if subjectEvidence != nil, backgroundEvidence != nil {
            // Both regional facts were measured, but their pixel support could not be compared.
            // Passing nil is intentional: the planner refuses opposing corrections without
            // verified separation.
            overlap = nil
        } else {
            overlap = nil
        }

        let colorCast = subjectRegion.map(Self.regionalColorCast) ?? 0
        let input = AutoRegionalPlanInput(
            subjectTone: subjectRegion.map(Self.regionalToneEvidence),
            subjectMask: subjectEvidence?.facts,
            prefersPersonTarget: subjectRegion.map(Self.prefersPersonTarget) ?? false,
            backgroundTone: backgroundRegion.map(Self.regionalToneEvidence),
            backgroundMask: backgroundEvidence?.facts,
            subjectBackgroundOverlap: overlap,
            colorCast: colorCast,
            crop: document.crop.normalizedRect.map(NormalizedRect.init),
            existingLayerNames: existingLayerNames
        )
        return AutoRegionalCorrections.plan(input)
    }

    private struct RegionalEvidence: Sendable {
        let facts: AutoRegionalMaskFacts
        let pixels: NormalizedMask
    }

    private func regionalEvidence(
        for region: AnalyzedRegion?, masksByID: [UUID: RegionMask]
    ) async -> RegionalEvidence? {
        guard let region,
            let mask = masksByID[region.id],
            let pixels = await maskStore.pixels(for: mask.reference)
        else { return nil }
        return RegionalEvidence(
            facts: AutoRegionalCorrections.facts(
                pixels: pixels, confidence: region.confidence,
                bounds: region.bounds ?? mask.bounds
            ),
            pixels: pixels
        )
    }

    private static func regionalToneEvidence(
        _ region: AnalyzedRegion
    ) -> AutoRegionalToneEvidence {
        AutoRegionalToneEvidence(
            median: region.tone.p50,
            highlightClipping: region.tone.highlightClippingFraction,
            shadowClipping: region.tone.shadowClippingFraction,
            cast: regionalColorCast(region)
        )
    }

    private static func regionalColorCast(_ region: AnalyzedRegion) -> Float {
        regionalColorCast(region.color)
    }

    /// Positive means the measured region is cooler (blue exceeds red), matching the planner's
    /// signed-cast contract and its counter-steering temperature correction.
    private static func regionalColorCast(_ color: ColorStatistics) -> Float {
        let cast = color.meanRGB.z - color.meanRGB.x
        return cast.isFinite ? min(max(cast, -1), 1) : 0
    }

    private static func prefersPersonTarget(_ region: AnalyzedRegion) -> Bool {
        if case .person = region.kind { return true }
        return false
    }
}
