import SwiftData
import SwiftUI

struct RootTabView: View {
    /// Whether this process already ran the launch check. Process-wide, so the check runs once per launch:
    /// a session found running when the process starts was interrupted by a kill. Starts `false`; the
    /// full-screen session isn't presented before the check ran, so it can't flash up before the
    /// recovery alert.
    static var launchCheckRan = false

    /// In-progress sessions (running, or finished and waiting for Save), newest first. The first one is the
    /// one the full-screen session shows, as in `SessionLibrary.activeSession()`. Start, Save, Discard and
    /// recovery only change the store; the cover follows.
    @Query private var activeSessions: [WorkoutSession]
    @Environment(\.modelContext) private var context
    @State private var launchCheckDone = RootTabView.launchCheckRan
    /// The interrupted workout waiting for an answer. The cover stays away while it's set. The alert is
    /// driven by it, so any plain dismissal counts as Resume and it can't get stuck.
    @State private var recovery: PendingRecovery?
    @State private var error: Error?

    init() {
        let inProgress = SessionStatus.inProgress.rawValue
        _activeSessions = Query(
            filter: #Predicate<WorkoutSession> { $0.statusRaw == inProgress },
            sort: [SortDescriptor(\.startedAt, order: .reverse)])
    }

    private var library: SessionLibrary { SessionLibrary(context: context) }

    private var recoveryAlert: Binding<Bool> {
        Binding(
            get: { SessionPresentationRules.showsRecoveryAlert(recovery: recovery, hasError: error != nil) },
            set: { if !$0 { recovery = nil } })
    }

    /// The cover only gets the session's ID, never a model.
    private var cover: Binding<ActiveSessionCover?> {
        Binding(
            get: {
                SessionPresentationRules.coverSessionID(
                    launchCheckDone: launchCheckDone, recoveryPending: recovery != nil,
                    firstSessionID: activeSessions.first?.id
                ).map(ActiveSessionCover.init)
            },
            // Closing is driven by the store (Save, Discard), never by a swipe.
            set: { _ in })
    }

    var body: some View {
        TabView {
            Tab("Workouts", systemImage: "dumbbell") {
                WorkoutListView()
            }
            Tab("History", systemImage: "calendar") {
                placeholder("History", systemImage: "calendar")
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                placeholder("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .task { runLaunchCheck() }
        .fullScreenCover(item: cover) { cover in
            ActiveSessionView(sessionID: cover.id)
                .interactiveDismissDisabled()
        }
        .alert(SessionMessages.recoveryTitle, isPresented: recoveryAlert, presenting: recovery) { pending in
            Button(SessionMessages.recoveryResumeButton, role: .cancel) { recovery = nil }
            if pending.canSave {
                Button(SessionMessages.recoveryEndButton) { endWorkout(pending) }
            } else {
                Button(SessionMessages.recoveryDiscardButton, role: .destructive) { discard(pending) }
            }
        } message: { pending in
            Text(pending.message)
        }
        .errorAlert($error, message: SessionMessages.failureMessage(for:))
    }

    private func placeholder(_ title: LocalizedStringKey, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text("Coming soon."))
    }

    // MARK: Recovery

    /// Runs once per process. A running workout asks first; one waiting for Save reopens its summary
    /// through the cover. The state is set together with `launchCheckDone`, so the cover never shows first.
    private func runLaunchCheck() {
        guard !Self.launchCheckRan else {
            launchCheckDone = true
            return
        }
        Self.launchCheckRan = true
        defer { launchCheckDone = true }
        do {
            guard let session = try library.activeSession() else { return }
            let decision = LaunchRecovery.decide(library.snapshot(of: session))
            recovery = SessionPresentationRules.pendingRecovery(
                for: decision, sessionID: session.id, workoutName: session.workout?.name)
        } catch {
            ErrorLogging.log(error, action: "Launch recovery check", category: "session")
            self.error = error
        }
    }

    private func endWorkout(_ pending: PendingRecovery) {
        answer(pending, action: "End recovered workout") { try library.endForRecovery($0) }
    }

    private func discard(_ pending: PendingRecovery) {
        answer(pending, action: "Discard recovered workout") { try library.discard($0) }
    }

    /// Applies the answer to the session, then lets the cover follow the store. On a failure the workout
    /// stays in progress: the question stays pending (no cover), the error is shown, and the question comes
    /// back once the error is dismissed. (The alert's own dismissal may already have cleared `recovery`,
    /// so it's set again explicitly.)
    private func answer(_ pending: PendingRecovery, action: String, _ apply: (WorkoutSession) throws -> Void) {
        guard let session = activeSessions.first(where: { $0.id == pending.sessionID }) else {
            recovery = nil
            return
        }
        do {
            try apply(session)
            recovery = nil
        } catch {
            ErrorLogging.log(error, action: action, category: "session")
            recovery = pending
            self.error = error
        }
    }
}

/// The session the full-screen cover shows. Identifiable by the session's ID.
private struct ActiveSessionCover: Identifiable {
    let id: UUID
}

private struct RootPreview: View {
    let preview: SessionPreviewData.Preview

    /// `launchCheckRan`: true shows the workout straight away (as after Resume), false runs the launch check,
    /// which asks about a running workout.
    init(_ state: SessionPreviewData.State, launchCheckRan: Bool) {
        RootTabView.launchCheckRan = launchCheckRan
        preview = SessionPreviewData.make(state)
    }

    var body: some View {
        RootTabView()
            .modelContainer(preview.container)
    }
}

#Preview {
    RootTabView()
        .modelContainer(WorkoutPreviewData.container())
}

#Preview("Active session (resting)") { RootPreview(.resting, launchCheckRan: true) }

#Preview("Recovery alert (running)") { RootPreview(.firstSet, launchCheckRan: false) }

#Preview("Summary waiting for Save") { RootPreview(.finished, launchCheckRan: false) }
