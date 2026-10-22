import SwiftUI

struct RestStepper: View {
    @Binding var seconds: Int
    var label = "Rest"

    var body: some View {
        Stepper(
            value: $seconds,
            in: AppSettings.restRange,
            step: AppSettings.restStep
        ) {
            LabeledContent(label, value: Formatters.rest(seconds: seconds))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Formatters.spokenDuration(seconds: seconds))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seconds = AppSettings.clampRest(seconds + AppSettings.restStep)
            case .decrement: seconds = AppSettings.clampRest(seconds - AppSettings.restStep)
            @unknown default: break
            }
        }
    }
}

#Preview {
    @Previewable @State var seconds = 90
    Form { RestStepper(seconds: $seconds) }
}
