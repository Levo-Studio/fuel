import Testing

@testable import Fuel

// MARK: - One row's figure

/// The composition rule inside a single row: two steps, and the row is worth no
/// more than the weaker of the ones that answered.
@Suite("Item confidence")
struct ItemConfidenceTests {

    @Test("A row with one answered step is worth that answer")
    func singleStep() {
        #expect(ItemConfidence(estimatePercent: 80).percent == 80)
        #expect(ItemConfidence(groundingPercent: 45).percent == 45)
    }

    /// The case the minimum exists for. An average would say 65 here and read
    /// as a middling row, when in fact half the work behind it is a coin toss.
    @Test("A confident identification does not paper over a doubtful match")
    func weakestStepWins() {
        let row = ItemConfidence(estimatePercent: 95, groundingPercent: 35)

        #expect(row.percent == 35)
    }

    /// And symmetrically, so neither step is privileged over the other.
    @Test("A confident match does not paper over a doubtful identification")
    func weakestStepWinsEitherWay() {
        let row = ItemConfidence(estimatePercent: 30, groundingPercent: 90)

        #expect(row.percent == 30)
    }

    @Test("A row nobody answered for has no figure")
    func noStepAnswered() {
        #expect(ItemConfidence().percent == nil)
    }

    /// An unanswered step is the absence of an opinion, not a zero — a row that
    /// was never grounded must not read as certainly wrong.
    @Test("An unanswered step is not a zero")
    func unansweredIsNotZero() {
        #expect(ItemConfidence(estimatePercent: 90, groundingPercent: nil).percent == 90)
    }

    /// A blob written by another build arrives unchecked. Clamping 150 would
    /// turn a value nobody can read into the most confident figure on the scale.
    @Test("A stored value off the scale is discarded, not clamped")
    func offScaleIsDiscarded() {
        #expect(ItemConfidence(estimatePercent: 150).percent == nil)
        #expect(ItemConfidence(estimatePercent: -1).percent == nil)
        #expect(ItemConfidence(estimatePercent: 150, groundingPercent: 40).percent == 40)
    }

    @Test("Both ends of the scale are readable values")
    func boundsAreValid() {
        #expect(ItemConfidence(estimatePercent: 0).percent == 0)
        #expect(ItemConfidence(estimatePercent: 100).percent == 100)
    }
}

// MARK: - The meal's figure

/// The derivation drawn beside a meal's kilocalories. Pure arithmetic over
/// plain values: no store, no container, no simulator.
@Suite("Estimate confidence")
struct EstimateConfidenceTests {

    @Test("One item's figure is the meal's figure")
    func singleItem() {
        #expect(EstimateConfidence.percent(of: [ItemConfidence(estimatePercent: 72)]) == 72)
    }

    /// The owner's ruling: the plain average, not the minimum. Four sure things
    /// and one guess is a mostly-known plate and reads as one.
    @Test("A meal with mixed confidences is the average of its items")
    func mixedConfidences() {
        let items = [
            ItemConfidence(estimatePercent: 90),
            ItemConfidence(estimatePercent: 90),
            ItemConfidence(estimatePercent: 90),
            ItemConfidence(estimatePercent: 90),
            ItemConfidence(estimatePercent: 30)
        ]

        // 390 / 5 = 78, and not the 30 a minimum would give.
        #expect(EstimateConfidence.percent(of: items) == 78)
    }

    /// Not weighted by kilocalories, which is the same list priced differently:
    /// the figure must not move when a row's price changes and the model's
    /// certainty does not.
    @Test("A meal's figure does not depend on how its calories are split")
    func unweightedByCalories() {
        let items = [ItemConfidence(estimatePercent: 100), ItemConfidence(estimatePercent: 50)]

        #expect(EstimateConfidence.percent(of: items) == 75)
    }

    @Test("A half is rounded up to a whole percent")
    func roundsToWhole() {
        let items = [ItemConfidence(estimatePercent: 80), ItemConfidence(estimatePercent: 85)]

        // 82.5, and the drawn figure is a whole number.
        #expect(EstimateConfidence.percent(of: items) == 83)
    }

    /// A row the user typed themselves was never estimated. Counting it as zero
    /// would report the model as less sure than it said it was.
    @Test("A row with no figure is left out rather than counted as zero")
    func unansweredRowsAreExcluded() {
        let items: [ItemConfidence?] = [
            ItemConfidence(estimatePercent: 80),
            ItemConfidence(),
            nil
        ]

        #expect(EstimateConfidence.percent(of: items) == 80)
    }

    /// A meal logged before the field existed, and a meal repeated from Recent
    /// where nothing was estimated afresh. Both draw nothing.
    @Test("A meal where nothing was answered has no figure")
    func noFigureAtAll() {
        #expect(EstimateConfidence.percent(of: []) == nil)
        #expect(EstimateConfidence.percent(of: [nil, nil]) == nil)
        #expect(EstimateConfidence.percent(of: [ItemConfidence()]) == nil)
    }

    /// The grounding step is carried through the average as readily as the
    /// estimate step, so the figure needs no reshaping when that pass exists.
    @Test("Both steps reach the meal's average")
    func bothStepsCount() {
        let items = [
            ItemConfidence(estimatePercent: 90, groundingPercent: 70),
            ItemConfidence(estimatePercent: 60, groundingPercent: 80)
        ]

        // The rows are worth 70 and 60; the meal is their average.
        #expect(EstimateConfidence.percent(of: items) == 65)
    }
}
