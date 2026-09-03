import Foundation
import Testing

@testable import Fuel

// MARK: - Notation

/// What the raw-weight shorthand is, written as the shapes it does and does
/// not match.
///
/// The rule is pure and takes a string, so there is no excuse for a thin
/// suite: every shape the scanner is meant to accept is listed, and so is
/// every near miss it is meant to leave alone. The near misses are the half
/// that matters — a marker that fires on the `r` in `burger` would attach a
/// paragraph about raw weights to meals that never mentioned one.
@Suite("Raw-weight notation")
struct RawWeightNotationTests {

    // MARK: - Accepted

    @Test(
        "a leading r on a weight is the raw marker, however it is spaced",
        arguments: [
            "r50g rice",
            "r50 g rice",
            "r 50g rice",
            "r 50 g rice"
        ]
    )
    func spacingVariants(_ sentence: String) {
        #expect(RawWeightNotation.isUsed(in: sentence))
    }

    @Test(
        "the marker and its unit are read in any case",
        arguments: [
            "R80g oats",
            "r80G oats",
            "R80G oats",
            "R 1.5 KG of potatoes"
        ]
    )
    func casing(_ sentence: String) {
        #expect(RawWeightNotation.isUsed(in: sentence))
    }

    @Test(
        "a fraction is a weight, with either separator",
        arguments: [
            "r1.5kg pasta",
            "r1,5 kg pasta",
            "r0.25 lb mince"
        ]
    )
    func fractions(_ sentence: String) {
        #expect(RawWeightNotation.isUsed(in: sentence))
    }

    @Test(
        "every mass unit a person types is a mass unit",
        arguments: [
            "r50g oats",
            "r50 grams of oats",
            "r1kg chicken",
            "r2 kilograms of chicken",
            "r8oz steak",
            "r8 ounces of steak",
            "r2lb beef",
            "r2 lbs beef",
            "r2 pounds of beef"
        ]
    )
    func units(_ sentence: String) {
        #expect(RawWeightNotation.isUsed(in: sentence))
    }

    @Test(
        "the marker is found wherever in the sentence it was typed",
        arguments: [
            "r300g rice",
            "chicken breast and r300g rice",
            "chicken, r300g rice, broccoli",
            "rice r300g"
        ]
    )
    func position(_ sentence: String) {
        #expect(RawWeightNotation.isUsed(in: sentence))
    }

    @Test("a full stop after the unit still ends a weight")
    func trailingPunctuation() {
        #expect(RawWeightNotation.isUsed(in: "Dinner was r300g rice."))
    }

    // MARK: - Rejected

    @Test(
        "a bare weight is an amount as eaten and carries no marker",
        arguments: [
            "300g rice",
            "300 g rice",
            "two eggs and 50 g of oats"
        ]
    )
    func bareWeights(_ sentence: String) {
        #expect(!RawWeightNotation.isUsed(in: sentence))
    }

    @Test(
        "an r inside a word is a letter, not a marker",
        arguments: [
            "burger 200g",
            "Sugar 5 g",
            "butter 10 g",
            "for 2 kg of potatoes"
        ]
    )
    func markerInsideAWord(_ sentence: String) {
        #expect(!RawWeightNotation.isUsed(in: sentence))
    }

    @Test(
        "the marker needs a number and a unit behind it",
        arguments: [
            "r rice",
            "r50 rice",
            "r50",
            "r",
            "r1.kg pasta",
            "r  50g rice",
            "r50 grammar"
        ]
    )
    func incompleteMarkers(_ sentence: String) {
        #expect(!RawWeightNotation.isUsed(in: sentence))
    }

    @Test("a digit before the r is not a word boundary")
    func markerAfterADigit() {
        #expect(!RawWeightNotation.isUsed(in: "3r50g"))
    }

    @Test("an empty sentence uses no shorthand")
    func empty() {
        #expect(!RawWeightNotation.isUsed(in: ""))
    }

    // MARK: - Ambiguity

    /// The case the convention deliberately does not cover.
    ///
    /// A count is not a weight, and a raw egg is still one egg. The scanner
    /// says no here so that the instruction is never sent for a sentence like
    /// this one, and the model is never nudged into inventing a raw-versus-
    /// cooked difference for something that has none.
    @Test(
        "a count is not a weight, marker or no marker",
        arguments: [
            "r2 eggs",
            "2 eggs",
            "r1 apple",
            "r3 slices of bread"
        ]
    )
    func counts(_ sentence: String) {
        #expect(!RawWeightNotation.isUsed(in: sentence))
    }

    /// Volume is left out for the same reason a count is: warming a liquid
    /// does not change what is in it, so there is no raw amount to state.
    @Test(
        "a volume has no raw and cooked to tell apart",
        arguments: [
            "r200ml milk",
            "r200 ml milk",
            "r0.5l milk"
        ]
    )
    func volumes(_ sentence: String) {
        #expect(!RawWeightNotation.isUsed(in: sentence))
    }
}
