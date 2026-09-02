import Foundation
import Testing

@testable import Fuel

// MARK: - The rule

@Suite("Meal label")
struct MealLabelTests {

    let labeler = MealLabeler(calendar: testCalendar)

    // MARK: - First entry of the day

    @Test("the first entry inside the breakfast window is breakfast")
    func firstBreakfast() {
        #expect(labeler.label(forEntryAt: at(8, 14), existing: []) == .breakfast)
    }

    @Test("the first entry inside the lunch window is lunch")
    func firstLunch() {
        #expect(labeler.label(forEntryAt: at(12, 40), existing: []) == .lunch)
    }

    @Test("the first entry inside the dinner window is dinner")
    func firstDinner() {
        #expect(labeler.label(forEntryAt: at(19, 20), existing: []) == .dinner)
    }

    @Test(
        "each window claims its meal from its first minute to its last",
        arguments: [
            (at(4, 0), MealLabel.breakfast),
            (at(10, 59), MealLabel.breakfast),
            (at(11, 0), MealLabel.lunch),
            (at(14, 59), MealLabel.lunch),
            (at(18, 0), MealLabel.dinner),
            (at(22, 59), MealLabel.dinner),
        ]
    )
    func windowBounds(moment: Date, expected: MealLabel) {
        #expect(labeler.label(forEntryAt: moment, existing: []) == expected)
    }

    // MARK: - The two consequences

    @Test("a second entry inside the breakfast window is a snack, not a second breakfast")
    func secondBreakfastIsSnack() {
        let breakfast = entry(at: at(7, 30), label: .breakfast)
        #expect(labeler.label(forEntryAt: at(9, 45), existing: [breakfast]) == .snack)
    }

    @Test("an entry at 16:00 on a day with no lunch yet is lunch")
    func lateLunch() {
        let breakfast = entry(at: at(8, 0), label: .breakfast)
        #expect(labeler.label(forEntryAt: at(16, 0), existing: [breakfast]) == .lunch)
    }

    @Test("an entry at 16:00 after lunch has been handed out is a snack")
    func afternoonSnack() {
        let lunch = entry(at: at(12, 30), label: .lunch)
        #expect(labeler.label(forEntryAt: at(16, 0), existing: [lunch]) == .snack)
    }

    // MARK: - Around the edges of the day

    @Test(
        "nothing between 23:00 and 03:59 can claim a meal",
        arguments: [at(23, 0), at(23, 30), at(0, 15), at(2, 0), at(3, 59)]
    )
    func outsideEveryWindow(moment: Date) {
        #expect(labeler.label(forEntryAt: moment, existing: []) == .snack)
    }

    @Test("everything after dinner is a snack")
    func afterDinner() {
        let dinner = entry(at: at(19, 0), label: .dinner)
        #expect(labeler.label(forEntryAt: at(21, 30), existing: [dinner]) == .snack)
        #expect(labeler.label(forEntryAt: at(22, 59), existing: [dinner]) == .snack)
    }

    @Test("a day of nothing but snacks stays a day of nothing but snacks")
    func onlySnacks() {
        let day = [at(0, 30), at(3, 0), at(23, 10), at(23, 59)]
        let labelled = labeler.relabelling(day.map { entry(at: $0) })
        #expect(labelled.allSatisfy { $0.label == .snack })
    }

    @Test("yesterday's meals do not claim today's")
    func mealsAreClaimedPerDay() {
        let yesterday = entry(at: at(8, 0, day: 0), label: .breakfast)
        #expect(labeler.label(forEntryAt: at(8, 0, day: 1), existing: [yesterday]) == .breakfast)
    }

    // MARK: - Re-deriving a day

    @Test("re-deriving a day hands out each main meal once")
    func relabelWholeDay() {
        let day = [
            entry(at: at(8, 14)),
            entry(at: at(9, 30)),
            entry(at: at(12, 40)),
            entry(at: at(15, 5)),
            entry(at: at(19, 20)),
            entry(at: at(21, 0)),
        ]
        #expect(labeler.relabelling(day).map(\.label) == [
            .breakfast, .snack, .lunch, .snack, .dinner, .snack,
        ])
    }

    @Test("re-deriving sorts the day before it reasons about it")
    func relabelIsOrderIndependent() {
        let day = [entry(at: at(19, 20)), entry(at: at(8, 14)), entry(at: at(12, 40))]
        let labelled = labeler.relabelling(day)
        #expect(labelled.map(\.label) == [.breakfast, .lunch, .dinner])
    }

    @Test("a label the user set by hand survives re-deriving")
    func handSetLabelSurvives() {
        let day = [
            entry(at: at(8, 14), label: .snack, userSet: true),
            entry(at: at(12, 40)),
        ]
        let labelled = labeler.relabelling(day)
        #expect(labelled[0].label == .snack)
        #expect(labelled[0].isLabelUserSet)
        #expect(labelled[1].label == .lunch)
    }

    @Test("a hand-set main meal holds that meal against a later entry")
    func handSetLabelClaimsItsMeal() {
        let day = [
            entry(at: at(8, 14), label: .lunch, userSet: true),
            entry(at: at(12, 40)),
        ]
        #expect(labeler.relabelling(day).map(\.label) == [.lunch, .snack])
    }

    // MARK: - The label control

    @Test("the label control cycles forward and wraps")
    func labelCycle() {
        #expect(MealLabel.breakfast.next == .lunch)
        #expect(MealLabel.lunch.next == .snack)
        #expect(MealLabel.snack.next == .dinner)
        #expect(MealLabel.dinner.next == .breakfast)
    }
}
