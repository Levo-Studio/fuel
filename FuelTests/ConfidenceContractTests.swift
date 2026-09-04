import Testing

@testable import Fuel

// MARK: - Reading a confidence off the wire

/// What `confidence_pct` is allowed to be. The field is a third party's to
/// write, so every one of these is a reply a provider can actually send.
@Suite("Confidence parsing")
struct ConfidencePercentParsingTests {

    @Test("A whole percent is read as written")
    func wholePercent() {
        #expect(EstimateContract.confidencePercent(80) == 80)
        #expect(EstimateContract.confidencePercent(0) == 0)
        #expect(EstimateContract.confidencePercent(100) == 100)
    }

    @Test("A missing figure is no figure")
    func missing() {
        #expect(EstimateContract.confidencePercent(nil) == nil)
    }

    @Test("A figure off the scale is no figure")
    func outOfRange() {
        #expect(EstimateContract.confidencePercent(101) == nil)
        #expect(EstimateContract.confidencePercent(-1) == nil)
        #expect(EstimateContract.confidencePercent(1000) == nil)
    }

    /// `1e300` is a finite `Double` a provider can put on the wire, and the
    /// plain `Int(_:)` conversion traps on it — the trap `LenientInt` documents
    /// and this reader avoids the same way.
    @Test("A figure too large to be an integer is no figure, and no crash")
    func hugeNumber() {
        #expect(EstimateContract.confidencePercent(1e300) == nil)
        #expect(EstimateContract.confidencePercent(-1e300) == nil)
    }

    @Test("An infinity is no figure")
    func notFinite() {
        #expect(EstimateContract.confidencePercent(.infinity) == nil)
        #expect(EstimateContract.confidencePercent(.nan) == nil)
    }

    /// The case the prompt rules out in as many words and the reader still has
    /// to survive: `0.8` read literally rounds to `1`, which would draw
    /// `1% ACC` over an estimate the model was almost sure of.
    @Test("A fraction on the nought-to-one scale is refused, not rescaled")
    func fractionIsRefused() {
        #expect(EstimateContract.confidencePercent(0.8) == nil)
        #expect(EstimateContract.confidencePercent(0.35) == nil)
        #expect(EstimateContract.confidencePercent(0.999) == nil)
    }

    /// A model asked for a whole number will occasionally write `85.0`, which
    /// is the same value differently spelled, and `85.4` is rounding rather
    /// than a scale error.
    @Test("A percentage written with a fraction is rounded")
    func roundsInRange() {
        #expect(EstimateContract.confidencePercent(85.0) == 85)
        #expect(EstimateContract.confidencePercent(85.4) == 85)
        #expect(EstimateContract.confidencePercent(85.5) == 86)
    }
}

// MARK: - A reply carrying confidences

/// The whole path from a provider's bytes to the meal's figure. These use the
/// contract directly rather than a transport: the question is what the JSON
/// means, not how it arrived.
@Suite("Confidence in a reply")
struct ConfidenceInReplyTests {

    private func reply(_ items: String) -> String {
        """
        {"title":"Salmon with polenta","kilocalories":460,"protein_g":34,\
        "carbs_g":28,"fat_g":23,"items":[\(items)]}
        """
    }

    @Test("A photo reply's confidences reach the meal's figure")
    func photoReply() throws {
        let json = reply(
            """
            {"name":"Salmon","kilocalories":240,"grams":150,\
            "confidence":"confident","confidence_pct":90,"amount":"estimated"},\
            {"name":"Spinach","kilocalories":70,"grams":90,\
            "confidence":"unsure","confidence_pct":40,"amount":"estimated"}
            """
        )

        let estimate = try EstimateContract.estimate(from: json, mode: .photo)

        #expect(estimate.items[0].confidence?.estimatePercent == 90)
        #expect(estimate.items[1].confidence?.estimatePercent == 40)
        #expect(estimate.confidencePercent == 65)
    }

