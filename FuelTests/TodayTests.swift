import Foundation
import Testing

@testable import Fuel

// MARK: - Fixtures

/// The day the export draws on both Today screens: 1640 kcal, macros
/// 118 / 172 / 48, and one entry in each of the four groups.
private nonisolated let drawnDay: [NutritionEntry] = [
    entry(
        at: at(8, 14),
        kilocalories: 420,
        macros: MacroTotals(protein: 30, carbs: 55, fat: 9),
        label: .breakfast,
        title: "Oats with skyr",
        source: .photo
    ),
    entry(
        at: at(12, 40),
        kilocalories: 680,
        macros: MacroTotals(protein: 52, carbs: 78, fat: 21),
        label: .lunch,
        title: "Chicken bowl, rice",
        source: .text
    ),
    entry(
        at: at(15, 5),
        kilocalories: 110,
        macros: MacroTotals(protein: 2, carbs: 24, fat: 1),
        label: .snack,
        title: "Espresso, banana",
        source: .recent
    ),
    entry(
        at: at(19, 20),
        kilocalories: 430,
        macros: MacroTotals(protein: 34, carbs: 15, fat: 17),
        label: .dinner,
        title: "Salmon with polenta",
        source: .photo
    ),
]

private nonisolated func presentation(
    _ entries: [NutritionEntry],
    mode: CountingMode
) -> TodayPresentation {
    TodayPresentation(entries: entries, mode: mode, date: at(9, 41))
}

// MARK: - The two shapes

@Suite("Today · the two modes")
struct TodayModeTests {

    @Test("goal mode carries a ring and three bars")
    func goalShape() {
        let today = presentation(drawnDay, mode: .goal(.default))
        #expect(today.summary.goal?.bars.map(\.macro) == [.protein, .carbs, .fat])
        #expect(today.showsRing)
    }

    @Test("count-only mode carries three figures and no ring")
    func countOnlyShape() {
        let today = presentation(drawnDay, mode: .countOnly)
        #expect(today.summary.goal == nil)
        #expect(!today.showsRing)

        guard case .countOnly(let figures) = today.summary else {
            Issue.record("count-only mode did not produce the count-only summary")
            return
        }
        // Screen 06 draws no bars at all — the macros are plain figures, in the
        // day's own grams and in the drawn order.
        #expect(figures.map(\.macro) == [.protein, .carbs, .fat])
        #expect(figures.map(\.grams) == [118, 172, 48])
    }

    @Test("the mode decides the shape, not the entries")
    func sameDayTwoShapes() {
        #expect(presentation(drawnDay, mode: .goal(.default)).showsRing)
        #expect(!presentation(drawnDay, mode: .countOnly).showsRing)
    }

    @Test("the suffix beside the total switches with the mode")
    func suffix() {
        let goal = presentation(drawnDay, mode: .goal(.default))
        let countOnly = presentation(drawnDay, mode: .countOnly)

        #expect(goal.totalSuffix == "/ 2400 kcal")
        #expect(countOnly.totalSuffix == "kcal logged")
    }

    @Test("the suffix follows the goal that was set, not the default")
    func suffixFollowsGoal() {
        let targets = DailyTargets(kilocalories: 1800, protein: 140, carbs: 180, fat: 60)
        #expect(presentation(drawnDay, mode: .goal(targets)).totalSuffix == "/ 1800 kcal")
    }
}

// MARK: - Figures

@Suite("Today · figures")
struct TodayFigureTests {

    @Test("the total is the day's total in both modes")
    func total() {
        #expect(presentation(drawnDay, mode: .goal(.default)).totals.kilocalories == 1640)
        #expect(presentation(drawnDay, mode: .countOnly).totals.kilocalories == 1640)
    }

    @Test("the percentage is the one GoalProgress states")
    func percentageIsPassedThrough() {
        // 696 of 2400 is 29% exactly, and 29% is what truncating the Double
        // share loses. Recomputing the figure in the presentation would
        // reintroduce that, so this is the case that catches it.
        let day = [entry(at: at(8, 0), kilocalories: 696, label: .breakfast)]
        let today = presentation(day, mode: .goal(.default))
        let progress = GoalProgress(totals: DailyTotals(kilocalories: 696, macros: .zero), targets: .default)

        #expect(today.summary.goal?.percentage == progress.percentage)
        #expect(today.summary.goal?.percentage == 29)
    }

    @Test("the ring fraction is the one GoalProgress states, capped at full")
    func ringFraction() {
        let over = [entry(at: at(8, 0), kilocalories: 3000, label: .breakfast)]
        let today = presentation(over, mode: .goal(.default))

        #expect(today.summary.goal?.ringFraction == 1)
        #expect(today.summary.goal?.percentage == 100)
    }

