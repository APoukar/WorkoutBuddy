import SwiftUI

/// Big reps control for the set screen: a label, - / + buttons and a large value that can be typed
/// into. Steps by 1 within `AppSettings.repsRange`. Like `WeightField`, the binding follows every
/// keystroke that parses, so Done sees what is on screen.
///
/// VoiceOver sees one adjustable element ("Reps, 10") with an "Edit Value" action that focuses the field.
struct LargeRepsControl: View {
    @Binding var reps: Int
    var label = "Reps"

    @State private var text = ""
    @State private var isFocused = false

    var body: some View {
        LargeValueControlLayout(
            label: label,
            canDecrement: reps > AppSettings.repsRange.lowerBound,
            canIncrement: reps < AppSettings.repsRange.upperBound,
            decrement: { reps = AppSettings.clampReps(reps - 1) },
            increment: { reps = AppSettings.clampReps(reps + 1) }
        ) {
            DecimalTextField(
                text: $text,
                isFocused: $isFocused,
                accessibilityLabel: label,
                alignment: .center,
                keyboardType: .numberPad,
                fontConfiguration: .largeValue
            )
            .frame(minWidth: 60, maxWidth: .infinity)
        }
        .numericTextEditing(
            value: $reps,
            text: $text,
            isFocused: $isFocused,
            commit: { Formatters.committedReps(text: $0, current: $1) },
            format: { String($0) }
        )
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
        .accessibilityAction(named: "Edit Value") { isFocused = true }
    }
}

#Preview("Default") {
    @Previewable @State var reps = 10
    LargeRepsControl(reps: $reps).padding()
}

#Preview("Accessibility text size") {
    @Previewable @State var reps = 100
    LargeRepsControl(reps: $reps)
        .padding()
        .dynamicTypeSize(.accessibility3)
}
