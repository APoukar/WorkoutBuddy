import Foundation
import Testing
@testable import WorkoutBuddy

struct FormattersTests {
    private let us = Locale(identifier: "en_US")
    private let cs = Locale(identifier: "cs_CZ")
    private let enCZ = Locale(identifier: "en_CZ")

    @Test func kgFormatting() {
        #expect(Formatters.kg(22.5, locale: us) == "22.5")
        #expect(Formatters.kg(22.5, locale: cs) == "22,5")
        #expect(Formatters.kg(20, locale: us) == "20")
        #expect(Formatters.kg(20, locale: cs) == "20")
    }

    @Test func weightFormatting() {
        #expect(Formatters.weight(22.5, locale: us) == "22.5\u{00A0}kg")
        #expect(Formatters.weight(22.5, locale: enCZ) == "22,5\u{00A0}kg")
        #expect(Formatters.weight(60, locale: us) == "60\u{00A0}kg")
        #expect(Formatters.weight(0.5, locale: us) == "0.5\u{00A0}kg")
        #expect(Formatters.weight(0, locale: us) == "Bodyweight")
        #expect(Formatters.weight(0, locale: enCZ) == "Bodyweight")
    }

    @Test func spokenWeightFormatting() {
        #expect(Formatters.spokenWeight(22.5, locale: us) == "22.5 kilograms")
        #expect(Formatters.spokenWeight(22.5, locale: enCZ) == "22,5 kilograms")
        #expect(Formatters.spokenWeight(60, locale: us) == "60 kilograms")
        #expect(Formatters.spokenWeight(1, locale: us) == "1 kilogram")
        #expect(Formatters.spokenWeight(0, locale: us) == "bodyweight")
        #expect(Formatters.spokenWeight(0, locale: enCZ) == "bodyweight")
    }

    @Test func restFormatting() {
        #expect(Formatters.rest(seconds: 90, locale: us) == "1:30")
        #expect(Formatters.rest(seconds: 0, locale: us) == "0:00")
        #expect(Formatters.rest(seconds: 600, locale: us) == "10:00")
        #expect(Formatters.rest(seconds: 5, locale: us) == "0:05")
    }

    @Test func spokenDuration() {
        let ninety = Formatters.spokenDuration(seconds: 90, locale: us)
        #expect(ninety.contains("1 minute"))
        #expect(ninety.contains("30 seconds"))
        #expect(Formatters.spokenDuration(seconds: 60, locale: us).contains("1 minute"))
        #expect(!Formatters.spokenDuration(seconds: 60, locale: us).contains("second"))
        #expect(Formatters.spokenDuration(seconds: 45, locale: us).contains("45 seconds"))
        #expect(Formatters.spokenDuration(seconds: 0, locale: us).contains("0 seconds"))
    }

    @Test func parsingAcceptsBothSeparators() {
        #expect(Formatters.parseKg("22.5") == 22.5)
        #expect(Formatters.parseKg("22,5") == 22.5)
        #expect(Formatters.parseKg(" 22,5 ") == 22.5)
        #expect(Formatters.parseKg("20") == 20)
        #expect(Formatters.parseKg("0") == 0)
    }

    @Test func parsingTwoFractionalDigitsRule() {
        #expect(Formatters.parseKg("22.55") == 22.55)
        #expect(Formatters.parseKg("22.555") == nil)
    }

    @Test func parsingAcceptsMidTypingForms() {
        #expect(Formatters.parseKg("22.") == 22)
        #expect(Formatters.parseKg("22,") == 22)
        #expect(Formatters.parseKg(".5") == 0.5)
        #expect(Formatters.parseKg(",5") == 0.5)
    }

    @Test func parsingRejectsInvalid() {
        for text in ["", " ", ".", ",", "abc", "-5", "12abc", "22.5.3", "22,5,3", "1,000", "1.000,5", "5 kg", "1e3", "٢٢"] {
            #expect(Formatters.parseKg(text) == nil, "\(text)")
        }
    }

    @Test func snapping() {
        #expect(Formatters.snappedKg(from: "22.3") == 22.5)
        #expect(Formatters.snappedKg(from: "22.2") == 22)
        #expect(Formatters.snappedKg(from: "22,7") == 22.5)
        #expect(Formatters.snappedKg(from: "22,8") == 23)
        #expect(Formatters.snappedKg(from: "22,55") == 22.5)
        #expect(Formatters.snappedKg(from: "999") == 500)
        #expect(Formatters.snappedKg(from: "x") == nil)
    }

    @Test func committedKg() {
        #expect(Formatters.committedKg(text: "22,3", current: 20) == 22.5)
        #expect(Formatters.committedKg(text: "", current: 20) == 20)
        #expect(Formatters.committedKg(text: "abc", current: 20) == 20)
        #expect(Formatters.committedKg(text: "22.", current: 20) == 22)
        #expect(Formatters.committedKg(text: "600", current: 20) == 500)
        #expect(Formatters.committedKg(text: "22.55", current: 20) == 22.5)
        #expect(Formatters.committedKg(text: "  ", current: 22.5) == 22.5)
    }

    @Test func needsTextRewrite() {
        #expect(!Formatters.needsTextRewrite(text: "", value: 22.5, valueAtFocus: 22.5))
        #expect(!Formatters.needsTextRewrite(text: "30.555", value: 22.5, valueAtFocus: 22.5))
        #expect(Formatters.needsTextRewrite(text: "", value: 25, valueAtFocus: 22.5))
        #expect(!Formatters.needsTextRewrite(text: "25", value: 25, valueAtFocus: 22.5))
        #expect(!Formatters.needsTextRewrite(text: "22.3", value: 22.5, valueAtFocus: 20))
        #expect(Formatters.needsTextRewrite(text: "22.5", value: 25, valueAtFocus: 20))
    }

    /// Covers only the pure keystroke path (not cursor placement, which shows only in a running app).
    /// Mirrors WeightField's per-keystroke handling: committedKg into the binding, then
    /// needsTextRewrite on the resulting value (which must not rewrite the text mid-typing).
    private func typeKeystrokes(_ texts: [String], startingAt start: Double) -> [Double] {
        let valueAtFocus = start
        var kg = start
        var committed: [Double] = []
        for text in texts {
            let value = Formatters.committedKg(text: text, current: valueAtFocus)
            if value != kg { kg = value }
            #expect(!Formatters.needsTextRewrite(text: text, value: kg, valueAtFocus: valueAtFocus), "\(text)")
            committed.append(kg)
        }
        return committed
    }

    @Test func typingCharacterByCharacterCommitsWithoutRewritingText() {
        #expect(typeKeystrokes(["2", "22", "22,", "22,5"], startingAt: 25) == [2, 22, 22, 22.5])
        #expect(typeKeystrokes(["2", "22", "22.", "22.5"], startingAt: 25) == [2, 22, 22, 22.5])
        // Replacing the whole text from empty.
        #expect(typeKeystrokes(["", "2", "22", "22,", "22,5"], startingAt: 25) == [25, 2, 22, 22, 22.5])
    }

    @Test func snapKgEdges() {
        #expect(AppSettings.snapKg(-3) == 0)
        #expect(AppSettings.snapKg(.nan) == 0)
        #expect(AppSettings.snapKg(.infinity) == 0)
        #expect(AppSettings.snapKg(500.4) == 500)
        #expect(AppSettings.snapKg(0.25) == 0.5)
    }
}
