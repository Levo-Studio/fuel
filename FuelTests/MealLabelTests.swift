import Foundation
import Testing

@testable import Fuel

// MARK: - The rule

@Suite("Meal label")
struct MealLabelTests {

    let labeler = MealLabeler(calendar: testCalendar)

    /// The day's history, as the rule sees it: the labels already handed out.
    private func label(at moment: Date, claimed: Set<MealLabel> = []) -> MealLabel {
        labeler.label(forEntryAt: moment, claimedLabels: claimed)
    }

    // MARK: - First entry of the day

    @Test("the first entry inside the breakfast window is breakfast")
    func firstBreakfast() {
        #expect(label(at: at(8, 14)) == .breakfast)
    }

    @Test("the first entry inside the lunch window is lunch")
    func firstLunch() {
        #expect(label(at: at(12, 40)) == .lunch)
    }

    @Test("the first entry inside the dinner window is dinner")
    func firstDinner() {
        #expect(label(at: at(19, 20)) == .dinner)
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
        #expect(label(at: moment) == expected)
    }

    // MARK: - The two consequences

    @Test("a second entry inside the breakfast window is a snack, not a second breakfast")
    func secondBreakfastIsSnack() {
        #expect(label(at: at(9, 45), claimed: [.breakfast]) == .snack)
    }

    @Test("an entry at 16:00 on a day with no lunch yet is lunch")
    func lateLunch() {
        #expect(label(at: at(16, 0), claimed: [.breakfast]) == .lunch)
    }

    @Test("an entry at 16:00 after lunch has been handed out is a snack")
    func afternoonSnack() {
        #expect(label(at: at(16, 0), claimed: [.lunch]) == .snack)
    }

    // MARK: - The two ends of the day

    @Test(
        "the small hours claim nothing, whatever the day did",
        arguments: [at(0, 0), at(0, 15), at(2, 0), at(3, 59)]
    )
    func smallHoursAreAlwaysSnacks(moment: Date) {
        #expect(label(at: moment) == .snack)
        #expect(label(at: moment, claimed: [.breakfast, .lunch]) == .snack)
        #expect(label(at: moment, claimed: [.breakfast, .lunch, .dinner]) == .snack)
    }

    @Test(
        "a late evening entry on a day without a dinner is dinner",
        arguments: [at(23, 0), at(23, 30), at(23, 59)]
    )
    func lateEveningStillClaimsDinner(moment: Date) {
        #expect(label(at: moment) == .dinner)
        #expect(label(at: moment, claimed: [.breakfast, .lunch]) == .dinner)
    }

    @Test(
        "a late evening entry once dinner is handed out is a snack",
        arguments: [at(23, 0), at(23, 30), at(23, 59)]
    )
    func lateEveningAfterDinnerIsASnack(moment: Date) {
        #expect(label(at: moment, claimed: [.dinner]) == .snack)
    }

    @Test("everything after dinner is a snack")
    func afterDinner() {
        #expect(label(at: at(21, 30), claimed: [.dinner]) == .snack)
        #expect(label(at: at(22, 59), claimed: [.dinner]) == .snack)
    }

    @Test("a day whose main meals are all taken is a day of nothing but snacks")
    func onlySnacks() {
        let taken: Set<MealLabel> = [.breakfast, .lunch, .dinner]
        let times = [at(2, 0), at(8, 14), at(12, 40), at(16, 0), at(19, 20), at(23, 30)]
        #expect(times.allSatisfy { label(at: $0, claimed: taken) == .snack })
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

    @Test("a day whose only entry is late still has a dinner")
    func lateOnlyEntryIsDinner() {
        let day = [entry(at: at(23, 30))]
        #expect(labeler.relabelling(day).map(\.label) == [.dinner])
    }

    @Test("re-deriving sorts the day before it reasons about it")
    func relabelIsOrderIndependent() {
        let day = [entry(at: at(19, 20)), entry(at: at(8, 14)), entry(at: at(12, 40))]
        let labelled = labeler.relabelling(day)
        #expect(labelled.map(\.label) == [.breakfast, .lunch, .dinner])
    }

    @Test("a back-dated entry takes the meal a later one was holding")
    func backDatedEntryTakesTheMeal() {
        let day = [entry(at: at(19, 0)), entry(at: at(18, 30))]
        #expect(labeler.relabelling(day).map(\.label) == [.dinner, .snack])
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

    @Test("a hand-set meal holds against an earlier entry too")
    func handSetLabelClaimsItsMealAgainstAnEarlierEntry() {
        let day = [
            entry(at: at(19, 0), label: .dinner, userSet: true),
            entry(at: at(18, 30)),
        ]
        #expect(labeler.relabelling(day).map(\.label) == [.snack, .dinner])
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
