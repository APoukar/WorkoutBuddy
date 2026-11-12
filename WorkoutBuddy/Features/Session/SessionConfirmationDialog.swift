import SwiftUI

/// Presents a `SessionConfirmation` as a confirmation dialog anchored to the view it's attached to
/// (on iOS 26 and later it appears as a popover from that view). The owner keeps the state and decides
/// what to ask; the view only shows the question and reports the confirmation.
private struct SessionConfirmationDialog: ViewModifier {
    @Binding var confirmation: SessionConfirmation?
    let onConfirm: (SessionConfirmation) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible,
            presenting: confirmation
        ) { item in
            Button(item.confirmButton, role: .destructive) { onConfirm(item) }
            Button(SessionMessages.cancelButton, role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
    }
}

extension View {
    func sessionConfirmation(
        _ confirmation: Binding<SessionConfirmation?>, onConfirm: @escaping (SessionConfirmation) -> Void
    ) -> some View {
        modifier(SessionConfirmationDialog(confirmation: confirmation, onConfirm: onConfirm))
    }
}
