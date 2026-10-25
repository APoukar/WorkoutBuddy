import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

struct UITestingLaunchTests {
    private typealias Argument = UITestingContract.Argument

    @Test func noFlagIsNotUITesting() {
        #expect(UITestingLaunch.parse([]) == nil)
        #expect(UITestingLaunch.parse(["-AppleLanguages", "(en)", Argument.scenario, "empty"]) == nil)
    }

    @Test func flagWithoutYesIsNotUITesting() {
        #expect(UITestingLaunch.parse([Argument.uiTesting]) == nil)
        #expect(UITestingLaunch.parse([Argument.uiTesting, "NO"]) == nil)
        #expect(UITestingLaunch.parse([Argument.uiTesting, "yes"]) == nil)
        #expect(UITestingLaunch.parse([Argument.uiTesting, Argument.scenario, "empty"]) == nil)
    }

    @Test func defaults() {
        #expect(UITestingLaunch.parse([Argument.uiTesting, "YES"]) == UITestingLaunch(scenario: .empty, store: .memory, keepData: false))
    }

    @Test func eachOption() {
        let disk = UITestingLaunch.parse([Argument.uiTesting, "YES", Argument.store, "disk"])
        #expect(disk?.store == .disk)
        #expect(disk?.keepData == false)
        let keep = UITestingLaunch.parse([Argument.uiTesting, "YES", Argument.keepData, "YES"])
        #expect(keep?.keepData == true)
        #expect(keep?.store == .memory)
        let scenario = UITestingLaunch.parse([Argument.uiTesting, "YES", Argument.scenario, "empty"])
        #expect(scenario?.scenario == .empty)
    }

    @Test func missingOrOtherKeepDataValueIsOff() {
        #expect(UITestingLaunch.parse([Argument.uiTesting, "YES", Argument.keepData])?.keepData == false)
        #expect(UITestingLaunch.parse([Argument.uiTesting, "YES", Argument.keepData, "NO"])?.keepData == false)
        #expect(UITestingLaunch.parse([Argument.uiTesting, "YES", Argument.keepData, "true"])?.keepData == false)
    }

    @Test func missingValuesFallBackToDefaults() {
        let launch = UITestingLaunch.parse([Argument.uiTesting, "YES", Argument.store])
        #expect(launch == UITestingLaunch())
    }

    @Test func optionsInAnyOrderAfterRegionPairs() {
        let first = UITestingLaunch.parse(
            ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", Argument.keepData, "YES", Argument.store, "disk", Argument.uiTesting, "YES"])
        let second = UITestingLaunch.parse(
            ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", Argument.uiTesting, "YES", Argument.store, "disk", Argument.keepData, "YES"])
        #expect(first == second)
        #expect(first == UITestingLaunch(scenario: .empty, store: .disk, keepData: true))
    }

    @Test func unknownScenarioIsRejected() {
        #expect(UITestingLaunch.Scenario(rawValue: "Templates") == nil)
        #expect(UITestingLaunch.Scenario(rawValue: "nonsense") == nil)
        #expect(UITestingLaunch.Scenario(rawValue: UITestingContract.Scenario.empty) == .empty)
        #expect(UITestingLaunch.Scenario(rawValue: UITestingContract.Scenario.templates) == .templates)
        #expect(UITestingLaunch.Scenario(rawValue: UITestingContract.Scenario.inProgress) == .inProgress)
        #expect(UITestingLaunch.Scenario(rawValue: UITestingContract.Scenario.nothingDone) == .nothingDone)
        #expect(UITestingLaunch.Scenario(rawValue: UITestingContract.Scenario.onSummary) == .onSummary)
    }

    @Test func contractNamesMatchTheApp() {
        #expect(UITestingContract.Store.memory == UITestingLaunch.Store.memory.rawValue)
        #expect(UITestingContract.Store.disk == UITestingLaunch.Store.disk.rawValue)
    }

    @Test func settingsStoreIsStandardOutsideUITesting() {
        #expect(UITestingLaunch.current == nil)
        #expect(AppSettings.store === UserDefaults.standard)
    }

    @Test func diskStoreIsNotTheRealStore() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let realURL = ModelConfiguration(schema: schema).url
        #expect(ModelContainerFactory.uiTestingStoreURL != realURL)
        #expect(ModelContainerFactory.uiTestingStoreURL.lastPathComponent == "UITesting.store")
        #expect(ModelContainerFactory.uiTestingStoreURL.deletingLastPathComponent() == FileManager.default.temporaryDirectory)
    }

    @Test func diskStoreKeepsDataOnlyWhenAsked() throws {
        func exerciseCount(keepData: Bool, seed: Bool) throws -> Int {
            let container = try ModelContainerFactory.makeUITestingDiskStore(keepData: keepData)
            if seed { try ExerciseSeed.seedIfNeeded(in: container.mainContext) }
            return try container.mainContext.fetchCount(FetchDescriptor<Exercise>())
        }
        // Uses the UI tests' own UITesting.store file on purpose: it is never the real store, and is wiped here.
        defer { ModelContainerFactory.deleteStoreFiles(at: ModelContainerFactory.uiTestingStoreURL) }
        #expect(try exerciseCount(keepData: false, seed: false) == 0)
        let seeded = try exerciseCount(keepData: false, seed: true)
        #expect(seeded > 0)
        #expect(try exerciseCount(keepData: true, seed: false) == seeded)
        #expect(try exerciseCount(keepData: false, seed: false) == 0)
    }

    @Test func uiTestingSettingsStoreTurnsSoundAndHapticsOff() {
        let name = "UITestingLaunchTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        let store = AppSettings.uiTestingStore(suiteName: name, keepData: false)
        let values = AppSettings.current(in: store)
        #expect(!values.soundEnabled)
        #expect(!values.hapticsEnabled)
    }

    @Test func uiTestingSettingsStoreClearsUnlessKeepData() {
        let name = "UITestingLaunchTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        let first = AppSettings.uiTestingStore(suiteName: name, keepData: false)
        first.set(42, forKey: AppSettings.Key.defaultReps)

        let kept = AppSettings.uiTestingStore(suiteName: name, keepData: true)
        #expect(AppSettings.current(in: kept).reps == 42)

        let cleared = AppSettings.uiTestingStore(suiteName: name, keepData: false)
        #expect(AppSettings.current(in: cleared).reps == AppSettings.Default.reps)
    }
}
