import Foundation

extension EditDocument {
    /// Fixed per-document overhead charged on top of the variable-length payload.
    static let retentionShellBytes = 4 * 1024

    /// Deterministic estimate of the value payload a retained document holds (KRMA-1059/1060).
    ///
    /// Counts `count * stride` for every variable-length collection and the UTF-8 bytes of retained
    /// strings. It takes no copy-on-write discount and is not an allocation or RSS bound.
    var estimatedRetentionBytes: Int {
        var total = Self.retentionShellBytes
        total += adjustments.count * MemoryLayout<AdjustmentNode>.stride
        total += (lut.lutID?.raw.utf8.count ?? 0)
        total += localAdjustments.count * MemoryLayout<LocalAdjustmentLayer>.stride
        for layer in localAdjustments {
            total += layer.name.utf8.count
            total += layer.autoProvenance?.generationID.utf8.count ?? 0
            total += layer.components.count * MemoryLayout<MaskComponent>.stride
            for component in layer.components {
                total += component.name.utf8.count
                switch component.source {
                case .brush(let brush):
                    total += brush.strokes.count * MemoryLayout<BrushStroke>.stride
                    for stroke in brush.strokes {
                        total += stroke.samples.count * MemoryLayout<BrushSample>.stride
                    }
                case .color(let color):
                    total += color.samples.count * MemoryLayout<ColorRangeSample>.stride
                default:
                    break
                }
            }
        }
        total += retouch.spots.count * MemoryLayout<RetouchSpot>.stride
        for spot in retouch.spots {
            total += spot.region.samples.count * MemoryLayout<BrushSample>.stride
        }
        total += retouch.eyes.count * MemoryLayout<EyeCorrection>.stride
        if let fingerprint = lastAutoRunFingerprint {
            total += fingerprint.sourceFingerprint.utf8.count
            total += fingerprint.documentHash.utf8.count
            total += fingerprint.renderIdentity.utf8.count
        }
        return total
    }
}
