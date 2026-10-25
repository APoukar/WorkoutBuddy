import SwiftUI

/// Decimal text field plus a stepper. The stepper uses the weight step from Settings.
/// Values stay on the 0.5 kg grid. The binding follows every keystroke that parses, so a button
/// tapped mid-edit (Save, Done) sees what is on screen.
/// The text field is UIKit-backed and brings its own Done button above the decimal pad.
struct WeightField: View {
    @Binding var kg: Double
    var label = "Weight"

    @AppStorage(AppSettings.Key.weightStep) private var stepRaw = AppSettings.Default.weightStep.rawValue
    @State private var text = ""
    @State private var isFocused = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var step: WeightStep { WeightStep(rawValue: stepRaw) ?? .default }

    private var snappedKg: Binding<Double> {
        Binding(get: { kg }, set: { kg = AppSettings.snapKg($0) })
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        layout {
            Text(label).accessibilityHidden(true)
            HStack {
                DecimalTextField(
                    text: $text,
                    isFocused: $isFocused,
                    accessibilityLabel: "\(label) in kilograms",
                    alignment: dynamicTypeSize.isAccessibilitySize ? .left : .right,
                    keyboardType: .decimalPad
                )
                // 44 pt tall, and takes the free width so the whole value area focuses it.
                .frame(minWidth: 60, maxWidth: .infinity)
                Text("kg")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .layoutPriority(1)
                    .accessibilityHidden(true)
                Stepper(label, value: snappedKg, in: AppSettings.kgRange, step: step.kg)
                    .labelsHidden()
                    .accessibilityLabel(label)
                    .accessibilityValue(Formatters.spokenKilograms(kg))
            }
        }
        .numericTextEditing(
            value: $kg,
            text: $text,
            isFocused: $isFocused,
            commit: { Formatters.committedKg(text: $0, current: $1) },
            format: { Formatters.kg($0) },
            normalize: AppSettings.snapKg
        )
    }
}

#Preview {
    @Previewable @State var kg = 22.5
    Form { WeightField(kg: $kg) }
}
