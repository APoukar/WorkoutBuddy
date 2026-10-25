import SwiftUI

/// The layout both large value controls share: a label above, then a - button, the big value and a
/// + button. At accessibility text sizes the buttons move under the value. The buttons are at least
/// 60 pt, hidden from VoiceOver (the control's owner exposes one adjustable element instead) and
/// disabled at the ends of the range.
struct LargeValueControlLayout<Field: View>: View {
    let label: String
    let canDecrement: Bool
    let canIncrement: Bool
    let decrement: () -> Void
    let increment: () -> Void
    @ViewBuilder var field: Field

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                field
                HStack {
                    stepButton("minus", enabled: canDecrement, action: decrement)
                    Spacer()
                    stepButton("plus", enabled: canIncrement, action: increment)
                }
            } else {
                HStack(spacing: 12) {
                    stepButton("minus", enabled: canDecrement, action: decrement)
                    field
                    stepButton("plus", enabled: canIncrement, action: increment)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 60, minHeight: 60)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(!enabled)
        .accessibilityHidden(true)
    }
}
