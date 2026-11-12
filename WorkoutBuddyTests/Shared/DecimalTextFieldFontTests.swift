import Testing
import UIKit
@testable import WorkoutBuddy

struct DecimalTextFieldFontTests {
    private func traits(_ category: UIContentSizeCategory) -> UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: category)
    }

    @Test func defaultConfigurationIsTheBodyFont() {
        let font = DecimalTextField.FontConfiguration.body.makeFont()
        #expect(font == UIFont.preferredFont(forTextStyle: .body))
        #expect(DecimalTextField.FontConfiguration() == .body)
    }

    @Test func largeValueScalesFromItsBaseSizeUpToItsMaximum() {
        let config = DecimalTextField.FontConfiguration.largeValue
        #expect(config.makeFont(compatibleWith: traits(.large)).pointSize == 48)
        #expect(config.makeFont(compatibleWith: traits(.accessibilityExtraExtraExtraLarge)).pointSize == 72)
        let bigger = config.makeFont(compatibleWith: traits(.extraExtraExtraLarge)).pointSize
        #expect(bigger > 48 && bigger < 72)
    }

    @Test func largeValueIsRoundedWithMonospacedDigits() {
        let font = DecimalTextField.FontConfiguration.largeValue.makeFont(compatibleWith: traits(.large))
        try? "\(font.fontName)\n\(font.fontDescriptor.fontAttributes)".write(toFile: "/private/tmp/claude-501/-Volumes-AP-Projects-WorkoutBuddy/929e0f58-6534-47ae-8115-f206d2ea0bb8/scratchpad/font.txt", atomically: true, encoding: .utf8)
    }
}
