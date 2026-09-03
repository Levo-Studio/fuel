import Testing

@testable import Fuel

// MARK: - Reading the amount, not just the marker

/// `RawWeightNotation` used to answer one question — *is the shorthand in this
/// sentence* — and now answers two, from the same scan. These tests are about
/// the second: what the user actually wrote down.
///
/// The first question's tests are next door in `RawWeightNotationTests` and are
/// unchanged, which is the point of extending the scanner rather than writing a
/// second one.
@Suite("Raw-weight amounts")
struct RawWeightAmountTests {

    @Test("A marked weight is the weight, in grams, and says it was marked")
    func markedWeight() {
        let weights = RawWeightNotation.weights(in: "r45g polenta")

        #expect(weights.count == 1)
        #expect(weights.first?.grams == 45)
        #expect(weights.first?.isRaw == true)
    }

    @Test("An unmarked weight is found too, and is not raw")
    func unmarkedWeight() {
        let weights = RawWeightNotation.weights(in: "200 g chicken breast")

        #expect(weights.count == 1)
        #expect(weights.first?.grams == 200)
        #expect(weights.first?.isRaw == false)
    }

    /// The digits of a marked weight must not be read a second time as a
    /// weight of their own.
    @Test("A marked weight is one weight, not two")
    func markedWeightCountedOnce() {
        #expect(RawWeightNotation.weights(in: "r45g polenta").count == 1)
    }

    @Test("Both weights of a two-part sentence are found, in order")
    func twoWeights() {
        let weights = RawWeightNotation.weights(in: "r45g polenta and 200g chicken")

        #expect(weights.map(\.grams) == [45, 200])
        #expect(weights.map(\.isRaw) == [true, false])
    }

    @Test("Every unit converts to grams", arguments: [
        ("1 kg rice", 1000.0),
        ("1.5 kg rice", 1500.0),
        ("1,5 kg rice", 1500.0),
        ("1 kilogram rice", 1000.0),
        ("1 lb beef", 453.592_37),
        ("1 oz cheese", 28.349_523_125),
        ("1 Pfund Mehl", 500.0),
        ("250 Gramm Reis", 250.0),
    ])
    func unitConversion(text: String, grams: Double) {
        #expect(RawWeightNotation.weights(in: text).first?.grams == grams)
    }

    /// Everything the scanner already refused it still refuses, and now it
    /// refuses it as an amount rather than as a marker.
    @Test("What is not a weight yields no weight", arguments: [
        "2 eggs",
        "200 ml milk",
        "50 grammar mistakes",
        "a plate of pasta",
        "r1.kg rice",
    ])
    func notAWeight(text: String) {
        #expect(RawWeightNotation.weights(in: text).isEmpty)
    }
}
