import SwiftData
import SwiftUI
import UIKit

/// The full-screen workout: the set screen, the rest screen or the summary, with the paused overlay on
/// top while paused. It gets only the session's ID and reads the session with its own query, so when the
/// row is gone (after Discard, before the cover closes) it renders nothing instead of reading a deleted
/// model. The child views get plain values and callbacks only. Every change goes through `SessionLibrary`
/// and is saved at once; the screen is derived from the stored state.
struct ActiveSessionView: View {
    let sessionID: UUID

    @Query private var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The End Workout or Discard Workout question being asked. This view keeps the state and decides what
    /// to ask; the overlay and the summary show the dialog from their buttons.
    @State private var confirmation: SessionConfirmation?
    @State private var error: Error?

    init(sessionID: UUID) {
        self.sessionID = sessionID
        _sessions = Query(filter: #Predicate<WorkoutSession> { $0.id == sessionID })
    }

    private var library: SessionLibrary { SessionLibrary(context: context) }

    /// The session, unless it's gone or being deleted.
    private var session: WorkoutSession? {
        guard let session = sessions.first, !session.isDeleted, session.modelContext != nil else { return nil }
        return session
    }

    var body: some View {
        let snapshot = session.map { library.snapshot(of: $0) }
        Group {
            if let session, let snapshot {
                content(session: session, snapshot: snapshot)
            } else {
                Color.clear
            }
        }
        .background(.background)
        .errorAlert($error, message: SessionMessages.failureMessage(for:))
        // Waits for the rest to end, then clears it and (in the foreground) plays the alert. Keyed on the
        // end time only, so it restarts when a rest starts, moves (resume) or is cleared, and is
        // cancelled by pause, skip and undo.
        .task(id: snapshot?.autoAdvanceDeadline) {
            if let endsAt = snapshot?.autoAdvanceDeadline { await autoAdvance(endsAt: endsAt) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { settleExpiredRest() }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Screens

    private func content(session: WorkoutSession, snapshot: SessionSnapshot) -> some View {
        let now = Date.now
        let screen = snapshot.screen(now: now)
        let key = SessionScreenKey(screen, in: snapshot)
        let paused = snapshot.isPaused
        let names = exerciseNames(of: session)
        let workoutName = session.workout?.name ?? SessionMessages.fallbackWorkoutName
        // A finished workout is never shown as paused.
        let timer = ElapsedTimerInfo(
            startedAt: snapshot.startedAt, pausedDuration: snapshot.pausedDuration,
            pausedAt: paused ? snapshot.pausedAt : nil)
        let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.25)

        return ZStack {
            screenView(screen, snapshot: snapshot, names: names, workoutName: workoutName, timer: timer, now: now)
                .id(key)
                .transition(.opacity)
                // The paused overlay is modal; the screen underneath is not reachable by VoiceOver.
                .accessibilityHidden(paused)
            if paused {
                PausedOverlayView(
                    timer: timer,
                    onResume: { run("Resume workout") { try $0.resume(in: $1) } },
                    onEnd: { confirmation = SessionConfirmation.forEndTap(in: snapshot) },
                    confirmation: $confirmation,
                    onConfirm: confirm)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(animation, value: key)
        .animation(animation, value: paused)
    }

    @ViewBuilder
    private func screenView(
        _ screen: SessionScreen, snapshot: SessionSnapshot, names: [UUID: String], workoutName: String,
        timer: ElapsedTimerInfo, now: Date
    ) -> some View {
        switch screen {
        case .set(let index):
            let entry = snapshot.entries[index]
            let prefill = snapshot.prefill(forSetAt: index)
            let nextName = snapshot.entries.indices.contains(index + 1)
                ? snapshot.entries[index + 1].exerciseID.flatMap { names[$0] } : nil
            SetScreenView(
                workoutName: workoutName,
                timer: timer,
                setID: entry.id,
                exerciseName: entry.exerciseID.flatMap { names[$0] } ?? SessionMessages.fallbackExerciseName,
                position: SessionMessages.position(of: index, in: snapshot),
                spokenPosition: SessionMessages.spokenPosition(of: index, in: snapshot),
                initialReps: prefill.reps,
                initialKg: prefill.kg,
                nextText: SessionMessages.nextPreview(after: index, in: snapshot, nextExerciseName: nextName),
                spokenNextText: SessionMessages.spokenNextPreview(after: index, in: snapshot, nextExerciseName: nextName),
                onDone: { setID, reps, kg in
                    run("Complete set") { try $0.completeSet(in: $1, setID: setID, reps: reps, kg: kg) }
                },
                onSkip: { setID in run("Skip set") { try $0.skipSet(in: $1, setID: setID) } },
                onPause: { run("Pause workout") { try $0.pause(in: $1) } })

        case .rest(let next, let remaining):
            let nextEntry = snapshot.entries[next]
            let nextName = nextEntry.exerciseID.flatMap { names[$0] }
            let undoIndex = snapshot.undoTargetIndex(now: now)
            // The rest being counted is the planned rest of the set just done, i.e. the Undo target.
            let total = undoIndex.map { snapshot.entries[$0].planned.restSeconds } ?? remaining
            RestScreenView(
                workoutName: workoutName,
                timer: timer,
                rest: RestTimerInfo(
                    endsAt: snapshot.restEndsAt ?? now.addingTimeInterval(TimeInterval(remaining)),
                    totalSeconds: total,
                    pausedAt: snapshot.isPaused ? snapshot.pausedAt : nil),
                undoSetID: undoIndex.map { snapshot.entries[$0].id },
                upNext: SessionMessages.upNext(at: next, in: snapshot, exerciseName: nextName),
                spokenUpNext: SessionMessages.spokenUpNext(at: next, in: snapshot, exerciseName: nextName),
                onSkipRest: { run("Skip rest") { try $0.skipRest(in: $1) } },
                onUndo: { setID in run("Undo set") { try $0.undo(in: $1, setID: setID) } },
                onPause: { run("Pause workout") { try $0.pause(in: $1) } })

        case .summary:
            SessionSummaryView(
                workoutName: workoutName,
                content: SessionSummaryContent(SessionStats(snapshot, now: now)),
                onSave: { run("Save workout") { try $0.save($1) } },
                onDiscard: { confirmation = .discard },
                confirmation: $confirmation,
                onConfirm: confirm)
        }
    }

    /// Exercise names by ID, looked up through the references (names are never copied into a session).
    private func exerciseNames(of session: WorkoutSession) -> [UUID: String] {
        let pairs = session.orderedExercises.compactMap { row in row.exercise.map { ($0.id, $0.name) } }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Actions

    /// Runs one library action on the current session. A failure is logged and shown in an alert.
    /// `action` must be a fixed string (it is logged publicly).
    private func run(_ action: String, _ body: (SessionLibrary, WorkoutSession) throws -> Void) {
        guard let session = freshSession() else { return }
        do {
            try body(library, session)
        } catch {
            ErrorLogging.log(error, action: action, category: "session")
            self.error = error
        }
    }

    /// Fetched by ID each time, so a long-running task never acts on a stale model.
    private func freshSession() -> WorkoutSession? {
        let id = sessionID
        do {
            return try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })).first
        } catch {
            ErrorLogging.log(error, action: "Load workout session", category: "session")
            self.error = error
            return nil
        }
    }

    private func confirm(_ item: SessionConfirmation) {
        switch item {
        case .end: run("End workout") { try $0.endEarly(in: $1) }
        case .discard: run("Discard workout") { try $0.discard($1) }
        }
    }

    // MARK: Rest end

    /// Sleeps until `endsAt`, then clears the rest (which opens the next set). The haptic and sound play
    /// only if the app noticed the end within a couple of seconds and is in the foreground; after a
    /// stay in the background the next set just shows.
    private func autoAdvance(endsAt: Date) async {
        while Date.now < endsAt {
            do { try await Task.sleep(for: .seconds(max(endsAt.timeIntervalSinceNow, 0.01))) } catch { return }
        }
        let noticedAt = Date.now
        guard !Task.isCancelled, let session = freshSession(),
            library.snapshot(of: session).restEndsAt == endsAt
        else { return }
        let inForeground = UIApplication.shared.applicationState == .active
        do {
            try library.finishRest(in: session, now: noticedAt)
        } catch {
            ErrorLogging.log(error, action: "Finish rest", category: "session")
            self.error = error
            return
        }
        if inForeground, RestAlertRules.shouldPlayAlert(restEndsAt: endsAt, noticedAt: noticedAt) {
            RestAlert.play()
        }
    }

    /// Coming back to the app: clears a rest that ran out meanwhile, silently, so the next set shows.
    private func settleExpiredRest() {
        guard let session = freshSession(), library.snapshot(of: session).hasExpiredRest(now: .now) else { return }
        run("Finish rest") { try $0.finishRest(in: $1) }
    }
}

private struct ActiveSessionPreview: View {
    let state: SessionPreviewData.State
    @State private var preview: SessionPreviewData.Preview

    init(_ state: SessionPreviewData.State) {
        self.state = state
        _preview = State(initialValue: SessionPreviewData.make(state))
    }

    var body: some View {
        ActiveSessionView(sessionID: preview.sessionID)
            .modelContainer(preview.container)
    }
}

#Preview("First set") { ActiveSessionPreview(.firstSet) }
#Preview("Resting") { ActiveSessionPreview(.resting) }
#Preview("Paused") { ActiveSessionPreview(.paused) }
#Preview("Finished") { ActiveSessionPreview(.finished) }
#Preview("Ended early") { ActiveSessionPreview(.endedEarly) }
#Preview("Nothing done") { ActiveSessionPreview(.allSkipped) }
#Preview("Accessibility text size") {
    ActiveSessionPreview(.resting).dynamicTypeSize(.accessibility3)
}
