import Foundation

// MARK: - Daily nutrition

/// Sums over a day's entries. Pure, and the only place a day's total is worked
/// out.
///
/// **A plain sum, in both figures, and that is the whole of the rule at this
/// level.** An entry's own two figures were settled by `MealArithmetic` when it
/// was priced or last changed, so a day is consistent with its meals exactly
/// because nothing here recomputes either one. Read that type before assuming
/// the day's kilocalories should equal `4·protein + 4·carbs + 9·fat` of the
/// day's macros: energy is the food table's published figure and is never
/// derived from the three macros, and it says by how much and why.
nonisolated enum DailyNutrition {

    /// Everything the header of the Today screen needs, in both modes.
    static func totals(of entries: [NutritionEntry]) -> DailyTotals {
        entries.reduce(into: DailyTotals.zero) { totals, entry in
            totals.kilocalories += entry.kilocalories
            totals.macros += entry.macros
        }
    }

    /// The calories of one group, printed beside its heading (`420 kcal`).
    static func kilocalories(of entries: [NutritionEntry]) -> Int {
        entries.reduce(0) { $0 + $1.kilocalories }
    }
}