    @Test("a macro bar carries the used figure, the goal and GoalProgress's fraction")
    func bars() {
        let today = presentation(drawnDay, mode: .goal(.default))
        let progress = GoalProgress(
            totals: DailyNutrition.totals(of: drawnDay),
            targets: .default
        )

        #expect(today.summary.goal?.bars.map(\.used) == [118, 172, 48])
        #expect(today.summary.goal?.bars.map(\.goal) == [160, 240, 70])
        #expect(
            today.summary.goal?.bars.map(\.fraction)
                == [progress.proteinFraction, progress.carbFraction, progress.fatFraction]
        )
    }

    @Test("a macro past its goal fills the bar and no further")
    func barsAreCapped() {
        let day = [entry(at: at(8, 0), macros: MacroTotals(protein: 400, carbs: 0, fat: 0), label: .breakfast)]
        let today = presentation(day, mode: .goal(.default))
        #expect(today.summary.goal?.bars.first?.fraction == 1)
        #expect(today.summary.goal?.bars.first?.used == 400)
    }
}

// MARK: - The day list

@Suite("Today · the day list")
struct TodayListTests {

    @Test("the groups run breakfast, lunch, snack, dinner")
    func order() {
        let today = presentation(drawnDay, mode: .goal(.default))
        #expect(today.groups.map(\.label) == [.breakfast, .lunch, .snack, .dinner])
    }

    @Test("a day with only some meals renders only those groups")
    func partiallyEmptyDay() {
        let day = [
            entry(at: at(8, 14), kilocalories: 420, label: .breakfast),
            entry(at: at(19, 20), kilocalories: 430, label: .dinner),
        ]
        let today = presentation(day, mode: .goal(.default))

        #expect(today.groups.map(\.label) == [.breakfast, .dinner])
        #expect(today.groups.map(\.kilocalories) == [420, 430])
        #expect(today.hasEntries)
    }

    @Test("a snack sits above a later dinner, because the order is not the clock")
    func orderIsNotChronological() {
        let day = [
            entry(at: at(19, 20), kilocalories: 430, label: .dinner),
            entry(at: at(15, 5), kilocalories: 110, label: .snack),
        ]
        #expect(presentation(day, mode: .goal(.default)).groups.map(\.label) == [.snack, .dinner])
    }

    @Test("an empty day has no groups and still reads against its goal")
    func emptyDay() {
        let today = presentation([], mode: .goal(.default))

        #expect(today.groups.isEmpty)
        #expect(!today.hasEntries)
        #expect(today.totals == .zero)
        #expect(today.summary.goal?.percentage == 0)
        #expect(today.summary.goal?.ringFraction == 0)
        #expect(today.totalSuffix == "/ 2400 kcal")
    }

    @Test("an empty day in count-only mode shows three zeroes")
    func emptyCountOnlyDay() {
        let today = presentation([], mode: .countOnly)

        #expect(today.groups.isEmpty)
        guard case .countOnly(let figures) = today.summary else {
            Issue.record("count-only mode did not produce the count-only summary")
            return
        }
        #expect(figures.map(\.grams) == [0, 0, 0])
    }
}

// MARK: - Copy and formatting

@Suite("Today · copy")
struct TodayCopyTests {

    @Test("every visible label comes out of the catalog in English")
    func labels() {
        #expect(TodayCopy.title == "Today")
        #expect(TodayCopy.macroName(.protein) == "Protein")
        #expect(TodayCopy.macroName(.carbs) == "Carbs")
        #expect(TodayCopy.macroName(.fat) == "Fat")
        #expect(TodayCopy.mealHeading(.breakfast) == "Breakfast")
        #expect(TodayCopy.mealHeading(.lunch) == "Lunch")
        #expect(TodayCopy.mealHeading(.snack) == "Snack")
        #expect(TodayCopy.mealHeading(.dinner) == "Dinner")
        #expect(TodayCopy.sourceName(.photo) == "Photo")
        #expect(TodayCopy.sourceName(.text) == "Text")
        #expect(TodayCopy.sourceName(.recent) == "Recent")
    }

    @Test("the figures read the way the export draws them")
    func figures() {
        #expect(TodayCopy.percentage(68) == "68%")
        #expect(TodayCopy.macroRatio(used: 118, goal: 160) == "118/160")
        #expect(TodayCopy.macroGrams(118) == "118 g")
        #expect(TodayCopy.groupKilocalories(420) == "420 kcal")
        #expect(TodayCopy.entryMeta(time: "08:14", source: .photo) == "08:14 · Photo")
    }

    @Test("the ring is announced as a share of something")
    func ringLabel() {
        // The drawn label is a bare `68%`, which read aloud on its own names no
        // quantity at all.
        #expect(TodayCopy.ringAccessibilityLabel(68) == "68% of the calorie goal")
    }

    @Test("the day total carries no thousands separator")
    func figureGrouping() {
        #expect(TodayFormat.figure(1640) == "1640")
        #expect(TodayFormat.figure(12_400) == "12400")
    }

    @Test("an entry's time is on the 24-hour clock whatever the locale does")
    func time() {
        #expect(TodayFormat.time(at(8, 14), timeZone: .gmt) == "08:14")
        #expect(TodayFormat.time(at(19, 20), timeZone: .gmt) == "19:20")
    }
}
