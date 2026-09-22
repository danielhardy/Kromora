import Foundation

/// One coherent boundary for lightweight runtime render instrumentation.
///
/// The app records counters here, while diagnostics consumers take one immutable snapshot.
/// Individual mutable counters are deliberately private so tests and scripts cannot couple
/// themselves to the storage layout.
struct RenderDiagnosticsSnapshot: Sendable, Equatable {
    let contentViewBodyEvaluations: Int
    let inspectorBodyEvaluations: Int
    let gridBodyEvaluations: Int
    let toolbarBodyEvaluations: Int
    let presentationCoreImageEvaluations: Int
}

struct RenderEngineDiagnosticsSnapshot: Sendable, Equatable {
    let trackedMaskSourceKeys: [String]
}

@MainActor
enum RenderDiagnostics {
    typealias Snapshot = RenderDiagnosticsSnapshot

    private static var contentViewBodyEvaluations = 0
    private static var inspectorBodyEvaluations = 0
    private static var gridBodyEvaluations = 0
    private static var toolbarBodyEvaluations = 0
    private static var presentationCoreImageEvaluations = 0

    static var snapshot: Snapshot {
        Snapshot(
            contentViewBodyEvaluations: contentViewBodyEvaluations,
            inspectorBodyEvaluations: inspectorBodyEvaluations,
            gridBodyEvaluations: gridBodyEvaluations,
            toolbarBodyEvaluations: toolbarBodyEvaluations,
            presentationCoreImageEvaluations: presentationCoreImageEvaluations
        )
    }

    static func reset() {
        contentViewBodyEvaluations = 0
        inspectorBodyEvaluations = 0
        gridBodyEvaluations = 0
        toolbarBodyEvaluations = 0
        presentationCoreImageEvaluations = 0
    }

    @discardableResult
    static func noteContentViewBody() -> Bool {
        contentViewBodyEvaluations &+= 1
        return true
    }

    @discardableResult
    static func noteInspectorBody() -> Bool {
        inspectorBodyEvaluations &+= 1
        return true
    }

    @discardableResult
    static func noteGridBody() -> Bool {
        gridBodyEvaluations &+= 1
        return true
    }

    @discardableResult
    static func noteToolbarBody() -> Bool {
        toolbarBodyEvaluations &+= 1
        return true
    }

    static func notePresentationCoreImageEvaluation() {
        presentationCoreImageEvaluations &+= 1
    }
}
