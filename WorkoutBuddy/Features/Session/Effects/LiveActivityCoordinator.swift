import Foundation

/// Makes the session's Live Activity match the session state. Like `RestNotificationCoordinator` it keeps
/// only the latest state and applies it in one running task at a time: a state that arrives while a
/// system call is in flight is applied after it, and the states in between are skipped.
@MainActor
final class LiveActivityCoordinator {
    private let controller: any LiveActivityControlling
    private let now: () -> Date
    private let log: (Error) -> Void

    private var latest: SessionEffectsState?
    private var task: Task<Void, Never>?
    /// Sessions this process has seen an activity for, found existing or requested. An activity the user
    /// swiped away stays away until the next launch. A failed request isn't recorded, so the next reconcile
    /// retries it.
    private var seenSessions: Set<UUID> = []

    /// `now` and `log` are injectable for tests. Failures are logged with the "session" category.
    init(
        controller: any LiveActivityControlling,
        now: @escaping () -> Date = { Date.now },
        log: @escaping (Error) -> Void = { ErrorLogging.log($0, action: "Live Activity", category: "session") }
    ) {
        self.controller = controller
        self.now = now
        self.log = log
    }

    func reconcile(_ state: SessionEffectsState) {
        latest = state
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// Returns when everything reported so far has been applied. For tests.
    func waitUntilIdle() async {
        await task?.value
    }

    private func run() async {
        while let next = latest {
            latest = nil
            await apply(next)
        }
        task = nil
    }

    private func apply(_ state: SessionEffectsState) async {
        let live = controller.liveActivities()
        guard case .active(let sessionID, _, _, _) = state,
            let content = LiveActivityContent.make(from: state, now: now())
        else {
            for activity in live { await controller.end(id: activity.id) }
            return
        }

        // Strays of other sessions (after a kill), and duplicates of this one.
        let mine = live.first { $0.sessionID == sessionID }
        for activity in live where activity.sessionID != sessionID || activity.id != mine?.id {
            await controller.end(id: activity.id)
        }

        if let mine {
            seenSessions.insert(sessionID)
            if mine.state != content.state || mine.staleDate != content.staleDate {
                await controller.update(id: mine.id, state: content.state, staleDate: content.staleDate)
            }
        } else if !seenSessions.contains(sessionID), controller.areActivitiesEnabled {
            do {
                try await controller.request(sessionID: sessionID, state: content.state, staleDate: content.staleDate)
                seenSessions.insert(sessionID)
            } catch LiveActivityError.notEnabled {
                // Expected when the user turned Live Activities off; not logged.
            } catch {
                log(error)
            }
        }
    }
}
