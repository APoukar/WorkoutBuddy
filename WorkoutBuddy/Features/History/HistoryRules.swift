import Foundation

/// A local calendar day (year, month, day). Compares and navigates cleanly, unlike a raw `DateComponents`.
nonisolated struct HistoryDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day of `date` in `calendar` (its time zone decides).
    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// For `UICalendarView`. Carries the calendar so the view and the rules agree.
    func dateComponents(calendar: Calendar) -> DateComponents {
        DateComponents(calendar: calendar, year: year, month: month, day: day)
    }

    init?(_ components: DateComponents) {
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    static func < (a: HistoryDay, b: HistoryDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// A screen of the History tab's navigation stack.
nonisolated enum HistoryRoute: Hashable, Sendable {
    case day(HistoryDay)
    case session(UUID)
}

/// What a session needs for the day rules: its ID and start.
nonisolated struct HistoryEntry: Hashable, Sendable {
    let id: UUID
    let startedAt: Date
}

/// Where tapping a day leads.
nonisolated enum HistoryDestination: Equatable, Sendable {
    case none
    case session(UUID)
    case dayList(HistoryDay)
}

/// The History tab's decisions that don't need a view or a model. A session belongs to the local calendar day
/// of `startedAt`, so a workout that runs past midnight sits on the day it started.
nonisolated enum HistoryRules {
    static func days(of entries: [HistoryEntry], calendar: Calendar) -> Set<HistoryDay> {
        Set(entries.map { HistoryDay($0.startedAt, calendar: calendar) })
    }

    /// The sessions that started on `day`, oldest first (the ID only makes equal starts deterministic).
    static func sessions(on day: HistoryDay, in entries: [HistoryEntry], calendar: Calendar) -> [HistoryEntry] {
        entries
            .filter { HistoryDay($0.startedAt, calendar: calendar) == day }
            .sorted { a, b in
                a.startedAt != b.startedAt ? a.startedAt < b.startedAt : a.id.uuidString < b.id.uuidString
            }
    }

    /// - Parameter sessions: the sessions of `day` (see `sessions(on:in:calendar:)`).
    static func destination(for day: HistoryDay, sessions: [HistoryEntry]) -> HistoryDestination {
        switch sessions.count {
        case 0: .none
        case 1: .session(sessions[0].id)
        default: .dayList(day)
        }
    }

    /// The path after the session `id` was deleted: its screen is dropped, and the day list under it too when
    /// its day has no session left. `remaining` may still contain the deleted session; it's ignored.
    static func path(
        afterDeleting id: UUID, from path: [HistoryRoute], remaining: [HistoryEntry], calendar: Calendar
    ) -> [HistoryRoute] {
        guard let index = path.firstIndex(of: .session(id)) else { return path }
        var result = Array(path[..<index])
        if case .day(let day)? = result.last {
            let left = remaining.filter { $0.id != id }
            if sessions(on: day, in: left, calendar: calendar).isEmpty { result.removeLast() }
        }
        return result
    }

    /// Whether a calendar day can be selected: days with a workout, and today (iOS draws a non-selectable today
    /// in plain grey, which would lose the "today highlighted" look; tapping an empty today does nothing).
    static func isSelectable(_ day: HistoryDay, days: Set<HistoryDay>, today: HistoryDay) -> Bool {
        days.contains(day) || day == today
    }

    /// The days whose decoration or selectability changed: in exactly one of the two sets. Sorted.
    static func daysToReload(old: Set<HistoryDay>, new: Set<HistoryDay>) -> [HistoryDay] {
        old.symmetricDifference(new).sorted()
    }

    /// The end of `UICalendarView.availableDateRange`: the start of today. The calendar treats the range by day,
    /// so "start of tomorrow" would let the next month in on the last day of a month.
    static func availableRangeEnd(now: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: now)
    }
}
