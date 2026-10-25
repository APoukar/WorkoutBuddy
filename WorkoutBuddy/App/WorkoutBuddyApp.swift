import SwiftData
import SwiftUI

@main
struct WorkoutBuddyApp: App {
    private let container: ModelContainer

    init() {
        do {
            if let launch = UITestingLaunch.current {
                // UI tests never touch the real store either.
                switch launch.store {
                case .memory: container = try ModelContainerFactory.make(inMemory: true)
                case .disk: container = try ModelContainerFactory.makeUITestingDiskStore(keepData: launch.keepData)
                }
            } else {
                // Unit tests never touch the real store.
                container = try ModelContainerFactory.make(inMemory: ModelContainerFactory.isRunningTests)
            }
        } catch {
            fatalError("WorkoutBuddy could not create its data store: \(error)")
        }
        Self.seed(container)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .defaultAppStorage(AppSettings.store)
        }
        .modelContainer(container)
    }

    /// A failed seed is not fatal: the store opened fine, so history is safe. The failed insert is
    /// rolled back and the seed runs again on the next launch, because it only runs on an empty store.
    static func seed(_ container: ModelContainer) {
        do {
            try ExerciseSeed.seedIfNeeded(in: container.mainContext)
        } catch {
            container.mainContext.rollback()
            ErrorLogging.log(error, action: "Exercise seed (will retry next launch)", category: "launch")
        }
    }
}
