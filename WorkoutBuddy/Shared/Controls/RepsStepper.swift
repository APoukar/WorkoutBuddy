import SwiftUI

struct RepsStepper: View {
    @Binding var reps: Int
    var label = "Reps"

    var body: some View {
        Stepper(value: $reps, in: AppSettings.repsRange) {
            LabeledContent(label, value: reps.formatted())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(reps)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: reps = AppSettings.clampReps(reps + 1)
            case .decrement: reps = AppSettings.clampReps(reps - 1)
            @unknown default: break
            }
        }
    }
}

#Preview {
    @Previewable @State var reps = 10
    Form { RepsStepper(reps: $reps) }
}
