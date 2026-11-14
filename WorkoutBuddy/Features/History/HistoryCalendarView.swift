import SwiftData
import SwiftUI
import UIKit

/// The History tab's month calendar: UIKit's `UICalendarView` with a dot on every day that has a saved workout.
/// Only those days and today can be selected (selectability is also what VoiceOver gets to know; today stays
/// selectable so iOS draws it highlighted). A tap on a day with a workout is reported to SwiftUI; the selection
/// is cleared right away, so the same day can be tapped again after coming back. A tap on an empty today only
/// clears the selection.
///
/// `calendar` is the one the rules use (`HistoryDay`, `HistoryRules`), so dots and taps always line up.
struct HistoryCalendarView: UIViewRepresentable {
    /// The days that have a workout.
    let days: Set<HistoryDay>
    /// The current time. The calendar's range changes only when this changes, never on every update, because
    /// that would jump the visible month while the user swipes.
    let today: Date
    let calendar: Calendar
    /// A one-shot command: every increase scrolls back to the current month.
    let todayTrigger: Int
    let onSelect: (HistoryDay) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(days: days, today: today, calendar: calendar, todayTrigger: todayTrigger, onSelect: onSelect)
    }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.timeZone = calendar.timeZone
        view.delegate = context.coordinator
        view.availableDateRange = Self.range(today: today, calendar: calendar)
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.selectionBehavior = selection
        context.coordinator.selection = selection
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect

        if coordinator.today != today || coordinator.calendar != calendar {
            coordinator.today = today
            if coordinator.calendar != calendar {
                coordinator.calendar = calendar
                view.calendar = calendar
                view.timeZone = calendar.timeZone
            }
            view.availableDateRange = Self.range(today: today, calendar: calendar)
            coordinator.selection?.updateSelectableDates()
        }

        if coordinator.days != days {
            // The day set first, so the system asks about the new state when it reloads.
            let changed = HistoryRules.daysToReload(old: coordinator.days, new: days)
            coordinator.days = days
            view.reloadDecorations(
                forDateComponents: changed.map { $0.dateComponents(calendar: calendar) }, animated: true)
            coordinator.selection?.updateSelectableDates()
        }

        if coordinator.todayTrigger != todayTrigger {
            coordinator.todayTrigger = todayTrigger
            let current = HistoryDay(today, calendar: calendar).dateComponents(calendar: calendar)
            view.setVisibleDateComponents(current, animated: true)
        }
    }

    /// Fits the calendar's own height at the proposed width, so 5- and 6-week months and accessibility text
    /// sizes get the right height inside a `ScrollView`.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let fitted = uiView.systemLayoutSizeFitting(
            target, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return CGSize(width: width, height: fitted.height)
    }

    /// From long ago to the start of today (see `HistoryRules.availableRangeEnd`).
    private static func range(today: Date, calendar: Calendar) -> DateInterval {
        let end = HistoryRules.availableRangeEnd(now: today, calendar: calendar)
        let start = calendar.date(byAdding: .year, value: -100, to: end) ?? .distantPast
        return DateInterval(start: start, end: end)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var days: Set<HistoryDay>
        var today: Date
        var todayTrigger: Int
        var onSelect: (HistoryDay) -> Void
        var calendar: Calendar
        var selection: UICalendarSelectionSingleDate?

        init(
            days: Set<HistoryDay>, today: Date, calendar: Calendar, todayTrigger: Int,
            onSelect: @escaping (HistoryDay) -> Void
        ) {
            self.days = days
            self.today = today
            self.calendar = calendar
            self.todayTrigger = todayTrigger
            self.onSelect = onSelect
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents)
            -> UICalendarView.Decoration?
        {
            guard let day = HistoryDay(dateComponents), days.contains(day) else { return nil }
            return .default()
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?)
            -> Bool
        {
            guard let dateComponents, let day = HistoryDay(dateComponents) else { return false }
            return HistoryRules.isSelectable(day, days: days, today: HistoryDay(today, calendar: calendar))
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let day = HistoryDay(dateComponents) else { return }
            if days.contains(day) { onSelect(day) }
            selection.setSelected(nil, animated: false)
        }
    }
}

private struct CalendarPreview: View {
    let days: Set<HistoryDay>
    @State private var selected: HistoryDay?

    var body: some View {
        ScrollView {
            HistoryCalendarView(days: days, today: .now, calendar: .current, todayTrigger: 0) { selected = $0 }
                .padding(.horizontal)
            Text(selected.map { "Tapped \($0.year)-\($0.month)-\($0.day)" } ?? "Nothing tapped")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private func previewDays() -> Set<HistoryDay> {
    let preview = HistoryPreviewData.make()
    let sessions = (try? HistoryLibrary(context: preview.container.mainContext).finishedSessions()) ?? []
    return HistoryRules.days(
        of: sessions.map { HistoryEntry(id: $0.id, startedAt: $0.startedAt) }, calendar: .current)
}

#Preview("With workouts") { CalendarPreview(days: previewDays()) }

#Preview("Empty") { CalendarPreview(days: []) }

#Preview("Accessibility size") {
    CalendarPreview(days: previewDays()).dynamicTypeSize(.accessibility3)
}
