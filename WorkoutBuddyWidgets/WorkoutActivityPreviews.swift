import SwiftUI
import WidgetKit

/// Sample content states for the previews. Previews can't show `isStale`, so "Rest over" has its own preview
/// of the content view with the display phase passed in.
private enum PreviewStates {
    static let attributes = WorkoutActivityAttributes(sessionID: UUID())
    static let start = Date.now.addingTimeInterval(-754)

    static let set = ActivityState(
        phase: .set, workoutName: "Push Day", exerciseName: "Bench Press",
        position: "Exercise 2 of 5 · Set 3 of 4", spokenPosition: "Exercise 2 of 5, set 3 of 4",
        setLine: "10 × 60 kg", spokenSetLine: "10 reps, 60 kilograms", elapsedStart: start)

    static let bodyweight = ActivityState(
        phase: .set, workoutName: "Push Day", exerciseName: "Push-ups",
        position: "Exercise 1 of 5 · Set 1 of 3", setLine: "15 × Bodyweight", elapsedStart: start)

    static let longName = ActivityState(
        phase: .set, workoutName: "A Very Long Workout Name For The Whole Week",
        exerciseName: "Incline Dumbbell Bench Press With A Very Long Name",
        position: "Exercise 12 of 15 · Set 10 of 12", setLine: "12 × 22.5 kg", elapsedStart: start)

    static let rest = ActivityState(
        phase: .rest, workoutName: "Push Day", exerciseName: "Bench Press",
        position: "Exercise 2 of 5 · Set 4 of 4", setLine: "10 × 60 kg",
        upNext: "Bench Press · Set 4 · 10 × 60 kg",
        spokenUpNext: "Bench Press, set 4, 10 reps at 60 kilograms", elapsedStart: start,
        restStart: .now, restEnd: .now.addingTimeInterval(90))

    static let pausedSet = ActivityState(
        phase: .paused, workoutName: "Push Day", exerciseName: "Bench Press",
        position: "Exercise 2 of 5 · Set 3 of 4", setLine: "10 × 60 kg",
        elapsedStart: start, pausedAt: .now)

    static let pausedRest = ActivityState(
        phase: .paused, workoutName: "Push Day", exerciseName: "Bench Press",
        position: "Exercise 2 of 5 · Set 4 of 4", setLine: "10 × 60 kg",
        elapsedStart: start, pausedAt: .now, frozenRestText: "1:05")

    static let finishedComplete = ActivityState(
        phase: .finished, workoutName: "Push Day", elapsedStart: start,
        summaryTitle: "Workout Complete", durationText: "45 min", spokenDurationText: "45 minutes")

    static let finishedEnded = ActivityState(
        phase: .finished, workoutName: "Push Day", elapsedStart: start,
        summaryTitle: "Workout Ended", durationText: "12 min", spokenDurationText: "12 minutes")

}

#Preview("Lock Screen", as: .content, using: PreviewStates.attributes) {
    WorkoutLiveActivity()
} contentStates: {
    PreviewStates.set
    PreviewStates.rest
    PreviewStates.pausedSet
    PreviewStates.pausedRest
    PreviewStates.finishedComplete
    PreviewStates.finishedEnded
    PreviewStates.bodyweight
    PreviewStates.longName
}

#Preview("Rest over (stale)") {
    WorkoutActivityContentView(state: PreviewStates.rest, phase: .restOver)
        .padding()
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: PreviewStates.attributes) {
    WorkoutLiveActivity()
} contentStates: {
    PreviewStates.set
    PreviewStates.rest
    PreviewStates.pausedRest
    PreviewStates.finishedComplete
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: PreviewStates.attributes) {
    WorkoutLiveActivity()
} contentStates: {
    PreviewStates.set
    PreviewStates.rest
    PreviewStates.pausedRest
    PreviewStates.finishedEnded
    PreviewStates.longName
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: PreviewStates.attributes) {
    WorkoutLiveActivity()
} contentStates: {
    PreviewStates.set
    PreviewStates.rest
    PreviewStates.pausedSet
    PreviewStates.finishedComplete
}
