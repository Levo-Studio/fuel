import Foundation

// MARK: - Recent meal

/// One row of the Recent list: a meal the user has already eaten, ready to be
/// logged again as it stands.
///
/// It carries no time and no label. Repeating a meal keeps its figures and
/// nothing else — the new entry is logged at the moment it is tapped and gets
/// its label from the day it lands in, which is the nutrition core's job.
nonisolated struct RecentMeal: Identifiable, Hashable, Sendable {

    /// The entry the row was built from, so the list has a stable identity
    /// across a reload. It is not carried into the new entry: logging writes a
    /// new meal, not a second view of the old one.
    let id: UUID

    let title: String
    let kilocalories: Int
    let macros: MacroTotals
}

// MARK: - Building the list

/// Turns a stretch of logged history into the rows screen 13 draws.
///
/// Pure and free of SwiftData, for the same reason the nutrition core is: the
/// list rule is testable in milliseconds without a container.
nonisolated enum RecentMeals {

    /// How many stored entries are read to build the list — a **row count**,
    /// handed to `FuelStore.recentEntries(limit:)` as a `fetchLimit`. It is not
    /// a span of time, and how far back it reaches depends entirely on how
    /// often the user logs: at four meals a day it is about a fortnight.
    ///
    /// Neither of these two is a design value — the export draws five rows
    /// because five fitted the frame, and a static render has nothing to
    /// scroll. They are the read depth and the cap on what is worth scrolling,
    /// and they sit here rather than in `FuelMetrics` because that file holds
    /// what the design drew, and inventing a value into it would make a count
    /// look like a measurement.
    ///
    /// The read is deeper than the cap because the list collapses repeats: a
    /// user who eats the same breakfast every day would otherwise spend most
    /// of the read on one meal.
    static let entriesRead = 60

    /// The most rows the list shows.
    static let maximumRows = 20

    /// The distinct meals in `entries`, keeping the most recent of each.
    ///
    /// `entries` must arrive newest first — `FuelStore.recentEntries(limit:)`
    /// sorts them that way — because the first row for a title is the one that
    /// is kept, and that is what makes it the most recent version of the meal.
    ///
    /// Two meals are the same meal when their titles match **exactly**. The
    /// titles are written by the model, so `Oats with skyr` and `Oats with
    /// Skyr` will occupy two rows, and that is the deliberate choice rather
    /// than an oversight: a looser key merges two rows that print differently,
    /// and the survivor then carries figures the user never saw beside the
    /// title they are reading. Showing a near-duplicate is a smaller lie than
    /// hiding one. If the model turns out to vary its titles often enough for
    /// this to be a nuisance, the fix is to make the titles stable, not to
    /// paper over them here.
    static func list(from entries: [NutritionEntry], limit: Int = maximumRows) -> [RecentMeal] {
        var seenTitles = Set<String>()
        var meals: [RecentMeal] = []

        for entry in entries where seenTitles.insert(entry.title).inserted {
            meals.append(
                RecentMeal(
                    id: entry.id,
                    title: entry.title,
                    kilocalories: entry.kilocalories,
                    macros: entry.macros
                )
            )
            if meals.count == limit { break }
        }

        return meals
    }
}
