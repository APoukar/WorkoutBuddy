import SwiftData
import Testing
@testable import WorkoutBuddy

struct WorkoutBuddyTests {
    @Test func launchSeedingIsIdempotent() throws {
        let test = try TestContainer()
        WorkoutBuddyApp.seed(test.container)
        #expect(try test.context.fetchCount(FetchDescriptor<Exercise>()) == 43)
        WorkoutBuddyApp.seed(test.container)
        #expect(try test.context.fetchCount(FetchDescriptor<Exercise>()) == 43)
    }

    @Test func testHostIsDetected() {
        #expect(ModelContainerFactory.isRunningTests)
    }
}
