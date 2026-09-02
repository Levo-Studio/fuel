import Foundation
import Testing

@testable import Fuel

// MARK: - Totals

@Suite("Daily totals")
struct DailyTotalsTests {

    @Test("an empty day totals zero")
    func emptyDay() {
        #expect(DailyNutrition.totals(of: []) == .zero)
    }

    @Test("calories and macros sum over the day")
    func summed() {
        let day = [
            entry(at: at(8, 14), kilocalories: 420, macros: MacroTotals(protein: 30, carbs: 55, fat: 9)),
            entry(at: at(12, 40), kilocalories: 680, macros: MacroTotals(protein: 52, carbs: 78, fat: 21)),
            entry(at: at(15, 5), kilocalories: 110, macros: MacroTotals(protein: 2, carbs: 24, fat: 1)),
            entry(at: at(19, 20), kilocalories: 430, macros: MacroTotals(protein: 34, carbs: 15, fat: 17)),
        ]
        let totals = DailyNutrition.totals(of: day)
        #expect(totals.kilocalories == 1640)
        #expect(totals.macros == MacroTotals(protein: 118, carbs: 172, fat: 48))
    }

    @Test("adding macros is component-wise")
    func macroArithmetic() {
        var totals = MacroTotals(protein: 10, carbs: 20, fat: 5)
        totals += MacroTotals(protein: 1, carbs: 2, fat: 3)
        #expect(totals == MacroTotals(protein: 11, carbs: 22, fat: 8))
        #expect(MacroTotals.zero + totals == totals)
    }

    @Test("a group's calories are the calories of its entries")
    func groupCalories() {
        let group = [
            entry(at: at(8, 0), kilocalories: 240),
            entry(at: at(8, 30), kilocalories: 180),
        ]
        #expect(DailyNutrition.kilocalories(of: group) == 420)
    }

    @Test("only the chosen day counts")
    func dayFilter() {
        let day = [
            entry(at: at(20, 0, day: 0), kilocalories: 500),
            entry(at: at(8, 0, day: 1), kilocalories: 300),
            entry(at: at(9, 0, day: 1), kilocalories: 200),
        ]
        let today = DailyNutrition.entries(day, on: at(12, 0, day: 1), calendar: testCalendar)
        #expect(today.count == 2)
        #expect(DailyNutrition.totals(of: today).kilocalories == 500)
    }
}

// MARK: - Goal versus count-only

@Suite("Goal progress")
struct GoalProgressTests {

    let targets = DailyTargets.default

    @Test("the defaults are the ones onboarding starts from")
    func defaults() {
        #expect(targets.kilocalories == 2400)
        #expect(targets.protein == 160)
        #expect(targets.carbs == 240)
        #expect(targets.fat == 70)
    }

    @Test("the ring fraction is the share of the goal")
    func ringFraction() {
        let progress = GoalProgress(
            totals: DailyTotals(kilocalories: 1200, macros: .zero),
            targets: targets
        )
        #expect(progress.ringFraction == 0.5)
    }

    @Test("the percentage is a whole number")
    func percentage() {
        let progress = GoalProgress(
            totals: DailyTotals(kilocalories: 1640, macros: .zero),
            targets: targets
        )
        #expect(progress.percentage == 68)
    }

    @Test("a day just short of the goal does not read as full")
    func percentageDoesNotRoundUp() {
        let progress = GoalProgress(
            totals: DailyTotals(kilocalories: 2399, macros: .zero),
            targets: targets
        )
        #expect(progress.percentage == 99)
        #expect(progress.ringFraction < 1)
    }

    @Test("going over the goal caps the ring at full")
    func overGoal() {
        let progress = GoalProgress(
            totals: DailyTotals(kilocalories: 3000, macros: .zero),
            targets: targets
        )
        #expect(progress.ringFraction == 1)
        #expect(progress.percentage == 100)
    }

    @Test("a target of zero has no fraction to draw")
    func zeroTarget() {
        #expect(GoalProgress.fraction(500, of: 0) == 0)
    }

    @Test("the macro bars each measure their own target")
    func macroBars() {
        let progress = GoalProgress(
            totals: DailyTotals(
                kilocalories: 1640,
                macros: MacroTotals(protein: 80, carbs: 240, fat: 105)
            ),
            targets: targets
        )
        #expect(progress.proteinFraction == 0.5)
        #expect(progress.carbFraction == 1)
        #expect(progress.fatFraction == 1)
    }

    @Test("count-only mode has no goal and no ring")
    func countOnly() {
        let mode = CountingMode.countOnly
        #expect(mode.targets == nil)
        #expect(mode.showsRing == false)
        #expect(mode.progress(for: DailyTotals(kilocalories: 1640, macros: .zero)) == nil)
    }

    @Test("goal mode carries its targets and its ring")
    func goalMode() {
        let mode = CountingMode.goal(targets)
        #expect(mode.showsRing)
        let progress = mode.progress(for: DailyTotals(kilocalories: 1200, macros: .zero))
        #expect(progress?.ringFraction == 0.5)
    }
}

// MARK: - The day list

@Suite("Day grouping")
struct DayGroupingTests {

    @Test("groups run breakfast, lunch, snack, dinner rather than by time")
    func groupOrder() {
        let day = [
            entry(at: at(19, 20), label: .dinner),
            entry(at: at(15, 5), label: .snack),
            entry(at: at(8, 14), label: .breakfast),
            entry(at: at(12, 40), label: .lunch),
        ]
        #expect(DayGrouping.groups(of: day).map(\.label) == [.breakfast, .lunch, .snack, .dinner])
    }

    @Test("a group with no entries is not rendered at all")
    func emptyGroupsAreDropped() {
        let day = [
            entry(at: at(8, 14), label: .breakfast),
            entry(at: at(15, 5), label: .snack),
        ]
        let groups = DayGrouping.groups(of: day)
        #expect(groups.map(\.label) == [.breakfast, .snack])
        #expect(groups.allSatisfy { !$0.entries.isEmpty })
    }

    @Test("entries inside a group sort by time")
    func entriesSortByTime() {
        let day = [
            entry(at: at(16, 0), label: .snack, title: "Later"),
            entry(at: at(15, 5), label: .snack, title: "Earlier"),
        ]
        let snacks = DayGrouping.groups(of: day)[0]
        #expect(snacks.entries.map(\.title) == ["Earlier", "Later"])
    }

    @Test("a group carries the calories printed beside its heading")
    func groupTotal() {
        let day = [
            entry(at: at(8, 14), kilocalories: 420, label: .breakfast),
            entry(at: at(12, 40), kilocalories: 680, label: .lunch),
        ]
        #expect(DayGrouping.groups(of: day).map(\.kilocalories) == [420, 680])
    }

    @Test("an empty day has no groups")
    func emptyDay() {
        #expect(DayGrouping.groups(of: []).isEmpty)
    }
}
