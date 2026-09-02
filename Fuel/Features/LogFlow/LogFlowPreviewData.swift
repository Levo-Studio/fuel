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

    /// A flow backed by an in-memory store holding the meals above.
    ///
    /// `nil` only if SwiftData cannot open a container at all, which is a
    /// broken toolchain rather than a state a preview should try to draw.
    static func model(showing tab: LogFlowTab) -> LogFlowModel? {
        guard let store = try? FuelStore(inMemory: true) else { return nil }

        // An hour apart and descending, so the seeded order is the drawn order
        // once the store hands them back newest first.
        let base = Date()
        for (index, meal) in meals.enumerated() {
            try? store.log(
                title: meal.title,
                kilocalories: meal.kilocalories,
                macros: meal.macros,
                loggedAt: base.addingTimeInterval(TimeInterval(index) * -3_600),
                source: .recent
            )
        }

        let model = LogFlowModel(store: store, selectedTab: tab)
        model.reload()
        return model
    }
}
