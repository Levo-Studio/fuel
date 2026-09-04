import Foundation
import Testing

@testable import Fuel

// MARK: - Meal result draft

/// The rules the result screen's draft holds on its own, without a store, a
/// client or a model around it.
///
/// The three screens that draw a draft — the two log modes and the meal detail
/// — each drive these through a request, which is where the ordinary cases are
/// pinned. This suite is for the shapes a scripted reply makes awkward to
/// arrange from that end: a reply with more rows than were asked about, one
/// with fewer, and the arithmetic a removal does without asking anything at
/// all.
@Suite("Meal result draft")
struct MealResultDraftTests {

    // MARK: - Fixtures

    private static func item(_ name: String, _ kilocalories: Int) -> RecognisedItem {
        RecognisedItem(name: name, kilocalories: kilocalories, note: .text(amount: .estimated))
    }

    private static func draft(_ items: [RecognisedItem], kilocalories: Int) -> MealResultDraft {
        MealResultDraft(
            title: "A meal",
            kilocalories: kilocalories,
            macros: MacroTotals(protein: 30, carbs: 40, fat: 10),
            items: items,
            label: .lunch,
            isLabelUserSet: false,
            isFavourite: false
        )
    }

    private static func reply(_ items: [RecognisedItem], kilocalories: Int) -> MealEstimate {
        MealEstimate(
            title: "The corrected rows",
            kilocalories: kilocalories,
            macros: MacroTotals(protein: 5, carbs: 5, fat: 5),
            items: items
        )
    }

    // MARK: - Splicing

    /// Two rewritten rows with an untouched one between them: each takes the
    /// reply row that answers it, and the row in the middle does not move.
    @Test("changed rows take the reply's rows one for one and keep their places")
    func replyRowsLandOneForOne() throws {
        var subject = Self.draft(
            [Self.item("Rice", 200), Self.item("Chicken", 180), Self.item("Salad", 40)],
            kilocalories: 420
        )
        let rice = subject.items[0].id
        let chicken = subject.items[1]
        let salad = subject.items[2].id
        subject.editItem(rice, to: "Rice, 300 g")
        subject.editItem(salad, to: "Salad with dressing")

        let merged = try #require(subject.applying(Self.reply(
            [Self.item("Rice, 300 g", 390), Self.item("Salad with dressing", 90)],
            kilocalories: 480
        )))

        #expect(merged.items.map(\.name) == ["Rice, 300 g", "Chicken", "Salad with dressing"])
        #expect(merged.items[1] == chicken)
        // The chicken's own 180, plus the model's total for the two rows it was
        // asked about.
        #expect(merged.kilocalories == 660)
        #expect(merged.canReanalyse == false)
    }

    /// A model that reads one corrected line as several — "sandwich" as bread,
    /// ham and butter — puts all of them where that line was.
    @Test("a reply that splits one row into several puts them all in its place")
    func replyRowsCanOutnumberTheChangedRows() throws {
        var subject = Self.draft(
            [Self.item("Sandwich", 300), Self.item("Apple", 80)],
            kilocalories: 380
        )
        let sandwich = subject.items[0].id
        subject.editItem(sandwich, to: "Ham sandwich, buttered")

        let merged = try #require(subject.applying(Self.reply(
            [Self.item("Bread, 2 slices", 160), Self.item("Ham", 90), Self.item("Butter", 70)],
            kilocalories: 320
        )))

        #expect(merged.items.map(\.name) == ["Bread, 2 slices", "Ham", "Butter", "Apple"])
        #expect(merged.kilocalories == 400)
    }

    /// And a model that reads two corrected lines as one leaves the surplus row
    /// with nothing to put in it, so it goes.
    @Test("a reply that merges two rows into one drops the row it did not answer")
    func replyRowsCanBeFewerThanTheChangedRows() throws {
        var subject = Self.draft(
            [Self.item("Rice", 200), Self.item("Curry sauce", 150), Self.item("Naan", 250)],
            kilocalories: 600
        )
        let rice = subject.items[0].id
        let sauce = subject.items[1].id
        subject.editItem(rice, to: "Rice with curry sauce")
        subject.editItem(sauce, to: "the same dish")

        let merged = try #require(subject.applying(Self.reply(
            [Self.item("Rice with curry sauce", 420)],
            kilocalories: 420
        )))

        #expect(merged.items.map(\.name) == ["Rice with curry sauce", "Naan"])
        #expect(merged.kilocalories == 670)
    }

    /// A reply with no breakdown cannot answer a question about particular
    /// rows: the rows the user rewrote would vanish with their corrections.
    @Test("a reply with no breakdown cannot be spliced")
    func replyWithoutItemsIsRefused() {
        var subject = Self.draft([Self.item("Rice", 200), Self.item("Chicken", 180)], kilocalories: 380)
        let rice = subject.items[0].id
        subject.editItem(rice, to: "Rice, 300 g")

        #expect(subject.applying(Self.reply([], kilocalories: 400)) == nil)
    }

    /// With every row rewritten there is nothing left to protect, so the same
    /// reply is a whole-meal answer and replaces the whole meal — including the
    /// breakdown it did not give.
    @Test("a reply with no breakdown still replaces a meal whose every row changed")
    func replyWithoutItemsReplacesAFullyChangedMeal() throws {
        var subject = Self.draft([Self.item("Rice", 200), Self.item("Chicken", 180)], kilocalories: 380)
        let rice = subject.items[0].id
        let chicken = subject.items[1].id
        subject.editItem(rice, to: "Rice, 300 g")
        subject.editItem(chicken, to: "Chicken thigh")

        let merged = try #require(subject.applying(Self.reply([], kilocalories: 400)))

        #expect(merged.items.isEmpty)
        #expect(merged.kilocalories == 400)
        #expect(merged.title == "The corrected rows")
        #expect(merged.macros == MacroTotals(protein: 5, carbs: 5, fat: 5))
    }

    // MARK: - Removing

    /// A removal is the change the device carries out in full, so it asks
    /// nothing and leaves nothing pending for the model.
    @Test("a removal takes the row's calories out and offers no re-analysis")
    func removalSubtractsAndAsksNothing() {
        var subject = Self.draft([Self.item("Rice", 200), Self.item("Chicken", 180)], kilocalories: 380)

        let chicken = subject.items[1].id
        subject.removeItem(chicken)

        #expect(subject.items.map(\.name) == ["Rice"])
        #expect(subject.kilocalories == 200)
        #expect(subject.macros == MacroTotals(protein: 30, carbs: 40, fat: 10))
        #expect(subject.hasItemEdits)
        #expect(subject.canReanalyse == false)
        #expect(subject.itemSentence.isEmpty)
    }

    /// The refusal on the last row changes nothing at all, the total included.
    @Test("a removal the draft refuses changes no figure")
    func refusedRemovalChangesNothing() {
        var subject = Self.draft([Self.item("Rice", 200)], kilocalories: 200)

        let rice = subject.items[0].id
        subject.removeItem(rice)
        subject.removeItem(UUID())

        #expect(subject.items.count == 1)
        #expect(subject.kilocalories == 200)
        #expect(subject.hasItemEdits == false)
    }
}
