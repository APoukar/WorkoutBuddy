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

    @Test func parseReps() {
        #expect(Formatters.parseReps("10") == 10)
        #expect(Formatters.parseReps("0") == 0)
        #expect(Formatters.parseReps("007") == 7)
        #expect(Formatters.parseReps(" 12 ") == 12)
        #expect(Formatters.parseReps("") == nil)
        #expect(Formatters.parseReps("  ") == nil)
        #expect(Formatters.parseReps("-5") == nil)
        #expect(Formatters.parseReps("+5") == nil)
        #expect(Formatters.parseReps("1.5") == nil)
        #expect(Formatters.parseReps("1,5") == nil)
        #expect(Formatters.parseReps("1 000") == nil)
        #expect(Formatters.parseReps("abc") == nil)
        #expect(Formatters.parseReps("\u{0661}\u{0662}") == nil)  // Arabic-Indic digits
        #expect(Formatters.parseReps("99999999999999999999") == nil)
    }

    @Test func committedReps() {
        #expect(Formatters.committedReps(text: "12", current: 10) == 12)
        #expect(Formatters.committedReps(text: "", current: 10) == 10)
        #expect(Formatters.committedReps(text: "abc", current: 10) == 10)
        #expect(Formatters.committedReps(text: "-3", current: 10) == 10)
        #expect(Formatters.committedReps(text: "0", current: 10) == 1)
        #expect(Formatters.committedReps(text: "150", current: 10) == 100)
        #expect(Formatters.committedReps(text: "99999999999999999999", current: 10) == 10)
        #expect(Formatters.committedReps(text: "100", current: 10) == 100)
        #expect(Formatters.committedReps(text: "1", current: 10) == 1)
    }

    @Test func needsTextRewriteForKg() {
        func needs(_ text: String, _ value: Double, _ valueAtFocus: Double) -> Bool {
            NumericTextEditing<Double>.needsTextRewrite(
                text: text, value: value, valueAtFocus: valueAtFocus, commit: Formatters.committedKg(text:current:))
        }
        #expect(!needs("", 22.5, 22.5))
        #expect(!needs("30.555", 22.5, 22.5))
        #expect(needs("", 25, 22.5))
        #expect(!needs("25", 25, 22.5))
        #expect(!needs("22.3", 22.5, 20))
        #expect(needs("22.5", 25, 20))
    }

    @Test func needsTextRewriteForReps() {
        func needs(_ text: String, _ value: Int, _ valueAtFocus: Int) -> Bool {
            NumericTextEditing<Int>.needsTextRewrite(
                text: text, value: value, valueAtFocus: valueAtFocus, commit: Formatters.committedReps(text:current:))
        }
        #expect(!needs("0", 1, 1))
        #expect(!needs("150", 100, 100))
        #expect(!needs("", 10, 10))
        #expect(needs("12", 13, 12))
    }

    /// Covers only the pure keystroke path (not cursor placement, which shows only in a running app).
    /// Mirrors WeightField's per-keystroke handling: committedKg into the binding, then
    /// NumericTextEditing.needsTextRewrite on the resulting value (which must not rewrite the text mid-typing).
    private func typeKeystrokes(_ texts: [String], startingAt start: Double) -> [Double] {
        let valueAtFocus = start
        var kg = start
        var committed: [Double] = []
        for text in texts {
            let value = Formatters.committedKg(text: text, current: valueAtFocus)
            if value != kg { kg = value }
            #expect(!NumericTextEditing<Double>.needsTextRewrite(
                text: text, value: kg, valueAtFocus: valueAtFocus, commit: Formatters.committedKg(text:current:)), "\(text)")
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

    // MARK: Workout duration and volume

    @Test func durationFormatting() {
        #expect(Formatters.duration(seconds: 45, locale: us) == "45 sec")
        #expect(Formatters.duration(seconds: 0, locale: us) == "0 sec")
        #expect(Formatters.duration(seconds: -5, locale: us) == "0 sec")
        #expect(Formatters.duration(seconds: 59, locale: us) == "59 sec")
        #expect(Formatters.duration(seconds: 60, locale: us) == "1 min")
        #expect(Formatters.duration(seconds: 12 * 60 + 40, locale: us) == "12 min")
        #expect(Formatters.duration(seconds: 3600, locale: us) == "1 hr")
        #expect(Formatters.duration(seconds: 3900, locale: us) == "1 hr, 5 min")
        #expect(Formatters.duration(seconds: 3600 + 5 * 60 + 59, locale: us) == "1 hr, 5 min")
        #expect(Formatters.duration(seconds: 3599, locale: us) == "59 min")
        #expect(Formatters.duration(seconds: 2 * 3600 + 30 * 60, locale: us) == "2 hr, 30 min")
    }

    @Test func spokenWorkoutDurationFormatting() {
        #expect(Formatters.spokenWorkoutDuration(seconds: 45, locale: us) == "45 seconds")
        #expect(Formatters.spokenWorkoutDuration(seconds: 1, locale: us) == "1 second")
        #expect(Formatters.spokenWorkoutDuration(seconds: 3900, locale: us) == "1 hour, 5 minutes")
        #expect(Formatters.spokenWorkoutDuration(seconds: 60, locale: us) == "1 minute")
        #expect(Formatters.spokenWorkoutDuration(seconds: 7200, locale: us) == "2 hours")
    }

    @Test func volumeFormatting() {
        #expect(Formatters.volume(4250, locale: us) == "4,250\u{00A0}kg")
        #expect(Formatters.volume(4250, locale: enCZ) == "4\u{00A0}250\u{00A0}kg")
        #expect(Formatters.volume(157.5, locale: us) == "157.5\u{00A0}kg")
        #expect(Formatters.volume(157.5, locale: enCZ) == "157,5\u{00A0}kg")
        #expect(Formatters.volume(0, locale: us) == "0\u{00A0}kg")
    }

    @Test func spokenKilogramsFormatting() {
        #expect(Formatters.spokenKilograms(0, locale: us) == "0 kilograms")
        #expect(Formatters.spokenKilograms(1, locale: us) == "1 kilogram")
        #expect(Formatters.spokenKilograms(22.5, locale: us) == "22.5 kilograms")
        #expect(Formatters.spokenKilograms(22.5, locale: enCZ) == "22,5 kilograms")
        #expect(Formatters.spokenKilograms(60, locale: us) == "60 kilograms")
        #expect(Formatters.spokenKilograms(0.5, locale: us) == "0.5 kilograms")
    }

    @Test func spokenVolumeFormatting() {
        #expect(Formatters.spokenVolume(4250, locale: us) == "4,250 kilograms")
        #expect(Formatters.spokenVolume(1, locale: us) == "1 kilogram")
        #expect(Formatters.spokenVolume(0, locale: us) == "0 kilograms")
        #expect(Formatters.spokenVolume(157.5, locale: enCZ) == "157,5 kilograms")
    }

    // MARK: Dates and times

    private var nov14Evening: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague") ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 18, minute: 30)) ?? .now
    }

    @Test func dateTextsFollowLocaleAndTimeZone() {
        let prague = TimeZone(identifier: "Europe/Prague") ?? .gmt
        let enGB = Locale(identifier: "en_GB")
        #expect(Formatters.shortDate(nov14Evening, locale: enGB, timeZone: prague) == "14 Nov 2026")
        #expect(Formatters.shortDate(nov14Evening, locale: Locale(identifier: "en_US"), timeZone: prague) == "Nov 14, 2026")
        #expect(Formatters.dayTitle(nov14Evening, locale: Locale(identifier: "en_CZ"), timeZone: prague) == "Saturday 14 November")
        #expect(Formatters.dayTitle(nov14Evening, locale: Locale(identifier: "en_US"), timeZone: prague) == "Saturday, November 14")
        #expect(Formatters.startTime(nov14Evening, locale: Locale(identifier: "en_CZ"), timeZone: prague) == "18:30")
        #expect(Formatters.sessionStart(nov14Evening, locale: Locale(identifier: "en_CZ"), timeZone: prague)
            .hasPrefix("Saturday 14 November 2026 at 18:30"))
    }

    @Test func dateTextsUseTheGivenTimeZone() {
        // 18:30 in Prague is 17:30 UTC.
        #expect(Formatters.startTime(nov14Evening, locale: Locale(identifier: "en_CZ"), timeZone: .gmt) == "17:30")
    }
}
