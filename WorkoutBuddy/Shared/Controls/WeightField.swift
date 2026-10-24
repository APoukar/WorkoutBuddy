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
    @State private var valueAtFocus = 0.0
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
                    .accessibilityValue("\(Formatters.kg(kg)) kilograms")
            }
        }
        .onAppear { text = Formatters.kg(kg) }
        .onChange(of: text) { _, newText in
            guard isFocused else { return }
            // Empty or unparseable text restores the value from when editing began.
            let value = Formatters.committedKg(text: newText, current: valueAtFocus)
            if value != kg { kg = value }
        }
        .onChange(of: kg) { _, newValue in
            // Outside change (or stepper): refresh the text unless it already stands for this value.
            if Formatters.needsTextRewrite(text: text, value: newValue, valueAtFocus: valueAtFocus) {
                text = Formatters.kg(newValue)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                valueAtFocus = AppSettings.snapKg(kg)
            } else {
                // On focus loss reformat from the binding.
                text = Formatters.kg(kg)
            }
        }
    }
}

#Preview {
    @Previewable @State var kg = 22.5
    Form { WeightField(kg: $kg) }
}
