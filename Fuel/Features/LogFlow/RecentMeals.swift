import Foundation

// MARK: - Which list

/// The two lists the Recent tab offers, in the order the switch draws them.
///
/// **Not in the export.** Screen 13 draws one list under one heading, with no
/// switch above it — the favourite is drawn on the result screens, as the
/// `☆ Favourite` / `★ Favourite` control, and nothing in the seventeen screens
/// reads it back. The owner asked for the second list and for the switch, so
/// this is an instructed deviation from a screen that is otherwise reproduced
/// as drawn.
///
/// Recent stays first, and is what the tab opens on: it is the drawn screen,
/// and it is the wider of the two lists, so it is the one that always has
/// something in it.
nonisolated enum RecentList: String, CaseIterable, Identifiable, Hashable, Sendable {

    case recent
    case favourites

    var id: String { rawValue }
}

// MARK: - Boundary

/// A stored meal as the Recent list needs to read it.
///
/// The list has a hand-off value of its own rather than reusing
/// `NutritionEntry`, which deliberately carries neither the line items nor the
/// favourite flag — the nutrition core has no use for either, and what it
/// cannot see it cannot come to depend on. This list needs both: it repeats a
/// meal whole, items included, and one of its two lists is the starred meals.
/// Widening the core's value to serve a feature would give the core two things
/// to ignore; a second value at the same boundary gives it none.
///
/// Pure and free of SwiftData, like `NutritionEntry` and for the same reason:
/// `FuelStore` builds one of these at its boundary, and everything below is
/// testable in milliseconds without a `ModelContainer`.
nonisolated struct RecentEntry: Identifiable, Hashable, Sendable {

    let id: UUID
    let title: String
    let kilocalories: Int
    let macros: MacroTotals
    let isFavourite: Bool
    let items: [RecognisedItem]

    init(
        id: UUID = UUID(),
        title: String,
        kilocalories: Int,
        macros: MacroTotals,
        isFavourite: Bool = false,
        items: [RecognisedItem] = []
    ) {
        self.id = id
        self.title = title
        self.kilocalories = kilocalories
        self.macros = macros
        self.isFavourite = isFavourite
        self.items = items
    }
}

// MARK: - Recent meal

/// One row of the Recent list: a meal the user has already eaten, ready to be
/// logged again as it stands.
///
/// It carries no time and no label — the new entry is logged at the moment it
/// is tapped and gets its label from the day it lands in, which is the
/// nutrition core's job.
///
/// It does carry the breakdown. See `items`.
nonisolated struct RecentMeal: Identifiable, Hashable, Sendable {

    /// The entry the row was built from, so the list has a stable identity
    /// across a reload. It is not carried into the new entry: logging writes a
    /// new meal, not a second view of the old one.
    let id: UUID

    let title: String
    let kilocalories: Int
    let macros: MacroTotals

    /// The meal's own line items, exactly as they were stored.
    ///
    /// A repeat is the same meal it was the first time, and its breakdown was
    /// settled then — by the model, and for any food that resolved against the
    /// table, by `FoodTableGrounding`, which prices an item's kilocalories and
    /// its macros together from one CIQUAL row. Carrying the items through
    /// verbatim is therefore not a shortcut: it reproduces figures the user has
    /// already seen and accepted, at no cost, where a second estimate would
    /// spend a request of theirs and could come back with different numbers for
    /// the same plate.
    ///
    /// That includes each item's `macros` being absent where it was absent —
    /// which is the table-versus-model marking, since a non-`nil` value is a
    /// CIQUAL figure and a `nil` one is the model's own estimate. Filling one
    /// in here would claim a measurement nothing made.
    let items: [RecognisedItem]

    init(
        id: UUID,
        title: String,
        kilocalories: Int,
        macros: MacroTotals,
        items: [RecognisedItem] = []
    ) {
        self.id = id
        self.title = title
        self.kilocalories = kilocalories
        self.macros = macros
        self.items = items
    }
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
    /// and `favouriteEntries(limit:)` both sort them that way — because the
    /// first row for a title is the one that is kept, and that is what makes it
    /// the most recent version of the meal. Its breakdown comes with it: the
    /// row shows one meal's figures, so it repeats that one meal's items rather
    /// than a set pooled from every time the title was logged.
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
    static func list(from entries: [RecentEntry], limit: Int = maximumRows) -> [RecentMeal] {
        var seenTitles = Set<String>()
        var meals: [RecentMeal] = []

        for entry in entries where seenTitles.insert(entry.title).inserted {
            meals.append(
                RecentMeal(
                    id: entry.id,
                    title: entry.title,
                    kilocalories: entry.kilocalories,
                    macros: entry.macros,
                    items: entry.items
                )
            )
            if meals.count == limit { break }
        }

        return meals
    }
}
