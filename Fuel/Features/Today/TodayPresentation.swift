import Foundation

// MARK: - Macro

/// The three macros, in the order both Today screens draw them.
///
/// Written out rather than derived from `MacroTotals`, because the order is a
/// promise to the design: protein, carbs, fat, left to right in count-only mode
/// and top to bottom beside the ring.
nonisolated enum TodayMacro: CaseIterable, Hashable, Sendable {

    case protein
    case carbs
    case fat
}

// MARK: - Goal mode

/// One macro bar: the name, the `used/goal` figure beside it, and how far the
/// accent fill runs.
///
/// The fraction is carried rather than computed here. `GoalProgress` already
/// caps it at full, and a second division at the call site would be a second
/// place for the cap to be forgotten.
nonisolated struct TodayMacroBar: Hashable, Sendable, Identifiable {

    let macro: TodayMacro
    let used: Int
    let goal: Int
    let fraction: Double

    var id: TodayMacro { macro }
}

// MARK: - Count-only mode

/// One macro figure: the name and the grams under it. There is no goal to show
/// against and therefore no fraction.
nonisolated struct TodayMacroFigure: Hashable, Sendable, Identifiable {

    let macro: TodayMacro
    let grams: Int

    var id: TodayMacro { macro }
}

// MARK: - Summary

/// The block between the title and the day list, which is where the two Today
/// screens actually differ.
///
/// The two modes are separate cases rather than one shape with optional
/// members, so a view cannot draw a ring in count-only mode by reading a `nil`
/// as zero. Count-only is not goal mode with the ring hidden — the export draws
/// a different block, with no ring and no bars at all.
nonisolated enum TodaySummary: Hashable, Sendable {

    case goal(Goal)
    case countOnly([TodayMacroFigure])

    /// Everything goal mode adds: the ring, its percentage, and the three bars.
    nonisolated struct Goal: Hashable, Sendable {

        /// Kept whole rather than unpacked, so the ring reads the same
        /// `GoalProgress` the percentage came from.
        let progress: GoalProgress
        let bars: [TodayMacroBar]

        /// Passed straight through. `GoalProgress` truncates rather than
        /// rounds, for the reason written down beside it, and recomputing the
        /// figure here would quietly reintroduce the rounding it avoids.
        var percentage: Int { progress.percentage }

        var ringFraction: Double { progress.ringFraction }

        var goalKilocalories: Int { progress.targets.kilocalories }
    }

    var goal: Goal? {
        switch self {
        case .goal(let goal): goal
        case .countOnly: nil
        }
    }

    /// The ring is drawn in goal mode and nowhere else.
    var showsRing: Bool { goal != nil }
}

// MARK: - Presentation

/// Everything the Today screen draws, worked out once from a day's entries.
///
/// Pure and free of SwiftUI, so both screens can be tested without a simulator.
/// It computes nothing itself: the totals come from `DailyNutrition`, the
/// grouping and its order from `DayGrouping`, and every fraction and the
/// percentage from `GoalProgress`. This type only decides which of the two
/// shapes the mode asks for.
nonisolated struct TodayPresentation: Hashable, Sendable {

    /// The day being shown, for the eyebrow above the title.
    let date: Date

    let totals: DailyTotals

    /// Breakfast, Lunch, Snack, Dinner — in that order, empty groups already
    /// dropped by `DayGrouping`.
    let groups: [MealGroup]

    let summary: TodaySummary

    init(entries: [NutritionEntry], mode: CountingMode, date: Date) {
        self.date = date

        let totals = DailyNutrition.totals(of: entries)
        self.totals = totals
        self.groups = DayGrouping.groups(of: entries)

        if let progress = mode.progress(for: totals) {
            self.summary = .goal(
                TodaySummary.Goal(
                    progress: progress,
                    bars: [
                        TodayMacroBar(
                            macro: .protein,
                            used: totals.macros.protein,
                            goal: progress.targets.protein,
                            fraction: progress.proteinFraction
                        ),
                        TodayMacroBar(
                            macro: .carbs,
                            used: totals.macros.carbs,
                            goal: progress.targets.carbs,
                            fraction: progress.carbFraction
                        ),
                        TodayMacroBar(
                            macro: .fat,
                            used: totals.macros.fat,
                            goal: progress.targets.fat,
                            fraction: progress.fatFraction
                        ),
                    ]
                )
            )
        } else {
            self.summary = .countOnly([
                TodayMacroFigure(macro: .protein, grams: totals.macros.protein),
                TodayMacroFigure(macro: .carbs, grams: totals.macros.carbs),
                TodayMacroFigure(macro: .fat, grams: totals.macros.fat),
            ])
        }
    }

    var showsRing: Bool { summary.showsRing }

    /// A day nobody has logged to yet. The header still stands — a zero total
    /// against a goal is a reading, not an absence — and the list is simply not
    /// there, because `DayGrouping` renders no empty group.
    var hasEntries: Bool { !groups.isEmpty }

    /// The line beside the big total: `/ 2400 kcal` against a goal, and
    /// `kcal logged` when there is none.
    var totalSuffix: String {
        switch summary {
        case .goal(let goal): TodayCopy.goalSuffix(goal.goalKilocalories)
        case .countOnly: TodayCopy.countOnlySuffix
        }
    }
}
