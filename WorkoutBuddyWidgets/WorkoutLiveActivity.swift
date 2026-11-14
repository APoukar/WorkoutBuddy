import ActivityKit
import SwiftUI
import WidgetKit

/// The workout's Live Activity on the Lock Screen and in the Dynamic Island. The views are in
/// `WorkoutActivityViews.swift`.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityContentView(
                state: context.state, phase: context.state.displayPhase(isStale: context.isStale))
                .padding()
        } dynamicIsland: { context in
            let phase = context.state.displayPhase(isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WorkoutActivityExpandedLeading(state: context.state, phase: phase)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutActivityExpandedTrailing(state: context.state, phase: phase)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutActivityExpandedBottom(state: context.state, phase: phase)
                }
            } compactLeading: {
                Image(systemName: phase.symbolName)
                    .accessibilityHidden(true)
            } compactTrailing: {
                WorkoutActivityCompactTrailing(state: context.state, phase: phase)
            } minimal: {
                WorkoutActivityMinimal(state: context.state, phase: phase)
            }
        }
    }
}