    /// The gap this feature exists to close: a typed meal had no confidence of
    /// any kind before, and the field is asked for in both log modes.
    @Test("A text reply carries a confidence too")
    func textReply() throws {
        let json = reply(
            """
            {"name":"2 eggs","kilocalories":158,"grams":120,\
            "confidence_pct":95,"amount":"recognised"}
            """
        )

        let estimate = try EstimateContract.estimate(from: json, mode: .text)

        #expect(estimate.items[0].confidence?.estimatePercent == 95)
        #expect(estimate.confidencePercent == 95)
    }

    /// A model that quoted its numbers has still answered the question.
    @Test("A quoted percentage is still a percentage")
    func quotedPercentage() throws {
        let json = reply(
            """
            {"name":"2 eggs","kilocalories":158,"grams":120,\
            "confidence_pct":"95","amount":"recognised"}
            """
        )

        let estimate = try EstimateContract.estimate(from: json, mode: .text)

        #expect(estimate.confidencePercent == 95)
    }

    /// The word and the number are separate fields and neither stands in for
    /// the other: an unreadable number leaves the drawn word untouched, and a
    /// missing word does not decide the number.
    @Test("An unreadable percentage leaves the confidence word alone")
    func unreadablePercentage() throws {
        let json = reply(
            """
            {"name":"Salmon","kilocalories":240,"grams":150,\
            "confidence":"confident","confidence_pct":"very sure",\
            "amount":"estimated"}
            """
        )

        let estimate = try EstimateContract.estimate(from: json, mode: .photo)

        #expect(estimate.items[0].note == .photo(confidence: .confident, approximateGrams: 150))
        // Absent, not present-and-empty: an `ItemConfidence` with nothing in it
        // would be written into the stored blob and would make
        // `confidence != nil` true of a row no step answered for.
        #expect(estimate.items[0].confidence == nil)
        #expect(estimate.confidencePercent == nil)
    }

    /// Every reply written before this field was asked for, and every model
    /// that ignores it. The estimate is exactly as usable as it was.
    @Test("A reply with no confidences at all still parses, and claims nothing")
    func noConfidences() throws {
        let json = reply(
            """
            {"name":"Salmon","kilocalories":240,"grams":150,\
            "confidence":"confident","amount":"estimated"},\
            {"name":"Polenta","kilocalories":150,"grams":180,\
            "confidence":"confident","amount":"estimated"}
            """
        )

        let estimate = try EstimateContract.estimate(from: json, mode: .photo)

        #expect(estimate.kilocalories == 460)
        #expect(estimate.items.count == 2)
        #expect(estimate.items.allSatisfy { $0.confidence == nil })
        #expect(estimate.confidencePercent == nil)
    }

    /// A row that answered and a row that did not: the meal is the average of
    /// the answers it has, not of the rows it has.
    @Test("A meal with one unanswered row averages only the answered ones")
    func partialConfidences() throws {
        let json = reply(
            """
            {"name":"Salmon","kilocalories":240,"grams":150,\
            "confidence_pct":80,"amount":"estimated"},\
            {"name":"Polenta","kilocalories":150,"grams":180,\
            "amount":"estimated"}
            """
        )

        let estimate = try EstimateContract.estimate(from: json, mode: .photo)

        #expect(estimate.items[0].confidence?.estimatePercent == 80)
        #expect(estimate.items[1].confidence == nil)
        #expect(estimate.confidencePercent == 80)
    }

    /// The `1e300` that traps a plain conversion, arriving as a real reply
    /// rather than as a direct call to the reader.
    @Test("A percentage no integer can hold does not take the estimate with it")
    func hugePercentageInReply() throws {
        let json = reply(
            """
            {"name":"Salmon","kilocalories":240,"grams":150,\
            "confidence_pct":1e300,"amount":"estimated"}
            """
        )

        let estimate = try EstimateContract.estimate(from: json, mode: .photo)

        #expect(estimate.kilocalories == 460)
        #expect(estimate.confidencePercent == nil)
    }

    /// The prompt has to name the field it parses, or the model is never asked
    /// the question this whole feature draws.
    @Test("The system prompt asks for the field the parser reads")
    func promptAsksForTheField() {
        #expect(EstimateContract.systemPrompt.contains("confidence_pct"))
        #expect(EstimateContract.systemPrompt.contains("0 to 100"))
    }
}
