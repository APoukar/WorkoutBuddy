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
            ErrorLogging.log(error, action: "Store load (resetting simulator store)", category: "launch")
            deleteStoreFiles(at: configuration.url)
            return try ModelContainer(for: schema, configurations: [configuration])
            #else
            fatalError("WorkoutBuddy could not open its data store and will not reset it on a device, to protect your history: \(error)")
            #endif
        }
    }

    /// The UI-testing disk store: its own file in the temporary directory, never the real `default.store`.
    static var uiTestingStoreURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "UITesting.store")
    }

    /// Builds the UI-testing disk store at `uiTestingStoreURL`. Its files are deleted first unless `keepData`.
    static func makeUITestingDiskStore(keepData: Bool) throws -> ModelContainer {
        let url = uiTestingStoreURL
        if !keepData { deleteStoreFiles(at: url) }
        let schema = Schema(versionedSchema: SchemaV1.self)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    }

    static func deleteStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            try? fileManager.removeItem(at: file)
        }
    }
}
