import Foundation

/// The origin of a raster that becomes visible on a presentation surface.
enum PresentationRasterSource: String, Sendable, Equatable {
    case stored
    case thumbnail
    case embedded
    case settled
    case refinement
}

/// A logical view that consumes presentation pixels. Grid and filmstrip cells share an
/// `ImageCollection.Item`, but remain separate surfaces in diagnostics because they have
/// independent visibility and layout budgets.
enum PresentationSurface: Hashable {
    case editCanvas(PhotoAssetID)
    case unidentifiedEditCanvas
    case gridCell(PhotoAssetID)
    case filmstripCell(PhotoAssetID)
    case collectionProjection

    var description: String {
        switch self {
        case .editCanvas(let assetID): "editCanvas(\(assetID))"
        case .unidentifiedEditCanvas: "editCanvas(unknown-asset)"
        case .gridCell(let assetID): "gridCell(\(assetID))"
        case .filmstripCell(let assetID): "filmstripCell(\(assetID))"
        case .collectionProjection: "collectionProjection"
        }
    }
}

@MainActor
final class PresentationChangeLedger {
    enum Kind: Equatable {
        case rasterAssignment(PresentationRasterSource)
        case geometryChange(from: String, to: String)
        case crossfade
        case collectionProjectionInvalidation
    }

    struct Change: Equatable {
        let ordinal: Int
        let surface: PresentationSurface
        let kind: Kind

        var diagnostic: String {
            let action: String
            switch kind {
            case .rasterAssignment(let source): action = "raster(\(source.rawValue))"
            case .geometryChange(let from, let to): action = "geometry(\(from) → \(to))"
            case .crossfade: action = "crossfade"
            case .collectionProjectionInvalidation: action = "projectionInvalidation"
            }
            return "#\(ordinal) \(surface.description): \(action)"
        }
    }

    private(set) var changes: [Change] = []

    func reset() { changes.removeAll(keepingCapacity: true) }

    func recordRasterAssignment(on surface: PresentationSurface, source: PresentationRasterSource) {
        append(.rasterAssignment(source), on: surface)
    }

    func recordGeometryChange(on surface: PresentationSurface, from: String, to: String) {
        append(.geometryChange(from: from, to: to), on: surface)
    }

    func recordCrossfade(on surface: PresentationSurface) {
        append(.crossfade, on: surface)
    }

    func recordCollectionProjectionInvalidation() {
        append(.collectionProjectionInvalidation, on: .collectionProjection)
    }

    func changes(on surface: PresentationSurface) -> [Change] {
        changes.filter { $0.surface == surface }
    }

    func diagnostic(for surface: PresentationSurface) -> String {
        let entries = changes(on: surface).map(\.diagnostic)
        return entries.isEmpty ? "\(surface.description): no changes" : entries.joined(separator: "\n")
    }

    private func append(_ kind: Kind, on surface: PresentationSurface) {
        changes.append(Change(ordinal: changes.count + 1, surface: surface, kind: kind))
    }
}
