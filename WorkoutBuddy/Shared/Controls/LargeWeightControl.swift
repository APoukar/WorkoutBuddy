import SwiftUI

/// Big kg control for the set screen: a label, - / + buttons and a large value that can be typed
/// into. The step comes from Settings (`WeightStep`); values stay on the 0.5 kg grid within
/// `AppSettings.kgRange`. 0 shows as "0" (as in other editing controls). Like `WeightField`, the
/// binding follows every keystroke that parses.
///
/// VoiceOver sees one adjustable element ("Weight, 60 kilograms") with an "Edit Value" action that
/// focuses the field.
struct LargeWeightControl: View {
    @Binding var kg: Double
    var label = "Weight (kg)"

    @AppStorage(AppSettings.Key.weightStep) private var stepRaw = AppSettings.Default.weightStep.rawValue
    @State private var text = ""
    @State private var isFocused = false

    private var step: WeightStep { WeightStep(rawValue: stepRaw) ?? .default }

    var body: some View {
        LargeValueControlLayout(
            label: label,
            canDecrement: kg > AppSettings.kgRange.lowerBound,
            canIncrement: kg < AppSettings.kgRange.upperBound,
            decrement: { kg = AppSettings.snapKg(kg - step.kg) },
            increment: { kg = AppSettings.snapKg(kg + step.kg) }
        ) {
            DecimalTextField(
                text: $text,
                isFocused: $isFocused,
                accessibilityLabel: "Weight in kilograms",
                alignment: .center,
                keyboardType: .decimalPad,
                fontConfiguration: .largeValue
            )
            .frame(minWidth: 60, maxWidth: .infinity)
        }
        .numericTextEditing(
            value: $kg,
            text: $text,
            isFocused: $isFocused,
            commit: { Formatters.committedKg(text: $0, current: $1) },
            format: { Formatters.kg($0) },
            normalize: AppSettings.snapKg
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight")
        .accessibilityValue(Formatters.spokenKilograms(kg))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: kg = AppSettings.snapKg(kg + step.kg)
            case .decrement: kg = AppSettings.snapKg(kg - step.kg)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Edit Value") { isFocused = true }
    }
}

#Preview("Default") {
    @Previewable @State var kg = 62.5
    LargeWeightControl(kg: $kg).padding()
}

#Preview("Bodyweight") {
    @Previewable @State var kg = 0.0
    LargeWeightControl(kg: $kg).padding()
}

#Preview("Accessibility text size") {
    @Previewable @State var kg = 127.5
    LargeWeightControl(kg: $kg)
        .padding()
        .dynamicTypeSize(.accessibility3)
}
