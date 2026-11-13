import ActivityKit
import SwiftUI
import WidgetKit

/// The workout's Live Activity on the Lock Screen and in the Dynamic Island.
///
/// A placeholder for now: phase 4, step 8 adds the real views.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            Text(context.state.workoutName)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.workoutName)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "dumbbell.fill")
            }
        }
    }
}

#Preview("Lock Screen", as: .content, using: WorkoutActivityAttributes(sessionID: UUID())) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(
        phase: .set, workoutName: "Push Day", exerciseName: "Bench Press", elapsedStart: .now)
}
