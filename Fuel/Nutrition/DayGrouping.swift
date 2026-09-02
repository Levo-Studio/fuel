import Foundation

// MARK: - Meal group

/// One heading of the Today list plus the entries under it.
nonisolated struct MealGroup: Hashable, Sendable, Identifiable {

    let label: MealLabel
    let entries: [NutritionEntry]

    var id: MealLabel { label }

    /// The figure beside the heading.
    var kilocalories: Int {
        DailyNutrition.kilocalories(of: entries)
    }
}

// MARK: - Grouping

nonisolated enum DayGrouping {

    /// The day list, grouped and ordered the way the design draws it.
    ///
    /// The groups run Breakfast, Lunch, Snack, Dinner — **not** chronologically.
    /// A snack at 15:05 sits above a dinner at 19:20 because the order is the
    /// shape of a day, not a timeline. Inside a group the entries do sort by
    /// time, and a group with no entries is not rendered at all, so an empty
    /// one is dropped here rather than left for a view to hide.
    static func groups(of entries: [NutritionEntry]) -> [MealGroup] {
        MealLabel.dayOrder.compactMap { label in
            let members = entries
                .filter { $0.label == label }
                .sorted { $0.loggedAt < $1.loggedAt }
            guard !members.isEmpty else { return nil }
            return MealGroup(label: label, entries: members)
        }
    }
}
