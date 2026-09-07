import CoreImage
import CoreVideo
import Foundation
import Vision

/// The revisions that participate in mask cache identity. Revision 2 of attention saliency is
/// available on macOS 14. Changing one invalidates only the affected cached masks.
struct VisionConfiguration: Codable, Sendable, Equatable, Hashable {
    let attentionRevision: Int
    let foregroundRevision: Int
    let faceRevision: Int
    let personRevision: Int

    init(attentionRevision: Int = 2, foregroundRevision: Int = 1, faceRevision: Int = 1, personRevision: Int = 1) {
        self.attentionRevision = max(1, attentionRevision)
        self.foregroundRevision = max(1, foregroundRevision)
        self.faceRevision = max(1, faceRevision)
        self.personRevision = max(1, personRevision)
    }

    static let `default` = VisionConfiguration()

    var providerVersion: String {
        "vision-a\(attentionRevision)-f\(foregroundRevision)-face\(faceRevision)-person\(personRevision)"
    }
}

enum VisionSemanticMaskError: LocalizedError, Sendable, Equatable {
    case unsupported(SemanticMaskKind)
    case unableToDecodeImage
    case noSalientRegion
    case noFaceDetected
    case faceIndexOutOfRange(Int)
    case foregroundIndexOutOfRange(Int)
    case personNotApplicable
    case noPersonDetected
    case unsupportedQuality(MaskQuality, SemanticMaskKind)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let kind): return "Vision mask kind is not supported yet: \(kind)"
        case .unableToDecodeImage: return "The analysis image could not be decoded"
        case .noSalientRegion: return "Vision did not return a salient region"
        case .noFaceDetected: return "Vision did not detect a face"
        case .faceIndexOutOfRange(let index): return "Vision did not detect face index \(index)"
        case .foregroundIndexOutOfRange(let index): return "Vision did not detect foreground instance index \(index)"
        case .personNotApplicable: return "Person segmentation was gated because no person signal was available"
        case .noPersonDetected: return "Vision did not produce a person mask"
        case .unsupportedQuality(let quality, let kind):
            return "Vision mask quality \(quality.rawValue) is not supported for \(kind) yet"
        case .requestFailed(let reason): return "Vision mask request failed: \(reason)"
        }
    }
}

