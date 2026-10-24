import SwiftUI

/// Shared texts for failed actions.
nonisolated enum ErrorMessages {
    /// Fallback text when an error has no more specific message.
    static let generic = "Something went wrong. Please try again."
}

/// Shows an alert for a failed action. `message` maps the error to the text to show, so each
/// feature can use its own wording.
private struct ErrorAlert: ViewModifier {
    @Binding var error: Error?
    let message: (Error) -> String

    func body(content: Content) -> some View {
        content.alert(
            "Something Went Wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error.map(message) ?? "")
        }
    }
}

extension View {
    func errorAlert(_ error: Binding<Error?>, message: @escaping (Error) -> String) -> some View {
        modifier(ErrorAlert(error: error, message: message))
    }
}
