import SwiftUI

/// The text <-> value handling shared by `WeightField` and the large reps and kg controls.
///
/// - The value follows every keystroke that parses. Empty or unparseable text restores the value
///   from when editing began (`valueAtFocus`), so a button tapped mid-edit (Save, Done) sees what is
///   on screen.
/// - An outside change to the value (a +/- button, a stepper) rewrites the text, unless the text
///   already stands for that value, so typing isn't disturbed.
/// - On focus loss the text is reformatted from the value.
///
/// The view owns `text` and `isFocused` (they are bound to a `DecimalTextField`); this modifier
/// only keeps them and `value` in step.
struct NumericTextEditing<Value: Equatable>: ViewModifier {
    @Binding var value: Value
    @Binding var text: String
    @Binding var isFocused: Bool
    /// The value typed text stands for: parsed (and snapped or clamped) text, or the given current value if it doesn't parse.
    let commit: (_ text: String, _ current: Value) -> Value
    /// The text that represents a value.
    let format: (Value) -> String
    /// Applied to the value when editing begins (for example snapping to the kg grid).
    let normalize: (Value) -> Value

    @State private var valueAtFocus: Value

    init(
        value: Binding<Value>,
        text: Binding<String>,
        isFocused: Binding<Bool>,
        commit: @escaping (String, Value) -> Value,
        format: @escaping (Value) -> String,
        normalize: @escaping (Value) -> Value = { $0 }
    ) {
        _value = value
        _text = text
        _isFocused = isFocused
        self.commit = commit
        self.format = format
        self.normalize = normalize
        _valueAtFocus = State(initialValue: value.wrappedValue)
    }

    /// Whether the text must be rewritten after the value changed to `value`. Text that already
    /// stands for the value (by the `commit` rule, where empty or invalid text stands for
    /// `valueAtFocus`) is left alone so typing isn't disturbed.
    nonisolated static func needsTextRewrite(
        text: String, value: Value, valueAtFocus: Value,
        commit: (String, Value) -> Value
    ) -> Bool {
        commit(text, valueAtFocus) != value
    }

    func body(content: Content) -> some View {
        content
            .onAppear { text = format(value) }
            .onChange(of: text) { _, newText in
                guard isFocused else { return }
                // Empty or unparseable text restores the value from when editing began.
                let newValue = commit(newText, valueAtFocus)
                if newValue != value { value = newValue }
            }
            .onChange(of: value) { _, newValue in
                // Outside change (or stepper): refresh the text unless it already stands for this value.
                if Self.needsTextRewrite(text: text, value: newValue, valueAtFocus: valueAtFocus, commit: commit) {
                    text = format(newValue)
                }
            }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    valueAtFocus = normalize(value)
                } else {
                    // On focus loss reformat from the binding.
                    text = format(value)
                }
            }
    }
}

extension View {
    func numericTextEditing<Value: Equatable>(
        value: Binding<Value>,
        text: Binding<String>,
        isFocused: Binding<Bool>,
        commit: @escaping (String, Value) -> Value,
        format: @escaping (Value) -> String,
        normalize: @escaping (Value) -> Value = { $0 }
    ) -> some View {
        modifier(NumericTextEditing(
            value: value, text: text, isFocused: isFocused,
            commit: commit, format: format, normalize: normalize
        ))
    }
}
