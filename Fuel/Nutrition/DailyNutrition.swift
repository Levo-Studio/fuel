import Foundation

// MARK: - Daily nutrition

/// Sums over a day's entries. Pure, and the only place a total is worked out.
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

    /// The entries of one calendar day, in the order they were logged.
    static func entries(
        _ entries: [NutritionEntry],
        on day: Date,
        calendar: Calendar = .current
    ) -> [NutritionEntry] {
        entries
            .filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
            .sorted { $0.loggedAt < $1.loggedAt }
    }
}
