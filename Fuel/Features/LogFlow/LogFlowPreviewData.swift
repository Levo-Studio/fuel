import Foundation

// MARK: - Preview data

/// The five meals screen 13 draws, so a preview shows the screen the design
/// shows.
///
/// The figures are the export's; only the words are translated.
/// Main-actor, unlike the rest of this feature's pure values: it builds a
/// `FuelStore`, which is.
enum LogFlowPreviewData {

    static let meals: [RecentMeal] = [
        RecentMeal(id: UUID(), title: "Oats with skyr", kilocalories: 420, macros: MacroTotals(protein: 32, carbs: 48, fat: 9)),
        RecentMeal(id: UUID(), title: "Chicken bowl, rice", kilocalories: 680, macros: MacroTotals(protein: 52, carbs: 74, fat: 16)),
        RecentMeal(id: UUID(), title: "Salmon with polenta", kilocalories: 430, macros: MacroTotals(protein: 32, carbs: 26, fat: 22)),
        RecentMeal(id: UUID(), title: "Protein shake, banana", kilocalories: 280, macros: MacroTotals(protein: 30, carbs: 32, fat: 3)),
        RecentMeal(id: UUID(), title: "Wholegrain bread, avocado", kilocalories: 340, macros: MacroTotals(protein: 11, carbs: 34, fat: 18)),
    ]

    /// The two of them the seeded store stars, so the Favourites list has
    /// something in it. Which two is arbitrary — the export names no favourite
    /// among the five.
    static let favourites = Array(meals.prefix(2))

    /// A flow backed by an in-memory store holding the meals above.
    ///
    /// `nil` only if SwiftData cannot open a container at all, which is a
    /// broken toolchain rather than a state a preview should try to draw.
    static func model(showing tab: LogFlowTab) -> LogFlowModel? {
        guard let store = try? FuelStore(inMemory: true) else { return nil }

        // An hour apart and descending, so the seeded order is the drawn order
        // once the store hands them back newest first.
        //
        // Anchored rather than read from the clock, like `TodayPreviewData`
        // and for the same reason: `FuelStore.log` derives each entry's label
        // from its time of day, so seeding against "now" would hand the five
        // meals whatever labels the hour the preview was opened happens to
        // give them. Local midnight, because the store's calendar is the
        // machine's.
        let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_756_771_200))
            .addingTimeInterval(TimeInterval(19 * 3_600))
        for (index, meal) in meals.enumerated() {
            // Bound rather than discarded: `@discardableResult` does not
            // survive `try?`, which wraps the value in an Optional of its own.
            _ = try? store.log(
                title: meal.title,
                kilocalories: meal.kilocalories,
                macros: meal.macros,
                loggedAt: base.addingTimeInterval(TimeInterval(index) * -3_600),
                source: .recent,
                isFavourite: favourites.contains(meal)
            )
        }

        let model = LogFlowModel(store: store, selectedTab: tab)
        model.reload()
        return model
    }
}
