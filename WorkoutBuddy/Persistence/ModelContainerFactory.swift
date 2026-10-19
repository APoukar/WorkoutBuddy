import Foundation
import SwiftData

enum ModelContainerFactory {
    /// True when the app process is hosting unit tests.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    /// Builds the V1 container. No migration plan until V2.
    /// In the simulator only, a store that fails to load is deleted and loading is retried once.
    /// On a device (any build) a load failure stops the app with a clear message.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        if inMemory {
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            #if targetEnvironment(simulator)
            print("ModelContainer failed to load (\(error)). Resetting the store and retrying once.")
            deleteStoreFiles(at: configuration.url)
            return try ModelContainer(for: schema, configurations: [configuration])
            #else
            fatalError("WorkoutBuddy could not open its data store and will not reset it on a device, to protect your history: \(error)")
            #endif
        }
    }

    #if targetEnvironment(simulator)
    private static func deleteStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            try? fileManager.removeItem(at: file)
        }
    }
    #endif
}
