import CoreImage
import Foundation

/// Why a precompiled kernel cannot be used. The underlying load error is preserved so a damaged
/// bundle is diagnosable from the message the user sees.
enum CIKernelLibraryError: LocalizedError, Sendable {
    case libraryUnavailable(underlying: any Error)
    case kernelUnavailable(name: String, underlying: (any Error)?)

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let underlying):
            return "Kromora's image-processing library could not be loaded "
                + "(\(underlying.localizedDescription)). Reinstall Kromora to restore it."
        case .kernelUnavailable(let name, let underlying):
            let reason = underlying.map { " (\($0.localizedDescription))" } ?? ""
            return "The image-processing step \"\(name)\" could not be loaded\(reason). "
                + "Reinstall Kromora to restore it."
        }
    }
}

/// The outcome of validating the kernels a render may need, computed once per process for the
/// shipping bundle (`.bundled`) and injectable in tests. Rendering consults it before building a
/// graph for a document, so a saved edit whose kernel cannot load fails the render or export
/// instead of being silently left out.
struct CIKernelLibraryStatus: Sendable {
    /// Failure per kernel name; a name that is absent loaded successfully.
    let failures: [String: CIKernelLibraryError]

    init(failures: [String: CIKernelLibraryError] = [:]) {
        self.failures = failures
    }

    static let bundled = CIKernelLibrary.validateBundledKernels()

    /// Throws the first failure (by name, for a stable message) among the kernels `names` needs.
    func require(_ names: some Collection<String>) throws {
        guard !failures.isEmpty else { return }
        for name in names.sorted() {
            if let failure = failures[name] { throw failure }
        }
    }
}

/// Loads the precompiled Core Image kernels behind the render pipeline.
///
/// The kernel functions live in `Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal` and are
/// compiled ahead of time by `scripts/build-metal-libraries.sh` into
/// `KromoraCIKernels.ci.metallib` (SwiftPM has no Metal build rule, so the library is a checked-in
/// build input). Loading by function name from library data uses no deprecated CIKernel Language
/// API and performs no runtime source compilation; the same library loads on Metal and software
/// CIContexts, preserving the CPU compatibility seam.
///
/// A missing or unloadable library yields `nil` kernels from the optional accessors, which the
/// graph builders treat as "stage not applied". That is only acceptable because
/// `RenderEngine` validates the kernels a document needs (``CIKernelLibraryStatus``,
/// ``RenderKernelRequirements``) before building any graph and fails the render or export when one
/// is unavailable. Every kernel is required for the saved edit that uses it: none is a decorative
/// presentation effect. MetalKernelParityTests additionally fail in CI when the library is
/// missing, unloadable, lacks an expected function, or is stale relative to the bundled sources.
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
        "retouchApplyCorrection",
        "retouchMembraneApply",
        "retouchPull",
        "retouchPush",
        "retouchSampleField",
    ]

    /// The subset of ``expectedKernelNames`` that are `CIColorKernel`s; the rest are `CIKernel`s.
    static let colorKernelNames: Set<String> = [
        "effectsMidtoneMask", "effectsVignette", "effectsGrain", "hslMixer", "colorGrading",
    ]

    private static let libraryData: Result<Data, CIKernelLibraryError> = {
        guard let url = KromoraKitResourceBundle.url(
            forResource: "KromoraCIKernels.ci", withExtension: "metallib")
        else {
            return .failure(.libraryUnavailable(underlying: CocoaError(
                .fileNoSuchFile, userInfo: [
                    NSLocalizedDescriptionKey: "KromoraCIKernels.ci.metallib is not in the app bundle",
                ])))
        }
        do {
            return .success(try Data(contentsOf: url))
        } catch {
            return .failure(.libraryUnavailable(underlying: error))
        }
    }()

    /// True when the bundled library loaded. Exposed for diagnostics; tests assert this.
    static var isAvailable: Bool { (try? libraryData.get()) != nil }

    static func loadColorKernel(named name: String) throws -> CIColorKernel {
        let data = try libraryData.get()
        do {
            return try CIColorKernel(functionName: name, fromMetalLibraryData: data)
        } catch {
            throw CIKernelLibraryError.kernelUnavailable(name: name, underlying: error)
        }
    }

    static func loadKernel(named name: String) throws -> CIKernel {
        let data = try libraryData.get()
        do {
            return try CIKernel(functionName: name, fromMetalLibraryData: data)
        } catch {
            throw CIKernelLibraryError.kernelUnavailable(name: name, underlying: error)
        }
    }

    static func colorKernel(named name: String) -> CIColorKernel? {
        try? loadColorKernel(named: name)
    }

    static func kernel(named name: String) -> CIKernel? {
        try? loadKernel(named: name)
    }

    /// Instantiates every expected kernel in its declared class, recording each failure.
    static func validateBundledKernels() -> CIKernelLibraryStatus {
        var failures: [String: CIKernelLibraryError] = [:]
        for name in expectedKernelNames {
            do {
                if colorKernelNames.contains(name) {
                    _ = try loadColorKernel(named: name)
                } else {
                    _ = try loadKernel(named: name)
                }
            } catch let error as CIKernelLibraryError {
                failures[name] = error
            } catch {
                failures[name] = .kernelUnavailable(name: name, underlying: error)
            }
        }
        return CIKernelLibraryStatus(failures: failures)
    }

    /// The function names actually present in the bundled library, for validation tests.
    static func bundledKernelNames() -> [String]? {
        guard let data = try? libraryData.get() else { return nil }
        return CIKernel.kernelNames(fromMetalLibraryData: data)
    }
}
