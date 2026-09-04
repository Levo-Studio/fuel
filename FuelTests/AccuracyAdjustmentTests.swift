import Foundation
import Testing

@testable import Fuel

// MARK: - Through a chat adjustment

/// The one path the accuracy figure crosses that nothing else in this feature
/// tests: the chat, which changes a meal's amounts without asking the model how
/// sure it is of anything.
///
/// Both behaviours are true today by construction — `MealAdjuster.repricing`
/// copies the row it re-prices, and `MealAdjuster.added` omits the parameter —
/// which is exactly the kind of truth one refactor turns into a lie.
@Suite("Accuracy through a chat adjustment")
struct AccuracyAdjustmentTests {

    private let table: FoodTable

    init() throws {
        table = try FoodTable.bundled()
    }

    /// One grounded row the table knows, carrying a confidence, plus the meal
    /// around it.
    private func meal(percent: Int?) throws -> AdjustableMeal {
        let row = try #require(FoodTableGrounding.bestMatch(for: "Rice", preferring: .prepared, in: table))
        let portion = PortionCalculator.portion(of: row.per100g, grams: 150)

        return AdjustableMeal(
            title: "Rice",
            kilocalories: portion.kilocalories,
            macros: MacroTotals(protein: 20, carbs: 60, fat: 12),
            items: [
                RecognisedItem(
                    name: "Rice",
                    kilocalories: portion.kilocalories,
                    grams: 150,
                    macros: portion.incompleteMacros ? nil : portion.macros,
                    confidence: percent.map { ItemConfidence(estimatePercent: $0) },
                    note: .photo(confidence: .confident, approximateGrams: 150)
                )
            ]
        )
    }

    /// The model's certainty is about what the food is. The user stating a
    /// larger amount does not answer that either way, which is the same reading
    /// `RecognisedItem.setWeight(_:)` gives the word beside it.
    @Test("a re-priced row keeps the confidence it arrived with")
    func repricingKeepsTheConfidence() throws {
        let subject = try meal(percent: 80)
        let intent = MealAdjustmentIntent(
            reply: "Raised the rice.",
            changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)]
        )

        let adjusted = try #require(MealAdjuster.apply(intent, to: subject, table: table))

        #expect(adjusted.items[0].grams == 300)
        #expect(adjusted.items[0].confidence?.estimatePercent == 80)
        #expect(EstimateConfidence.percent(of: adjusted.items.map(\.confidence)) == 80)
    }

    /// The same row with no table behind it, so the other branch of `repricing`
    /// — the one that scales the previous figures — is held to it too.
    @Test("a row scaled without a table keeps its confidence as well")
    func scalingKeepsTheConfidence() throws {
        let subject = try meal(percent: 80)
        let intent = MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)])

        let adjusted = try #require(MealAdjuster.apply(intent, to: subject, table: nil))

        #expect(adjusted.items[0].confidence?.estimatePercent == 80)
    }

    /// `MealChatContract` asks the model what to change, never how sure it is.
    /// A row it adds therefore carries no figure and counts for nothing, rather
    /// than dragging the meal's average to zero.
    @Test("a row the chat added carries no confidence and does not drag the average")
    func additionCarriesNoConfidence() throws {
        let subject = try meal(percent: 80)
        let intent = MealAdjustmentIntent(
            reply: "Added the oil.",
            additions: [MealAdjustmentIntent.Addition(name: "Olive oil", grams: 10)]
        )

        let adjusted = try #require(MealAdjuster.apply(intent, to: subject, table: table))

        #expect(adjusted.items.count == 2)
        #expect(adjusted.items[1].confidence == nil)
        #expect(EstimateConfidence.percent(of: adjusted.items.map(\.confidence)) == 80)
    }

    /// A meal that never had a figure does not gain one from an adjustment: an
    /// amount the user stated is not the model saying how sure it is.
    @Test("an adjustment cannot give a meal a figure it never had")
    func adjustmentInventsNothing() throws {
        let subject = try meal(percent: nil)
        let intent = MealAdjustmentIntent(
            reply: "Raised the rice, added the oil.",
            changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)],
            additions: [MealAdjustmentIntent.Addition(name: "Olive oil", grams: 10)]
        )

        let adjusted = try #require(MealAdjuster.apply(intent, to: subject, table: table))

        #expect(adjusted.items.allSatisfy { $0.confidence == nil })
        #expect(EstimateConfidence.percent(of: adjusted.items.map(\.confidence)) == nil)
    }
}
