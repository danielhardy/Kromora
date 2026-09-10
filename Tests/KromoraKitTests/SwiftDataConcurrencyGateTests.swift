import Foundation
import SwiftData
import XCTest

/// Keep this separate from the production schema: the test is a compile-time gate for
/// SwiftData's concurrency boundary, not part of Kromora's persistence model.
@Model
final class SwiftDataConcurrencyGateRecord {
    var value: Int

    init(value: Int) {
        self.value = value
    }
}

/// This deliberately mirrors the smallest useful `@ModelActor` store. The only value returned
/// from the actor is an `Int`; its `ModelContext` never appears in the actor's public API.
@ModelActor
actor SwiftDataConcurrencyGateStore {
    // `@ModelActor` synthesizes the ModelContainer initializer and the actor-confined
    // DefaultSerialModelExecutor/ModelContext storage.
    func insertAndCount(value: Int) throws -> Int {
        modelContext.insert(SwiftDataConcurrencyGateRecord(value: value))
        try modelContext.save()
        return try modelContext.fetch(FetchDescriptor<SwiftDataConcurrencyGateRecord>()).count
    }
}

@MainActor
final class SwiftDataConcurrencyGateTests: XCTestCase {
    func testModelAndModelActorAreSwift6ConcurrencySafe() async throws {
        let schema = Schema([SwiftDataConcurrencyGateRecord.self])
        let configuration = ModelConfiguration(
            "SwiftDataConcurrencyGate",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        // The detached closure is @Sendable, so capturing the container here proves that the
        // SDK's ModelContainer can cross a concurrency boundary in Swift 6 mode. The actor's
        // result is Sendable, while its non-Sendable ModelContext remains actor-confined.
        let count = try await Task.detached { @Sendable in
            let store = SwiftDataConcurrencyGateStore(modelContainer: container)
            return try await store.insertAndCount(value: 245)
        }.value

        XCTAssertEqual(count, 1)
    }
}
