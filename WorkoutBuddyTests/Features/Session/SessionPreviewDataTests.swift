import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

/// The preview data is compiled in every configuration, so it is checked like any other code.
@MainActor
struct SessionPreviewDataTests {
    private func snapshot(_ state: SessionPreviewData.State) throws -> (SessionSnapshot, ModelContainer) {
        let preview = SessionPreviewData.make(state)
        let sessionID = preview.sessionID
        let session = try #require(
            try preview.container.mainContext.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first)
        return (SessionLibrary(context: preview.container.mainContext).snapshot(of: session), preview.container)
    }

    @Test func firstSetShowsTheFirstSet() throws {
        let (snapshot, _) = try snapshot(.firstSet)
        #expect(snapshot.entries.count == 2)
        #expect(snapshot.screen(now: .now) == .set(0))
    }

    @Test func restingShowsTheRestBeforeTheSecondSet() throws {
        let (snapshot, _) = try snapshot(.resting)
        guard case .rest(let next, let remaining) = snapshot.screen(now: .now) else {
            Issue.record("Expected the rest screen")
            return
        }
        #expect(next == 1)
        #expect((55...65).contains(remaining))
        #expect(snapshot.undoTargetIndex(now: .now) == 0)
    }

    @Test func pausedIsPausedDuringTheRest() throws {
        let (snapshot, _) = try snapshot(.paused)
        #expect(snapshot.isPaused)
        #expect(snapshot.restRemaining(now: .now) != nil)
    }

    @Test func finishedWaitsForSave() throws {
        let (snapshot, _) = try snapshot(.finished)
        #expect(snapshot.screen(now: .now) == .summary)
        #expect(snapshot.status == .inProgress)
        let stats = SessionStats(snapshot, now: .now)
        #expect(stats.canSave && !stats.endedEarly)
    }

    @Test func endedEarlyHasANotPerformedSet() throws {
        let (snapshot, _) = try snapshot(.endedEarly)
        #expect(snapshot.screen(now: .now) == .summary)
        let stats = SessionStats(snapshot, now: .now)
        #expect(stats.canSave && stats.endedEarly)
    }

    @Test func allSkippedCannotBeSaved() throws {
        let (snapshot, _) = try snapshot(.allSkipped)
        #expect(snapshot.screen(now: .now) == .summary)
        #expect(!SessionStats(snapshot, now: .now).canSave)
    }
}
