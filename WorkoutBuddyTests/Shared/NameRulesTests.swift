import Foundation
import Testing
@testable import WorkoutBuddy

struct NameRulesTests {
    private let squat = (id: UUID(), name: "Squat")
    private let bench = (id: UUID(), name: "Bench Press")

    private var active: [(id: UUID, name: String)] { [squat, bench] }

    @Test func emptyAndWhitespaceNamesAreEmpty() {
        #expect(NameRules.check("", against: active) == .empty)
        #expect(NameRules.check("  \n\t ", against: active) == .empty)
    }

    @Test func duplicatesIgnoreCaseAndEdgeWhitespace() {
        #expect(NameRules.check("squat", against: active) == .duplicate)
        #expect(NameRules.check("  BENCH press \n", against: active) == .duplicate)
    }

    @Test func differentOrInnerSpacedNamesAreFine() {
        #expect(NameRules.check("Squats", against: active) == nil)
        #expect(NameRules.check("Bench  Press", against: active) == nil)
        #expect(NameRules.check("Squat", against: []) == nil)
    }

    @Test func excludingSkipsOnlyThatRecord() {
        #expect(NameRules.check("squat", against: active, excluding: squat.id) == nil)
        #expect(NameRules.check("bench press", against: active, excluding: squat.id) == .duplicate)
        #expect(NameRules.check("squat", against: active, excluding: UUID()) == .duplicate)
        #expect(NameRules.check("", against: active, excluding: squat.id) == .empty)
    }

    @Test func visibleErrorWaitsForEditingOnlyForEmpty() {
        #expect(NameRules.visibleError(.empty, hasEdited: false) == nil)
        #expect(NameRules.visibleError(.empty, hasEdited: true) == .empty)
        #expect(NameRules.visibleError(.duplicate, hasEdited: false) == .duplicate)
        #expect(NameRules.visibleError(.duplicate, hasEdited: true) == .duplicate)
        #expect(NameRules.visibleError(nil, hasEdited: true) == nil)
    }
}
