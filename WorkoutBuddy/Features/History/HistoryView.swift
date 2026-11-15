import SwiftData
import SwiftUI
import UIKit

/// The History tab (F6): a month calendar with a dot on every day with a saved workout. Tapping a day opens
/// the session detail (one workout) or a day list (several). The stack's path holds IDs and days, never
/// models, so a deleted session can't leave a dangling value.
struct HistoryView: View {
    /// Finished sessions, oldest first (`HistoryLibrary.finishedDescriptor()`, the one definition of history).
    @Query private var sessions: [WorkoutSession]
    @Environment(\.scenePhase) private var scenePhase

    @State private var path: [HistoryRoute] = []
    /// The current time as the calendar knows it: refreshed when the day changes (time change, coming back).
    @State private var today = Date.now
    /// Every increase scrolls the calendar back to the current month.
    @State private var todayTrigger = 0

    init() {
        _sessions = Query(HistoryLibrary.finishedDescriptor())
    }

    private var calendar: Calendar { .current }

    private var entries: [HistoryEntry] {
        sessions.map { HistoryEntry(id: $0.id, startedAt: $0.startedAt) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                HistoryCalendarView(
                    days: HistoryRules.days(of: entries, calendar: calendar), today: today, calendar: calendar,
                    todayTrigger: todayTrigger, onSelect: select
                )
                .id(today)  // Recreated when the day changes: UICalendarView may not move its own today ring at midnight.
                .padding(.horizontal)
                if sessions.isEmpty {
                    ContentUnavailableView {
                        Label(HistoryMessages.emptyTitle, systemImage: "calendar")
                    } description: {
                        Text(HistoryMessages.emptyMessage)
                    }
                }
            }
            .navigationTitle(HistoryMessages.tabTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(HistoryMessages.todayButton) { todayTrigger += 1 }
                }
            }
            .navigationDestination(for: HistoryRoute.self) { route in
                switch route {
                case .day(let day):
                    HistoryDayView(day: day, sessions: sessionsOf(day))
                case .session(let id):
                    SessionDetailView(sessionID: id, onDeleted: { deleted(id) })
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshToday()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshToday() }
        }
    }

    private func sessionsOf(_ day: HistoryDay) -> [WorkoutSession] {
        let ids = HistoryRules.sessions(on: day, in: entries, calendar: calendar).map(\.id)
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    private func select(_ day: HistoryDay) {
        let onDay = HistoryRules.sessions(on: day, in: entries, calendar: calendar)
        switch HistoryRules.destination(for: day, sessions: onDay) {
        case .none: break
        case .session(let id): path.append(.session(id))
        case .dayList(let day): path.append(.day(day))
        }
    }

    private func deleted(_ id: UUID) {
        path = HistoryRules.path(afterDeleting: id, from: path, remaining: entries, calendar: calendar)
    }

    /// Only when the calendar day changed, so the calendar's range isn't reset on every return to the app.
    private func refreshToday() {
        if !calendar.isDate(today, inSameDayAs: .now) { today = .now }
    }
}

#Preview("With workouts") {
    HistoryView().modelContainer(HistoryPreviewData.make().container)
}

#Preview("Empty") {
    HistoryView().modelContainer(WorkoutPreviewData.container())
}
