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

    /// A space the user cannot see the difference of must not be a space the
    /// scanner sees the difference of. A non-breaking space comes off the iOS
    /// keyboard and off the clipboard; a tab comes out of a spreadsheet.
    @Test(
        "any one whitespace character separates the marker from its weight",
        arguments: [
            "r300\u{00A0}g rice",
            "r300\tg rice",
            "r\u{00A0}300 g rice",
            "r300 g\u{00A0}rice",
            "r300\u{2009}g rice"
        ]
    )
    func whitespaceVariants(_ sentence: String) {
        #expect(RawWeightNotation.isUsed(in: sentence))
    }

    @Test(
        "two separators are two things on the line, not one amount",
        arguments: [
            "r  50g rice",
            "r \u{00A0}50g rice",
            "r50  g rice"
        ]
    )
    func doubleSeparators(_ sentence: String) {
        #expect(!RawWeightNotation.isUsed(in: sentence))
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

    /// The sentence may be in any language, so the units are too.
    ///
    /// These are the ones that used to fall through: a German speaker writes
    /// `Gramm`, shortens it to `gr`, and says `Pfund` where an English speaker
    /// says pound. Missing them is the expensive direction — the estimate is
    /// wrong by a factor of three and nothing on screen says why.
    @Test(
        "a unit is a unit in the language the meal was typed in",
        arguments: [
            "r300 Gramm Reis",
            "r300gr rice",
            "r300 gr Reis",
            "r300grs rice",
            "r300kgs potatoes",
            "r1 Kilo Kartoffeln",
            "r1kilogramm Kartoffeln",
            "r2 kilos of potatoes",
            "r500 Pfund is a lot of beef",
            "r300 grammes de riz",
            "r1 kilogramme de riz",
            "r8 Unzen Steak"
        ]
    )
    func unitsInOtherLanguages(_ sentence: String) {
        #expect(RawWeightNotation.isUsed(in: sentence))
    }

    /// A word that begins like a unit is not one, in any language. The
    /// boundary check is what does this, not the order of the table.
    @Test(
        "a unit has to end where the word ends",
        arguments: [
            "r300gg rice",
            "r300 grammatik",
            "r300 kilometres from here",
            "r300 pounding the dough"
        ]
    )
    func unitPrefixes(_ sentence: String) {
        #expect(!RawWeightNotation.isUsed(in: sentence))
    }

    /// Measures of space stay out even where a dry one would be meaningful,
    /// because the same door lets in the liquids that have no raw form.
    @Test(
        "a measure of volume is not a weight",
        arguments: [
            "r1 cup of rice",
            "r2 tbsp oil",
            "r0.5 l milk",
            "r2 Stück Brot"
        ]
    )
    func volumesAndCounts(_ sentence: String) {
        #expect(!RawWeightNotation.isUsed(in: sentence))
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

// MARK: - Instruction

/// What the contract actually sends once the shorthand has been found.
@Suite("Raw-weight instruction")
struct RawWeightInstructionTests {

    @Test("a sentence using the shorthand carries the convention")
    func conventionIsAppended() {
        let instruction = EstimateContract.textInstruction(for: "r300g rice, 200g chicken")
        #expect(instruction.contains(EstimateContract.rawWeightConvention))
    }

    @Test("a sentence without the shorthand carries none of it")
    func conventionIsWithheld() {
        let instruction = EstimateContract.textInstruction(for: "300g rice, 200g chicken")
        #expect(!instruction.contains(EstimateContract.rawWeightConvention))
        #expect(!instruction.contains("raw"))
    }

    /// The convention goes before the user's own words, like everything else
    /// Fuel has to say — a paragraph after the description would be a
    /// paragraph a typed sentence could imitate.
    @Test("the convention is said before the description begins")
    func conventionPrecedesTheDescription() throws {
        let instruction = EstimateContract.textInstruction(for: "r300g rice")
        let convention = try #require(instruction.range(of: EstimateContract.rawWeightConvention))
        let description = try #require(instruction.range(of: "Description: r300g rice"))
        #expect(convention.upperBound < description.lowerBound)
    }

    @Test("the sentence itself is passed through untouched")
    func descriptionIsUnchanged() {
        #expect(
            EstimateContract.textInstruction(for: "r300g rice")
                .hasSuffix("Description: r300g rice")
        )
    }

    /// The convention names the ambiguous case in the instruction itself, so a
    /// sentence that mixes a raw weight with a count does not get a raw
    /// reading of the count for free.
    @Test("the convention tells the model not to invent a distinction")
    func conventionNamesTheAmbiguousCase() {
        #expect(EstimateContract.rawWeightConvention.contains("r2 eggs"))
        #expect(EstimateContract.rawWeightConvention.contains("Never invent a difference"))
    }

    /// The raw amount is asked for in the item's name and forbidden in the
    /// title, because `RecentMeals` groups repeats by an exact title match and
    /// a weight that varies would split one meal into a row per weighing.
    @Test("the convention keeps the raw amount out of the meal title")
    func conventionProtectsTheTitle() {
        #expect(EstimateContract.rawWeightConvention.contains("Never put it in the meal's title"))
    }

    /// The examples the instruction shows.
    ///
    /// Held here rather than written into each test below, because the two
    /// things asserted about them are a pair: the model has to be shown them,
    /// and the device has to accept them.
    ///
    /// `nonisolated` because a `@Test`'s argument list is evaluated outside
    /// the actor the suite is on, and everything in this repository is on the
    /// main actor unless it says otherwise.
    private nonisolated static let examples = ["r300g", "r 1.5 kg", "r8oz", "r300 Gramm"]

    /// **The invariant worth keeping.** Every example the model is shown must
    /// be a shape the scanner accepts, or the model is being taught a notation
    /// that never reaches it — the user types the form they were shown, the
    /// device declines to send the convention, and the estimate comes back
    /// silently wrong with a sentence that looks exactly right.
    @Test("every example shown to the model is one the scanner accepts", arguments: examples)
    func examplesAreShapesTheScannerAccepts(_ example: String) {
        #expect(EstimateContract.rawWeightConvention.contains(example))
        #expect(RawWeightNotation.isUsed(in: example))
    }

    /// The scanner reads the unit in more than one language, so the examples
    /// do too. A list of English shapes would teach a narrower rule than the
    /// device accepts, and the person most likely to weigh their rice is the
    /// one who writes `Gramm`.
    @Test("the examples are not all English")
    func examplesAreNotAllEnglish() {
        #expect(EstimateContract.rawWeightConvention.contains("r300 Gramm"))
        #expect(RawWeightNotation.isUsed(in: "r300 Gramm Reis"))
    }
}

// MARK: - Amount field

/// How the `amount` field is read once the instruction has put the word `raw`
/// in front of the model.
@Suite("Stated amounts")
struct StatedAmountTests {

    private static func reply(amount: String) -> String {
        """
        {"title":"Rice","kilocalories":330,"protein_g":7,"carbs_g":73,"fat_g":1,\
        "items":[{"name":"Rice (raw 100 g)","kilocalories":330,\
        "amount":\(amount)}]}
        """
    }

    private static func note(amount: String) throws -> RecognisedItem.Note {
        let estimate = try EstimateContract.estimate(from: reply(amount: amount), mode: .text)
        return try #require(estimate.items.first).note
    }

    /// The regression the instruction would otherwise have introduced: a model
    /// that answers `raw` has been told the amount more precisely than
    /// `recognised` ever said it, and reading that as an estimate would put
    /// the least guessed row on the screen under the word for guessing.
    @Test(
        "a stated amount stays stated, however the model spells it",
        arguments: [
            "\"recognised\"",
            "\"recognized\"",
            "\"Recognised\"",
            "\" recognised \"",
            "\"raw\"",
            "\"RAW\"",
            "\"raw weight\"",
            "\"raw_weight\""
        ]
    )
    func statedAmounts(_ amount: String) throws {
        #expect(try Self.note(amount: amount) == .text(amount: .recognised))
    }

    @Test(
        "anything that does not say the amount was given reads as estimated",
        arguments: [
            "\"estimated\"",
            "\"guessed\"",
            "\"\"",
            "null"
        ]
    )
    func unstatedAmounts(_ amount: String) throws {
        #expect(try Self.note(amount: amount) == .text(amount: .estimated))
    }
}
