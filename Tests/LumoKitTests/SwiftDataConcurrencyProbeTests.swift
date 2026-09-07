import Foundation
import SwiftData
import XCTest

/// Throwaway model for LUMO-245. Keep this separate from the production schema: the test is a
/// compile-time gate for SwiftData's concurrency boundary, not part of Lumo's persistence model.
@Model
final class LUMO245SwiftDataProbeRecord {
    var value: Int

    init(value: Int) {
        self.value = value
    }
}

/// This deliberately mirrors the smallest useful `@ModelActor` store. The only value returned
/// from the actor is an `Int`; its `ModelContext` never appears in the actor's public API.
@ModelActor
actor LUMO245SwiftDataProbeStore {
    // `@ModelActor` synthesizes the ModelContainer initializer and the actor-confined
    // DefaultSerialModelExecutor/ModelContext storage.
    func insertAndCount(value: Int) throws -> Int {
        modelContext.insert(LUMO245SwiftDataProbeRecord(value: value))
        try modelContext.save()
        return try modelContext.fetch(FetchDescriptor<LUMO245SwiftDataProbeRecord>()).count
    }
}

@MainActor
final class SwiftDataConcurrencyProbeTests: XCTestCase {
    func testModelAndModelActorAreSwift6ConcurrencySafe() async throws {
        let schema = Schema([LUMO245SwiftDataProbeRecord.self])
        let configuration = ModelConfiguration(
            "LUMO245SwiftDataProbe",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        // The detached closure is @Sendable, so capturing the container here proves that the
        // SDK's ModelContainer can cross a concurrency boundary in Swift 6 mode. The actor's
        // result is Sendable, while its non-Sendable ModelContext remains actor-confined.
        let count = try await Task.detached { @Sendable in
            let store = LUMO245SwiftDataProbeStore(modelContainer: container)
            return try await store.insertAndCount(value: 245)
        }.value

        XCTAssertEqual(count, 1)
    }
}
