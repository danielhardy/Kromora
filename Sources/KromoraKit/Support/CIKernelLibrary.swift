import CoreImage
import Foundation

/// Loads the precompiled Core Image kernels behind the render pipeline.
///
/// The kernel functions live in `Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal` and are
/// compiled ahead of time by `scripts/build-metal-libraries.sh` into
/// `KromoraCIKernels.ci.metallib` (SwiftPM has no Metal build rule, so the library is a checked-in
/// build input). Loading by function name from library data uses no deprecated CIKernel Language
/// API and performs no runtime source compilation; the same library loads on Metal and software
/// CIContexts, preserving the CPU compatibility seam.
///
/// A missing or unloadable library yields `nil` kernels here, and every call site already renders
/// without its effect in that case. That must never happen silently in CI: MetalKernelParityTests
/// fail when the library is missing, unloadable, lacks an expected function, or is stale relative
/// to the bundled sources.
enum CIKernelLibrary {
    /// Every kernel function the render code loads. The parity tests assert this set is present
    /// in the bundled library; add the function name here when a new kernel lands.
    static let expectedKernelNames: [String] = [
        "effectsMidtoneMask",
        "effectsVignette",
        "effectsGrain",
        "hslMixer",
        "colorGrading",
        "localAnalyticMask",
        "localInvertMask",
        "localCombineMask",
        "applyToneCurve",
    ]

    private static let libraryData: Data? = KromoraKitResourceBundle.data(
        forResource: "KromoraCIKernels.ci", withExtension: "metallib")

    /// True when the bundled library loaded. Exposed for diagnostics; tests assert this.
    static var isAvailable: Bool { libraryData != nil }

    static func colorKernel(named name: String) -> CIColorKernel? {
        guard let libraryData else { return nil }
        return try? CIColorKernel(functionName: name, fromMetalLibraryData: libraryData)
    }

    static func kernel(named name: String) -> CIKernel? {
        guard let libraryData else { return nil }
        return try? CIKernel(functionName: name, fromMetalLibraryData: libraryData)
    }

    /// The function names actually present in the bundled library, for validation tests.
    static func bundledKernelNames() -> [String]? {
        guard let libraryData else { return nil }
        return CIKernel.kernelNames(fromMetalLibraryData: libraryData)
    }
}
