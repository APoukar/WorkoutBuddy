import SwiftUI
import UIKit

/// A UIKit-backed decimal text field that owns its own "Done" keyboard accessory.
///
/// The decimal pad has no return key, and SwiftUI's `.keyboard` toolbar placement is unreliable
/// (non-first `TabView` tabs, sheets), so the field supplies an `inputAccessoryView` itself and
/// nothing depends on SwiftUI toolbar hosting. `text` updates on every keystroke; `isFocused`
/// follows editing begin/end.
struct DecimalTextField: UIViewRepresentable {
    /// The field's font. The default is today's body font. With a `pointSize` the font is built from
    /// the system font (optionally rounded, with monospaced digits) and scaled for Dynamic Type
    /// with `UIFontMetrics` for `textStyle`, never beyond `maximumPointSize`.
    struct FontConfiguration: Equatable {
        var textStyle: UIFont.TextStyle = .body
        /// Base size at the default text size. `nil` means the plain preferred font for `textStyle`.
        var pointSize: CGFloat?
        var weight: UIFont.Weight = .regular
        var rounded = false
        var monospacedDigits = false
        var maximumPointSize: CGFloat?

        static let body = FontConfiguration()

        /// The big value of the large reps and kg controls.
        static let largeValue = FontConfiguration(
            textStyle: .largeTitle, pointSize: 48, weight: .bold,
            rounded: true, monospacedDigits: true, maximumPointSize: 72
        )

        func makeFont(compatibleWith traits: UITraitCollection? = nil) -> UIFont {
            guard let pointSize else { return .preferredFont(forTextStyle: textStyle) }
            var descriptor = UIFont.systemFont(ofSize: pointSize, weight: weight).fontDescriptor
            if rounded, let roundedDescriptor = descriptor.withDesign(.rounded) { descriptor = roundedDescriptor }
            if monospacedDigits {
                descriptor = descriptor.addingAttributes([
                    .featureSettings: [[
                        UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                        UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                    ]],
                ])
            }
            let base = UIFont(descriptor: descriptor, size: pointSize)
            let metrics = UIFontMetrics(forTextStyle: textStyle)
            if let maximumPointSize {
                return metrics.scaledFont(for: base, maximumPointSize: maximumPointSize, compatibleWith: traits)
            }
            return metrics.scaledFont(for: base, compatibleWith: traits)
        }
    }

    @Binding var text: String
    @Binding var isFocused: Bool
    var accessibilityLabel: String
    var alignment: NSTextAlignment = .right
    var minWidth: CGFloat = 60
    var keyboardType: UIKeyboardType = .decimalPad
    var fontConfiguration: FontConfiguration = .body

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = keyboardType
        field.font = fontConfiguration.makeFont()
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .none
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)

        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        let done = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak field] _ in
            field?.resignFirstResponder()
        })
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        toolbar.sizeToFit()
        field.inputAccessoryView = toolbar
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.appliedFont != fontConfiguration {
            context.coordinator.appliedFont = fontConfiguration
            field.font = fontConfiguration.makeFont()
        }
        if field.text != text { field.text = text }
        if field.keyboardType != keyboardType { field.keyboardType = keyboardType; field.reloadInputViews() }
        field.textAlignment = alignment
        field.accessibilityLabel = accessibilityLabel
        // Only drive focus from SwiftUI when it disagrees with UIKit. The change is deferred, so
        // re-read the latest state when it runs.
        if isFocused != field.isFirstResponder {
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak field] in
                guard let field, coordinator.parent.isFocused != field.isFirstResponder else { return }
                if coordinator.parent.isFocused { field.becomeFirstResponder() } else { field.resignFirstResponder() }
            }
        }
    }

    /// Fills the width it is offered (so the whole value area is tappable), and is at least
    /// `minWidth` wide and 44 pt tall. With no finite width offered it hugs its text.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        let font = uiView.font ?? fontConfiguration.makeFont()
        let textWidth = ((uiView.text ?? "") as NSString).size(withAttributes: [.font: font]).width
        let ideal = max(minWidth, ceil(textWidth) + 8)
        let width: CGFloat
        if let offered = proposal.width, offered.isFinite {
            width = max(minWidth, offered)
        } else {
            width = ideal
        }
        // Fixed height, never stretched to the offered height: a real 44 pt tap target.
        return CGSize(width: width, height: max(ceil(font.lineHeight) + 8, 44))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DecimalTextField
        var appliedFont: FontConfiguration

        init(_ parent: DecimalTextField) {
            self.parent = parent
            appliedFont = parent.fontConfiguration
        }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
            // Select the whole number so the first keystroke replaces it instead of inserting into
            // it. Deferred, because UIKit places the cursor at the tap point after this callback.
            DispatchQueue.main.async { [weak textField] in
                guard let textField, textField.isFirstResponder else { return }
                textField.selectedTextRange = textField.textRange(
                    from: textField.beginningOfDocument, to: textField.endOfDocument)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}