/// The sole Vision boundary for this subsystem. VN requests, handlers, CIImages, and pixel
/// buffers are created and consumed inside the actor; callers receive only Lumo value types.
actor VisionSemanticMaskProvider: SemanticMaskProviding {
    let configuration: VisionConfiguration
    private let store: MaskStore

    init(configuration: VisionConfiguration = .default, store: MaskStore = MaskStore()) {
        self.configuration = configuration
        self.store = store
    }

    func mask(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        try Task.checkCancellation()
        var interval = LumoSignpostInterval(
            Self.signpostStage(for: kind),
            context: LumoTraceContext(sourceToken: image.source.traceToken, quality: quality.rawValue)
        )
        defer { interval.end() }
        switch kind {
        case .foreground:
            return try await foregroundUnionMask(image: image, quality: quality)
        case .subject:
            return try await subjectMask(image: image, quality: quality)
        case .face:
            return try await faceMask(index: 0, image: image, quality: quality)
        case .faceInstance(let index):
            return try await faceMask(index: index, image: image, quality: quality)
        case .foregroundInstance(let index):
            return try await foregroundMask(index: index, image: image, quality: quality)
        case .background:
            // Background composition belongs to PhotoAnalysisCoordinator, which owns the
            // foreground/background request de-duplication and shared cache identity.
            throw VisionSemanticMaskError.unsupported(kind)
        case .person:
            return try await personMask(image: image, quality: quality)
        case .unknown:
            // These cases are intentionally explicit: follow-up providers can fill one case at a
            // time without changing the shared protocol or leaking a VN type to consumers.
            throw VisionSemanticMaskError.unsupported(kind)
        }
    }

    private static func signpostStage(for kind: SemanticMaskKind) -> LumoWorkflowStage {
        switch kind {
        case .foreground: return .analysisForegroundMask
        case .subject: return .analysisSubjectMask
        case .face, .faceInstance: return .analysisFaceMask
        case .foregroundInstance: return .analysisForegroundMask
        case .background: return .analysisBackgroundMask
        case .person: return .analysisPersonMask
        case .unknown: return .analysisForegroundMask
        }
    }

    /// Returns the stable Foreground target used by durable local-mask recipes. The union is
    /// cached separately from the numbered instances so Background and Foreground can share one
    /// segmentation result, including the empty-result case.
    /// Internal for the size-mismatch regression test; the union path only misbehaves when the
    /// cached instance-mask dimensions differ from the analysis dimensions, which needs seeded
    /// store entries rather than a live Vision call.
    func foregroundUnionMask(image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        let key = cacheKey(for: .foreground, image: image, quality: quality)
        if let reference = await store.mask(for: key, quality: quality),
           let pixels = await store.pixels(for: reference) {
            return RegionMask(kind: .foreground, bounds: bounds(of: pixels), quality: quality,
                              reference: reference, confidence: 1, coverage: pixels.coverage)
        }

        let instances = try await foregroundMasks(image: image, quality: quality)
        // Seed from the instances themselves, never from `image.dimensions`: Vision reports
        // instance masks at its own output resolution (a square buffer regardless of source
        // aspect), so combining them with an analysis-sized seed threw incompatibleSizes for
        // every real image.
        guard let seed = instances.first, let seedPixels = await store.pixels(for: seed.reference) else {
            // Documented empty-result case: a zero-coverage union at the analysis dimensions so
            // Background can still be produced as its complement.
            let empty = try NormalizedMask(
                size: image.dimensions,
                values: Array(repeating: 0, count: image.dimensions.width * image.dimensions.height)
            )
            let reference = try await store.store(empty, for: key, quality: quality)
            return RegionMask(kind: .foreground, bounds: bounds(of: empty), quality: quality,
                              reference: reference, confidence: 1, coverage: empty.coverage)
        }
        var union = seedPixels
        for instance in instances.dropFirst() {
            guard let pixels = await store.pixels(for: instance.reference) else {
                throw RegionMaskError.missingPixels
            }
            union = try MaskOperations.union(union, MaskOperations.resized(pixels, to: union.size))
        }
        let reference = try await store.store(union, for: key, quality: quality)
        return RegionMask(kind: .foreground, bounds: bounds(of: union), quality: quality,
                          reference: reference, confidence: 1, coverage: union.coverage)
    }

    /// Returns every detected face as an independently cached `RegionMask`. `.face` is the
    /// source-compatible spelling for index zero; later detections use `.faceInstance(index)`.
    /// The mask is intentionally bounding-rectangle-derived in v1. Landmark parsing is deferred
    /// until a concrete `.render` consumer demonstrates that the additional complexity is needed.
    func faceMasks(image: AnalysisImage, quality: MaskQuality) async throws -> [RegionMask] {
        try Task.checkCancellation()
        let firstKey = cacheKey(for: .face, image: image, quality: quality)
        if let firstReference = await store.mask(for: firstKey, quality: quality),
           let firstPixels = await store.pixels(for: firstReference) {
            var cached = [makeFaceMask(index: 0, pixels: firstPixels, reference: firstReference,
                                       quality: quality)]
            var index = 1
            while let reference = await store.mask(
                for: cacheKey(for: .faceInstance(index), image: image, quality: quality),
                quality: quality
            ), let pixels = await store.pixels(for: reference) {
                cached.append(makeFaceMask(index: index, pixels: pixels, reference: reference,
                                            quality: quality))
                index += 1
            }
            return cached
        }

        let observations = try detectFaces(image: image)
        guard !observations.isEmpty else { throw VisionSemanticMaskError.noFaceDetected }

        var masks: [RegionMask] = []
        masks.reserveCapacity(observations.count)
        for (index, observation) in observations.enumerated() {
            try Task.checkCancellation()
            let bounds = NormalizedRect.fromVision(observation.boundingBox)
            let pixels = try rectangularMask(bounds: bounds, size: image.dimensions)
            let kind: SemanticMaskKind = index == 0 ? .face : .faceInstance(index)
            let key = cacheKey(for: kind, image: image, quality: quality)
            let reference = try await store.store(pixels, for: key, quality: quality)
            masks.append(makeFaceMask(index: index, pixels: pixels, reference: reference,
                                      quality: quality))
        }
        return masks
    }

    /// Returns each foreground instance as a real pixel mask. The ordinal is stable for the
    /// request result: `.foregroundInstance(0)` is the first instance, `.foregroundInstance(1)`
    /// the second, and so on. Vision's instance labels remain private to this adapter.
    func foregroundMasks(image: AnalysisImage, quality: MaskQuality) async throws -> [RegionMask] {
        try Task.checkCancellation()
        let firstKey = cacheKey(for: .foregroundInstance(0), image: image, quality: quality)
        if let firstReference = await store.mask(for: firstKey, quality: quality),
           let firstPixels = await store.pixels(for: firstReference) {
            var cached = [makeForegroundMask(index: 0, pixels: firstPixels, reference: firstReference,
                                             quality: quality)]
            var index = 1
            while let reference = await store.mask(
                for: cacheKey(for: .foregroundInstance(index), image: image, quality: quality),
                quality: quality
            ), let pixels = await store.pixels(for: reference) {
                cached.append(makeForegroundMask(index: index, pixels: pixels, reference: reference,
                                                 quality: quality))
                index += 1
            }
            return cached
        }

        guard #available(macOS 14.0, *) else {
            throw VisionSemanticMaskError.requestFailed("Foreground instance masks require macOS 14 or newer")
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        guard VNGenerateForegroundInstanceMaskRequest.supportedRevisions.contains(configuration.foregroundRevision) else {
            throw VisionSemanticMaskError.requestFailed(
                "Vision foreground revision \(configuration.foregroundRevision) is unavailable"
            )
        }
        let handler = try makeRequestHandler(for: image)
        do {
            try handler.perform([request])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VisionSemanticMaskError.requestFailed(error.localizedDescription)
        }
        try Task.checkCancellation()

        guard let observation = request.results?.first else { return [] }
        let instanceIDs = observation.allInstances
        guard !instanceIDs.isEmpty else { return [] }

        var masks: [RegionMask] = []
        masks.reserveCapacity(instanceIDs.count)
        for (index, instanceID) in instanceIDs.enumerated() {
            try Task.checkCancellation()
            let buffer: CVPixelBuffer
            do {
                buffer = try observation.generateMask(forInstances: IndexSet(integer: instanceID))
            } catch {
                throw VisionSemanticMaskError.requestFailed(error.localizedDescription)
            }
            let pixels = try normalizedMask(from: buffer)
            let key = cacheKey(for: .foregroundInstance(index), image: image, quality: quality)
            let reference = try await store.store(pixels, for: key, quality: quality)
            masks.append(makeForegroundMask(index: index, pixels: pixels, reference: reference,
                                             quality: quality))
        }
        return masks
    }

    /// Smoke-test seam for the adapter boundary. The handler itself never leaves the actor.
    func validateRequestHandler(for image: AnalysisImage) throws {
        _ = try makeRequestHandler(for: image)
    }

    private func subjectMask(image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        let key = cacheKey(for: .subject, image: image, quality: quality)
        if let reference = await store.mask(for: key, quality: quality),
           let pixels = await store.pixels(for: reference) {
            return RegionMask(kind: .subject, bounds: bounds(of: pixels), quality: quality,
                              reference: reference, confidence: 1, coverage: pixels.coverage)
        }

        try Task.checkCancellation()
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = try makeRequestHandler(for: image)
        do {
            try handler.perform([request])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VisionSemanticMaskError.requestFailed(error.localizedDescription)
        }
        try Task.checkCancellation()

        guard let observation = request.results?.first,
              let salientObject = observation.salientObjects?.first else {
            throw VisionSemanticMaskError.noSalientRegion
        }

        let bounds = NormalizedRect.fromVision(salientObject.boundingBox)
        // The salient-object box is the stable semantic result. It is rasterized at the requested
        // mask resolution here; a later refinement ticket can use the observation's heat map for
        // a higher-fidelity render-quality matte without changing this provider boundary.
        let pixels = try rectangularMask(bounds: bounds, size: image.dimensions)
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(kind: .subject, bounds: bounds, quality: quality, reference: reference,
                          confidence: 1, coverage: pixels.coverage)
    }

    private func faceMask(index: Int, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        guard index >= 0 else { throw VisionSemanticMaskError.faceIndexOutOfRange(index) }
        let masks = try await faceMasks(image: image, quality: quality)
        guard index < masks.count else { throw VisionSemanticMaskError.faceIndexOutOfRange(index) }
        return masks[index]
    }

    private func foregroundMask(index: Int, image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        guard index >= 0 else { throw VisionSemanticMaskError.foregroundIndexOutOfRange(index) }
        let masks = try await foregroundMasks(image: image, quality: quality)
        guard index < masks.count else { throw VisionSemanticMaskError.foregroundIndexOutOfRange(index) }
        return masks[index]
    }

    private func personMask(image: AnalysisImage, quality: MaskQuality) async throws -> RegionMask {
        guard quality != .render else {
            throw VisionSemanticMaskError.unsupportedQuality(.render, .person)
        }
        // A cached person matte is valid regardless of the gating signals: the caller that
        // produced it already paid the gate. Checking the cache first keeps retries, photo
        // re-opens, and overlay resolution from failing with personNotApplicable just because
        // the face/foreground entries were evicted or have not landed yet.
        let key = cacheKey(for: .person, image: image, quality: quality)
        if let reference = await store.mask(for: key, quality: quality),
           let pixels = await store.pixels(for: reference) {
            return RegionMask(kind: .person, bounds: bounds(of: pixels), quality: quality,
                              reference: reference, confidence: 1, coverage: pixels.coverage)
        }

        // Gating is deliberately cache-only. The coordinator/provider that requests person
        // segmentation must have already requested face or foreground analysis; this prevents a
        // landscape from paying for a full person matte merely because a caller asked for `.person`.
        let hasFaceSignal = await store.mask(
            for: cacheKey(for: .face, image: image, quality: quality), quality: quality
        ) != nil
        let hasForegroundSignal = await store.mask(
            for: cacheKey(for: .foregroundInstance(0), image: image, quality: quality), quality: quality
        ) != nil
        guard hasFaceSignal || hasForegroundSignal else {
            throw VisionSemanticMaskError.personNotApplicable
        }

        guard #available(macOS 12.0, *) else {
            throw VisionSemanticMaskError.requestFailed("Person segmentation requires macOS 12 or newer")
        }
        let request = VNGeneratePersonSegmentationRequest()
        guard VNGeneratePersonSegmentationRequest.supportedRevisions.contains(configuration.personRevision) else {
            throw VisionSemanticMaskError.requestFailed(
                "Vision person revision \(configuration.personRevision) is unavailable"
            )
        }
        request.revision = configuration.personRevision
        request.qualityLevel = quality == .analysis ? .fast : .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent32Float
        let handler = try makeRequestHandler(for: image)
        do {
            try handler.perform([request])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VisionSemanticMaskError.requestFailed(error.localizedDescription)
        }
        try Task.checkCancellation()

        guard let observation = request.results?.first else {
            throw VisionSemanticMaskError.noPersonDetected
        }
        let pixels: NormalizedMask
        do {
            pixels = try normalizedMask(from: observation.pixelBuffer)
        } catch let error as VisionSemanticMaskError {
            throw error
        } catch {
            throw VisionSemanticMaskError.requestFailed(error.localizedDescription)
        }
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(kind: .person, bounds: bounds(of: pixels), quality: quality,
                          reference: reference, confidence: 1, coverage: pixels.coverage)
    }

    private func detectFaces(image: AnalysisImage) throws -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        guard VNDetectFaceRectanglesRequest.supportedRevisions.contains(configuration.faceRevision) else {
            throw VisionSemanticMaskError.requestFailed(
                "Vision face revision \(configuration.faceRevision) is unavailable"
            )
        }
        request.revision = configuration.faceRevision
        let handler = try makeRequestHandler(for: image)
        do {
            try handler.perform([request])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VisionSemanticMaskError.requestFailed(error.localizedDescription)
        }
        return request.results ?? []
    }

    private func makeFaceMask(
        index: Int,
        pixels: NormalizedMask,
        reference: RegionMaskReference,
        quality: MaskQuality
    ) -> RegionMask {
        let coverage = pixels.coverage
        // A 1% image-area face is the minimum meaningful face for analysis. Smaller detections
        // remain available, but their confidence falls linearly so ensemble consumers can discount
        // distant/background faces without inventing a skin-tone recommendation here.
        let confidence = min(0.95, max(0.05, coverage / 0.01 * 0.95))
        return RegionMask(
            kind: index == 0 ? .face : .faceInstance(index),
            bounds: bounds(of: pixels), quality: quality, reference: reference,
            confidence: confidence, coverage: coverage
        )
    }

    private func makeForegroundMask(
        index: Int,
        pixels: NormalizedMask,
        reference: RegionMaskReference,
        quality: MaskQuality
    ) -> RegionMask {
        RegionMask(
            kind: .foregroundInstance(index), bounds: bounds(of: pixels), quality: quality,
            reference: reference, confidence: 1, coverage: pixels.coverage
        )
    }

    private func normalizedMask(from buffer: CVPixelBuffer) throws -> NormalizedMask {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else {
            throw VisionSemanticMaskError.requestFailed("Vision returned an empty mask")
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(buffer) else {
            throw VisionSemanticMaskError.requestFailed("Vision returned a mask without pixels")
        }

        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let rowStride = stride / MemoryLayout<Float>.stride
        let values: [Float]
        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_OneComponent32Float:
            values = (0..<height).flatMap { y in
                let row = address.assumingMemoryBound(to: Float.self).advanced(by: y * rowStride)
                return (0..<width).map { x in min(max(row[x], 0), 1) }
            }
        case kCVPixelFormatType_OneComponent8:
            let byteStride = stride
            values = (0..<height).flatMap { y in
                let row = address.assumingMemoryBound(to: UInt8.self).advanced(by: y * byteStride)
                return (0..<width).map { x in Float(row[x]) / 255 }
            }
        default:
            throw VisionSemanticMaskError.requestFailed(
                "Vision returned unsupported mask pixel format \(CVPixelBufferGetPixelFormatType(buffer))"
            )
        }
        return try NormalizedMask(size: PixelDimensions(width: width, height: height), values: values)
    }

    /// Constructing the handler is kept private so VNImageRequestHandler cannot cross isolation.
    private func makeRequestHandler(for image: AnalysisImage) throws -> VNImageRequestHandler {
        let ciImage: CIImage?
        switch image.source.backing {
        case .url(let url): ciImage = try? ImageDecoder.load(from: url)
        case .data(let data): ciImage = try? ImageDecoder.load(from: data, name: "analysis-image")
        }
        guard let ciImage else { throw VisionSemanticMaskError.unableToDecodeImage }
        return VNImageRequestHandler(ciImage: ciImage, options: [:])
    }

    /// Internal for the regression tests that seed the store under the provider's own keys.
    func cacheKey(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) -> MaskCacheKey {
        let assetID: PhotoAssetID
        let fingerprint: PhotoSourceFingerprint
        switch image.source.backing {
        case .url(let url):
            fingerprint = .file(at: url)
            assetID = .file(url, fingerprint: fingerprint)
        case .data(let data):
            fingerprint = .data(data)
            assetID = .data(data)
        }
        return MaskCacheKey(assetID: image.assetID ?? assetID, sourceFingerprint: fingerprint, kind: kind,
                            quality: quality, providerVersion: configuration.providerVersion)
    }

    private func rectangularMask(bounds: NormalizedRect, size: PixelDimensions) throws -> NormalizedMask {
        var values = Array(repeating: Float.zero, count: size.width * size.height)
        for y in 0..<size.height {
            let normalizedY = Double(y) / Double(max(1, size.height - 1))
            for x in 0..<size.width {
                let normalizedX = Double(x) / Double(max(1, size.width - 1))
                if normalizedX >= bounds.minX, normalizedX <= bounds.maxX,
                   normalizedY >= bounds.minY, normalizedY <= bounds.maxY {
                    values[y * size.width + x] = 1
                }
            }
        }
        return try NormalizedMask(size: size, values: values)
    }

    private func bounds(of mask: NormalizedMask) -> NormalizedRect {
        var minX = mask.size.width
        var minY = mask.size.height
        var maxX = -1
        var maxY = -1
        for y in 0..<mask.size.height {
            for x in 0..<mask.size.width where mask.values[y * mask.size.width + x] > 0 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return NormalizedRect(x: 0, y: 0, width: 0, height: 0) }
        return NormalizedRect(
            x: Double(minX) / Double(mask.size.width), y: Double(minY) / Double(mask.size.height),
            width: Double(maxX - minX + 1) / Double(mask.size.width),
            height: Double(maxY - minY + 1) / Double(mask.size.height)
        )
    }
}
