import SwiftData
import SwiftUI

/// The day list (F6): the saved workouts of one day, oldest first, each leading to its detail. Shown when a
/// tapped day has more than one session. Names come from the references, never from a copy.
struct HistoryDayView: View {
    let day: HistoryDay
    /// The day's sessions, oldest first.
    let sessions: [WorkoutSession]

    @Environment(\.modelContext) private var context

    private var title: String {
        let calendar = Calendar.current
        guard let date = calendar.date(from: day.dateComponents(calendar: calendar)) else { return "" }
        return Formatters.dayTitle(date)
    }

    var body: some View {
        List(sessions) { session in
            NavigationLink(value: HistoryRoute.session(session.id)) { row(for: session) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for session: WorkoutSession) -> some View {
        let library = SessionLibrary(context: context)
        let snapshot = library.snapshot(of: session)
        let stats = SessionStats(snapshot, now: snapshot.endedAt ?? snapshot.startedAt)
        let name = session.workout?.name
        return VStack(alignment: .leading, spacing: 2) {
            Text(HistoryMessages.workoutName(name))
            Text(HistoryMessages.dayRowDetail(startedAt: session.startedAt, stats: stats))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            HistoryMessages.spokenDayRow(name: name, startedAt: session.startedAt, stats: stats))
    }
}

#Preview {
    let preview = HistoryPreviewData.make()
    let sessions = (try? HistoryLibrary(context: preview.container.mainContext).finishedSessions()) ?? []
    let calendar = Calendar.current
    let evening = sessions.first { $0.id == preview.completedID }
    return NavigationStack {
        HistoryDayView(
            day: HistoryDay(evening?.startedAt ?? .now, calendar: calendar),
            sessions: sessions.filter {
                HistoryDay($0.startedAt, calendar: calendar) == HistoryDay(evening?.startedAt ?? .now, calendar: calendar)
            })
    }
    .modelContainer(preview.container)
}
