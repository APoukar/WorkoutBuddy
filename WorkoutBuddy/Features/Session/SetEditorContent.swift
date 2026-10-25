import SwiftUI
import UIKit

/// The scrolling content shared by the set screen and the set review: the exercise name, the position
/// line, the large reps and kg controls and two slots (under the position line: the Previous Set button
/// or the status badge; under the controls: the "Next" preview or Mark as Skipped). The caller owns the
/// reps and kg and adds its own bottom bar. Swipes attach to the scrolling content and are off while a
/// text field is being edited.
struct SetEditorContent<BelowPosition: View, Footer: View>: View {
    let exerciseName: String
    let position: String
    let spokenPosition: String
    @Binding var reps: Int
    @Binding var kg: Double
    let navigation: ReviewNavigation
    @ViewBuilder let belowPosition: BelowPosition
    @ViewBuilder let footer: Footer

    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exerciseName)
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(position)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(spokenPosition)
                            .reviewAccessibilityActions(navigation)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    belowPosition
                }

                LargeRepsControl(reps: $reps)
                LargeWeightControl(kg: $kg)

                footer
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityHiddenWhenCovered()
        .reviewSwipes(navigation, isEditing: isEditing)
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in
            isEditing = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in
            isEditing = false
        }
    }
}
