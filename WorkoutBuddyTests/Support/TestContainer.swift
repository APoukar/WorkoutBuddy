import SwiftData
@testable import WorkoutBuddy

/// Keeps the `ModelContainer` alive for the whole test. A bare `mainContext` crashes once its container is released.
struct TestContainer {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
    }
}
