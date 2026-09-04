import CoreImage
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
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let kind): return "Vision mask kind is not supported yet: \(kind)"
        case .unableToDecodeImage: return "The analysis image could not be decoded"
        case .noSalientRegion: return "Vision did not return a salient region"
        case .noFaceDetected: return "Vision did not detect a face"
        case .faceIndexOutOfRange(let index): return "Vision did not detect face index \(index)"
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
        switch kind {
        case .subject:
            return try await subjectMask(image: image, quality: quality)
        case .face:
            return try await faceMask(index: 0, image: image, quality: quality)
        case .faceInstance(let index):
            return try await faceMask(index: index, image: image, quality: quality)
        case .background, .person, .foregroundInstance, .unknown:
            // These cases are intentionally explicit: follow-up providers can fill one case at a
            // time without changing the shared protocol or leaking a VN type to consumers.
            throw VisionSemanticMaskError.unsupported(kind)
        }
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

    private func cacheKey(for kind: SemanticMaskKind, image: AnalysisImage, quality: MaskQuality) -> MaskCacheKey {
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
        return MaskCacheKey(assetID: assetID, sourceFingerprint: fingerprint, kind: kind,
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
