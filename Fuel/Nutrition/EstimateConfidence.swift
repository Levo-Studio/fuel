import Foundation

// MARK: - One item's confidence

/// How sure the model is about one line of a breakdown, per step of the work
/// that produced it.
///
/// **Two questions, not one, because two different decisions were made about
/// this row and either of them can be the wrong one.** The estimate says what
/// the food is and how much of it there is; the grounding says which row of the
/// food table that food is — or, where no row fits, whether the per-100 g
/// figures written in its place are realistic. A row can be a confident
/// identification priced against a doubtful match, and it can be a hesitant
/// identification that nevertheless resolved to an unmistakable row. One number
/// covering both would hide whichever of the two went wrong.
///
/// **Both fields are the model's own answer about its own work, and nothing
/// else is ever written into either.** No local score, no match quality, no
/// figure derived on the device. A number here that the model did not state is
/// the one failure this whole type exists to prevent — see `percent`, which
/// answers `nil` rather than substituting anything.
nonisolated struct ItemConfidence: Codable, Hashable, Sendable {

    /// How sure the model was that it identified this food and got its amount
    /// right, as it answered `confidence_pct` in `EstimateContract`.
    ///
    /// `nil` where the model left the field out, answered something that is not
    /// a percentage, or where nobody asked — a row the user typed themselves,
    /// and every row stored before the field existed.
    var estimatePercent: Int?

    /// How sure the model was that this row was priced against the right food:
    /// the right table row where one was matched, and realistic per-100 g
    /// figures where none was and it supplied its own.
    ///
    /// **Nothing writes this yet, and it is `nil` on every item Fuel produces
    /// today.** The pass that would answer it does not exist:
    /// `FoodTableGrounding` matches a name to a CIQUAL row on the device, by a
    /// deterministic token-coverage rule and with no model in the loop, so
    /// there is no model opinion to record. The field is here rather than added
    /// later because an item's confidence is stored inside `FoodEntry.items`
    /// as one `Codable` blob, and widening a bare `Int` into this type
    /// afterwards would fail to decode every row already written.
    ///
    /// It is deliberately **not** inferred from `estimatePercent`. The two
    /// answer different questions, which is the entire reason the figure is
    /// worth showing; a confident identification quietly standing in for an
    /// unasked table match would be the invented number this type refuses to
    /// carry.
    var groundingPercent: Int?

    init(estimatePercent: Int? = nil, groundingPercent: Int? = nil) {
        self.estimatePercent = estimatePercent
        self.groundingPercent = groundingPercent
    }

    // MARK: - The row's single figure

    /// The one figure for this row, or `nil` if no step answered.
    ///
    /// **The lower of the answered steps, and an average would be wrong here.**
    /// The steps are conjunctive: the row is right only if the food was
    /// identified and weighed correctly *and* priced against the right thing.
    /// Averaging 95 and 35 gives 65, which reads as a middling row and hides
    /// that half of the work behind it is a coin toss — a highly confident
    /// weight papering over a doubtful table match, or the reverse. The minimum
    /// is symmetric and says what the row is actually worth: no better than its
    /// weakest answered step.
    ///
    /// **A step that did not answer is not a zero.** An unanswered step is the
    /// absence of an opinion, and treating it as no confidence would report a
    /// figure the model never gave — so only the answered steps are weighed,
    /// and a row where none answered has no figure at all.
    ///
    /// A value outside `0...100` is discarded rather than clamped. The parser
    /// bounds what it writes, but a row decoded from a blob another build wrote
    /// arrives unchecked, and clamping 150 to 100 would turn a value nobody can
    /// read into the most confident figure the scale has.
    var percent: Int? {
        [estimatePercent, groundingPercent]
            .compactMap { $0 }
            .filter { EstimateConfidence.range.contains($0) }
            .min()
    }
}

// MARK: - The meal's figure

/// The accuracy figure drawn beside a meal's kilocalories: how sure the model
/// is of the estimate it produced.
///
/// Pure arithmetic over plain values, like everything else in this folder. It
/// knows nothing about the store, the screens, or which provider answered — it
/// is handed the confidences of a meal's rows and returns the meal's number.
nonisolated enum EstimateConfidence {

    /// The scale the model is asked to answer on, and the only values that are
    /// ever shown or stored. Stated once here so the parser, the row reader and
    /// the tests cannot drift apart about what a percentage is.
    static let range = 0...100

    /// The meal's figure, or `nil` where there is nothing honest to draw.
    ///
    /// **The plain average of the rows that have a figure, which is the
    /// owner's ruling and not a default.** Not the minimum: a meal is not
    /// reduced to its single worst line, and a plate of four certain things and
    /// one guess is genuinely mostly known. Not weighted by kilocalories
    /// either: that would make the figure move when a row's *price* changed
    /// rather than when the model's certainty did, so grounding a single row
    /// against the food table — which changes calories and says nothing about
    /// confidence — would silently rewrite how sure the model is said to have
    /// been.
    ///
    /// **Rows with no figure are left out rather than counted as zero**, for
    /// the reason `ItemConfidence.percent` gives about an unanswered step: a
    /// row the user typed themselves was never estimated, and letting it drag
    /// the average down would report the model as less sure than it said it
    /// was. A meal where no row has a figure has none itself, and the screens
    /// draw nothing — which is the case for every meal logged before this
    /// existed and for every meal repeated from the Recent list, where nothing
    /// was estimated afresh.
    ///
    /// Rounded to the nearest whole percent, because the figure is drawn as a
    /// whole number and a stored fraction nothing can show is a fraction that
    /// only makes two readers disagree.
    static func percent(of confidences: [ItemConfidence?]) -> Int? {
        let answered = confidences.compactMap { $0?.percent }
        guard !answered.isEmpty else {
            return nil
        }
        let mean = Double(answered.reduce(0, +)) / Double(answered.count)
        return Int(mean.rounded())
    }
}
