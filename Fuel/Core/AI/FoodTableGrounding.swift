import Foundation

// MARK: - Grounding a reply against the food table

/// Corrects a parsed `MealEstimate` against `FoodTable` wherever the two can be
/// matched with confidence, and leaves everything else exactly as the model
/// wrote it.
///
/// **Sits after parsing, not inside it.** `EstimateContract.estimate(from:
/// mode:)` turns a provider's reply into a `MealEstimate`; this type takes
/// that finished value and looks each item up in a table CIQUAL published,
/// which is a different question from reading JSON and is answered without
/// touching how the JSON is read. `EstimateContract.swift` also has an owner
/// mid-diagnosis of an unrelated reliability issue in this same folder at the
/// time this file was written, which is a second, incidental reason to leave
/// its parsing untouched rather than folding this in there.
///
/// **A table hit corrects kilocalories and nothing else.** `RecognisedItem`
/// has no per-item macro breakdown today — only a name and a kilocalorie
/// figure — and the meal's `macros` is a single top-level estimate covering
/// every item at once. Grounding one item's kilocalories against the table
/// while leaving the others as the model wrote them has an exact answer:
/// apply that item's own kilocalorie delta to the meal's total, and nothing
/// else needs to move. Grounding macros the same way does not have an exact
/// answer, because there is no stored per-item macro figure to take a delta
/// against — only a meal-wide number that was never broken down by item in
/// the first place. Approximating one by splitting the meal's macros across
/// items by kilocalorie share would be presenting a guess as a CIQUAL figure,
/// which is the opposite of what this table is for. Carrying a per-item macro
/// breakdown is a real improvement and a real change to `RecognisedItem`'s
/// shape; it is a question for whoever schedules that, not a corner to cut
/// silently inside a kilocalorie fix.
nonisolated enum FoodTableGrounding {

    // MARK: - Entry point

    /// Grounds `estimate` against the table bundled with the app, or returns
    /// it unchanged if the table cannot be opened.
    ///
    /// A missing or corrupt table file is not a reason to fail an estimate the
    /// user already paid for — see `FoodTable.bundled()`'s own `Failure`
    /// cases, neither of which should happen against a file this type ships
    /// with, but "should not happen" is not "cannot happen" on someone's
    /// device.
    ///
    /// This is the one entry point a client's request path is expected to
    /// call, immediately after `EstimateContract.estimate(from:mode:)`:
    ///
    /// ```swift
    /// let estimate = try EstimateContract.estimate(from: replyText, mode: mode)
    /// return FoodTableGrounding.groundAgainstBundledTable(
    ///     estimate,
    ///     mode: mode,
    ///     originalText: mode == .text ? theTextThatWasSent : nil
    /// )
    /// ```
    static func groundAgainstBundledTable(
        _ estimate: MealEstimate,
        mode: AILogMode,
        originalText: String?
    ) -> MealEstimate {
        guard let table = try? FoodTable.bundled() else {
            return estimate
        }
        return ground(estimate, mode: mode, originalText: originalText, table: table)
    }

    /// The same correction, against a table the caller already has open.
    /// Tests use this so a table is opened once for many cases rather than
    /// once per case.
    static func ground(
        _ estimate: MealEstimate,
        mode: AILogMode,
        originalText: String?,
        table: FoodTable
    ) -> MealEstimate {
        let textWeight = soleTextWeight(for: estimate, mode: mode, originalText: originalText)

        var kilocalorieDelta = 0
        let items = estimate.items.map { item -> RecognisedItem in
            guard
                let weight = weight(for: item, mode: mode, soleTextWeight: textWeight),
                let match = bestMatch(for: item.name, preferring: weight.preparation, in: table)
            else {
                return item
            }

            let portion = PortionCalculator.portion(of: match.per100g, grams: weight.grams)
            kilocalorieDelta += portion.kilocalories - item.kilocalories

            var grounded = item
            grounded.kilocalories = portion.kilocalories
            return grounded
        }

        var grounded = estimate
        grounded.items = items
        // The floor matches `PortionCalculator`'s own: a negative meal is not
        // a value that reaches the day's ring regardless of how a delta got
        // there.
        grounded.kilocalories = max(0, estimate.kilocalories + kilocalorieDelta)
        return grounded
    }

    // MARK: - The weight to ground with

    private struct GroundingWeight {
        var grams: Double
        var preparation: FoodPreparation
    }

    /// The one weight a typed sentence names, if the sentence and the reply
    /// agree there is exactly one.
    ///
    /// **This is deliberately narrow, and the narrowness is the safety
    /// rule.** `RawWeightNotation.weights(in:)` returns every quantity a
    /// sentence contains, in reading order, with no link back to which item a
    /// given quantity belongs to — "r45g polenta and 200g chicken" yields two
    /// weights and nothing that says which is which. Guessing that order
    /// matches the model's item order would be right more often than not and
    /// wrong exactly when it mattered, on a food weighed raw, which is the one
    /// case this whole table exists to get right. So grounding only fires
    /// where there is nothing to guess: one item in the reply, one weight in
    /// the sentence. `RawWeightNotationTests` and `RawWeightAmountTests` speak
    /// for the scan itself; this is only the decision to use it or not.
    ///
    /// Multi-item and multi-weight text meals are not a regression from this
    /// — they are exactly as they were before this file existed, which is the
    /// model's own estimate, untouched.
    private static func soleTextWeight(
        for estimate: MealEstimate,
        mode: AILogMode,
        originalText: String?
    ) -> RawWeightNotation.Weight? {
        guard mode == .text, estimate.items.count == 1, let originalText else {
            return nil
        }
        let weights = RawWeightNotation.weights(in: originalText)
        return weights.count == 1 ? weights[0] : nil
    }

    /// The weight to price `item` at, or `nil` if there is none this file
    /// trusts.
    ///
    /// **Photo and text disagree about where the weight comes from, and agree
    /// about what "no marker" means.** A photo item already carries its own
    /// `approximateGrams` — the model's guess at how much is on the plate —
    /// and that guess is the only amount a photo can ever produce, marker or
    /// no marker; there is no sentence to have typed a raw weight into. It is
    /// always looked up against the *prepared* row, because a photographed
    /// meal is food as it will be eaten, which is the same thing a bare typed
    /// weight means: `RawWeightNotation`'s own doc comment states it as "a
    /// weight without it is the amount as eaten." Text uses the marker where
    /// `soleTextWeight` found one and the prepared row otherwise, which is the
    /// identical default stated the other way round.
    private static func weight(
        for item: RecognisedItem,
        mode: AILogMode,
        soleTextWeight: RawWeightNotation.Weight?
    ) -> GroundingWeight? {
        switch mode {
        case .photo:
            guard case .photo(_, let approximateGrams) = item.note, approximateGrams > 0 else {
                return nil
            }
            return GroundingWeight(grams: Double(approximateGrams), preparation: .prepared)

        case .text:
            guard let soleTextWeight else {
                return nil
            }
            return GroundingWeight(
                grams: soleTextWeight.grams,
                preparation: soleTextWeight.isRaw ? .raw : .prepared
            )
        }
    }

    // MARK: - Matching a name to a row

    /// The one row `name` resolves to, or `nil` if nothing is confident
    /// enough to price a meal against.
    ///
    /// **Full coverage or nothing.** `FoodTable.search` ranks its best guess
    /// first, but "best of the candidates" and "actually the same food" are
    /// different claims — its own doc comment is explicit that the ordering
    /// is a shortlist for a model to choose from, not a verdict. Every one of
    /// the query's own words has to appear, as a prefix match, somewhere in
    /// the row's name before this file will act on it unattended: "chicken"
    /// against `Chicken, breast, raw` is a stated food read plainly; "chicken
    /// sandwich" against the same row is not, because the bread and whatever
    /// is on it are not thin air, and pricing the sandwich as if it were
    /// nothing but the chicken would be a wrong number wearing a CIQUAL
    /// citation. A query that fails this simply falls through to the model's
    /// own estimate, which is the safe side of this particular mistake — see
    /// this file's own asymmetry, one paragraph up from here.
    private static func bestMatch(
        for name: String,
        preferring preparation: FoodPreparation,
        in table: FoodTable
    ) -> FoodTableEntry? {
        let query = strippingRawAnnotation(name)
        let queryTokens = Set(FoodTable.tokenise(query))
        guard !queryTokens.isEmpty else {
            return nil
        }

        guard let candidate = table.search(query, preferring: preparation, limit: 1).first else {
            return nil
        }

        let candidateTokens = Set(FoodTable.tokenise(candidate.name))
        let covered = queryTokens.allSatisfy { token in
            candidateTokens.contains { $0.hasPrefix(token) }
        }
        return covered ? candidate : nil
    }

    /// Strips the ` (raw 300 g)` an item name carries when it named a raw
    /// weight, per `EstimateContract.rawWeightConvention`.
    ///
    /// **Not a second reader of the marker.** `RawWeightNotation` already read
    /// the user's own sentence, before this file ever saw it, to decide
    /// `soleTextWeight` above; this is a different string, written by the
    /// model rather than the user, in a shape the system prompt asked it to
    /// use. Without stripping it, the very items this table exists to fix —
    /// "Rice (raw 300 g)" — would query the table for the words "rice raw
    /// 300", which appear in no row CIQUAL publishes, and the annotation that
    /// proves the marker was read would be exactly what stops the lookup from
    /// finding anything.
    private static func strippingRawAnnotation(_ name: String) -> String {
        guard let range = name.range(of: " (raw ", options: .caseInsensitive) else {
            return name
        }
        return String(name[..<range.lowerBound])
    }
}
