import XCTest
@testable import KromoraKit

@MainActor
final class LookSelectionCoordinatorTests: TempDirectoryTestCase {

    private func makeLook(_ name: String, source: LUTSource = .user) -> CubeLUT {
        CubeLUT(
            cube: Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: 8), size: 2, name: name,
            category: "Test", sourceURL: tempDirectory.appendingPathComponent("\(name).cube"),
            source: source)
    }

    private func makeCoordinator(
        looks: [CubeLUT] = []
    ) -> (LookSelectionCoordinator, LUTLibrary) {
        let library = makeLUTLibrary()
        library.allLUTs = looks
        return (LookSelectionCoordinator(library: library), library)
    }

    func testResolvePrefersLibraryThenDerivedRegistry() {
        let scanned = makeLook("Scanned")
        let (coordinator, _) = makeCoordinator(looks: [scanned])
        XCTAssertEqual(coordinator.resolve(scanned.lutID), scanned)
        XCTAssertNil(coordinator.resolve(nil))

        let derived = makeLook("Derived", source: .derived)
        coordinator.register(derived)
        XCTAssertEqual(coordinator.registeredCount, 1)
        XCTAssertEqual(coordinator.resolve(derived.lutID), derived)
    }

    func testSelectionOutcomes() {
        let look = makeLook("A")
        let (coordinator, library) = makeCoordinator(looks: [look])
        XCTAssertEqual(coordinator.selection(for: nil), .clear)
        XCTAssertEqual(coordinator.selection(for: look.lutID), .select(look))

        let missing = makeLook("Missing").lutID
        XCTAssertEqual(coordinator.selection(for: missing), .unresolved)

        library.isScanning = true
        guard case .loading = coordinator.selection(for: missing) else {
            return XCTFail("expected loading while scanning")
        }
    }

    func testMissingReferenceIsReportedOncePerTransition() {
        let (coordinator, library) = makeCoordinator()
        let missing = makeLook("Gone").lutID

        XCTAssertEqual(coordinator.refreshStatus(for: nil), .cleared)
        library.isScanning = true
        XCTAssertEqual(coordinator.refreshStatus(for: missing), .unchanged)
        library.isScanning = false

        guard case .missing(let message) = coordinator.refreshStatus(for: missing) else {
            return XCTFail("expected missing report")
        }
        XCTAssertTrue(message.contains("Gone.cube"))
        XCTAssertEqual(coordinator.refreshStatus(for: missing), .unchanged)

        coordinator.resetReportedStatus()
        guard case .missing = coordinator.refreshStatus(for: missing) else {
            return XCTFail("reset should allow a fresh report")
        }
    }

    func testResolvedReferenceClearsStatus() {
        let look = makeLook("Back")
        let (coordinator, library) = makeCoordinator()
        _ = coordinator.refreshStatus(for: look.lutID)
        library.allLUTs = [look]
        XCTAssertEqual(coordinator.refreshStatus(for: look.lutID), .cleared)
    }

    func testNavigationIncludesNoneSlot() {
        let a = makeLook("A"), b = makeLook("B")
        let (coordinator, _) = makeCoordinator(looks: [a, b])

        XCTAssertEqual(coordinator.navigate(.next, from: nil, currentID: nil), .select(a))
        XCTAssertEqual(coordinator.navigate(.next, from: a, currentID: a.lutID), .select(b))
        XCTAssertEqual(coordinator.navigate(.previous, from: b, currentID: b.lutID), .select(a))
        XCTAssertEqual(coordinator.navigate(.previous, from: a, currentID: a.lutID), .clear)
        XCTAssertEqual(coordinator.navigate(.previous, from: nil, currentID: nil), .none)
    }
}
