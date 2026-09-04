import Foundation

// MARK: - Result draft

/// The estimate as the result screen holds it: still editable, not yet an
/// entry.
///
/// A value rather than a `FoodEntry`, because screens 14 and 15 are a
/// decision. The user can cycle the label, mark it a favourite and rewrite the
/// list of items it was made from, and none of that should exist in the
/// database until they tap `Add` — an estimate they walk away from must leave
/// nothing behind.
///
/// One type for both AI log modes. A photo and a typed sentence produce the
/// same thing — a priced meal with a breakdown — and the only difference the
/// two result screens draw is what sits above the label pill, which is the
/// screen's business and not the draft's.
///
/// **It says nothing about where it came from.** There is no photo here, no
/// typed sentence and no flag for whether it has been written down yet: a draft
/// is a meal and its breakdown, and the caller holds the rest. That is what
/// lets one screen serve a scan, a typed entry and — when it is built — a meal
/// that is already in the store.
nonisolated struct MealResultDraft: Equatable, Sendable {

    /// Model-written text. Already capped at 120 characters at the parse
    /// boundary in `Core/AI`, so it is not capped again here — but it is not
    /// assumed short either, and it is rendered as plain text with no markup
    /// path.
    var title: String

    var kilocalories: Int
    var macros: MacroTotals

    /// The advisor line under the macros, in the model's own words, or `nil`
    /// where there is none — which is a state every screen has to draw as it
    /// drew before the line existed. See `MealEstimate.advice`.
    var advice: String?

    /// How sure the model is of this estimate, as a whole percent, or `nil`
    /// where nothing estimated it.
    ///
    /// **Carried rather than computed from `items` on demand**, which looks
    /// like the longer way round and is the only correct one. A meal repeated
    /// from the Recent list holds the breakdown of the meal it repeats,
    /// confidences and all, so a property that averaged the rows every time it
    /// was read would print a percentage on a screen where nothing was
    /// estimated. The figure is derived once, at the moment an estimate
    /// produces one, and then travels with the draft exactly as `advice` does.
    ///
    /// `EstimateConfidence.percent(of:)` is the only thing that ever produces a
    /// value for it, and it is re-derived wherever the estimate is — a whole
    /// replacement and a splice both write it, from the rows that then stand.
    var estimateConfidencePercent: Int?

    var items: [RecognisedItem]

    /// What the meal-label rule gives this moment, until the user says
    /// otherwise.
    var label: MealLabel

    /// `true` once the pill has been tapped. It decides whether the commit
    /// writes the label back over the store's own derivation.
    var isLabelUserSet: Bool

    var isFavourite: Bool

    /// Items whose text is the user's rather than the model's — one they
    /// retyped, or one they added that the model never saw.
    ///
    /// **One set, two readers, and they must not be able to disagree.** The
    /// screen reads it to leave a row's calorie column empty: a figure beside a
    /// line the model has not read yet would be a number Fuel made up. The next
    /// re-analysis reads it to decide what to ask about, which is the same
    /// question asked from the other side — the rows the model has not read yet
    /// are exactly the rows worth spending a request on, and every other row
    /// already carries an answer.
    ///
    /// That second reading is what keeps an untouched row's figures its own.
    /// A re-analysis used to send the whole list and take the whole reply, so a
    /// row nobody had touched came back at whatever the model guessed the
    /// second time — the owner's 300 kcal of pasta returning as 150 after an
    /// edit to a different line. A row that is never in the request cannot come
    /// back different.
    var userWrittenItems: Set<RecognisedItem.ID> = []

    /// Whether the item list has been changed since the estimate produced it.
    ///
    /// **Not the same question as `canReanalyse`, and the difference is a
    /// removal.** This is "has the user done work here", which `‹ Back` reads
    /// to decide whether throwing the screen away needs a confirmation; a row
    /// the user deleted is work whether or not anything is left to ask the
    /// model about. What can be asked is `canReanalyse`, and it is narrower.
    ///
    /// It lives on the draft and not on a log model so that every caller of the
    /// result screen — including one that starts from a stored entry — gets the
    /// same rule without a second copy of it.
    var hasItemEdits: Bool = false

    // MARK: - Editing the breakdown

    /// Throws out a line the model got wrong.
    ///
    /// **Refused on the last remaining row** — see `canRemoveItems` for why, and
    /// for why a list that arrived empty is not the same case.
    ///
    /// **The total follows the row out, and the macros do not.** The asymmetry
    /// is `FoodTableGrounding`'s, for the same reason: a row always carries its
    /// own kilocalorie figure, and the meal's total has already been reconciled
    /// against it — that file adjusts the meal total by each row's own delta
    /// when it corrects one — so taking that figure back out is arithmetic on
    /// two numbers the model itself produced. A row's macros are the other
    /// case. The model is asked for `protein_g`/`carbs_g`/`fat_g` once, for the
    /// whole meal, and never per item, so the meal's macro figure was never
    /// composed from the rows and there is nothing in it to subtract; a row's
    /// `macros`, where it has any, is a CIQUAL figure that never reached the
    /// meal level at all. Subtracting it would take a number out that was never
    /// put in.
    ///
    /// So the macros stand, describing a meal one line larger than the one
    /// drawn under them. That is the honest state of a figure nobody can
    /// recompute without inventing the split, and it is unchanged from before
    /// this method did any arithmetic at all.
    ///
    /// **A removal alone asks the model nothing.** There is no new text for it
    /// to price — the user has said a line does not belong, which is a fact
    /// about the meal and not a question — so this does not make the footer
    /// offer `Re-analyse`. See `canReanalyse`.
    mutating func removeItem(_ id: RecognisedItem.ID) {
        // The refusal comes first, and it marks nothing: a removal that did not
        // happen must not leave the estimate reading as stale.
        guard canRemoveItems, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        userWrittenItems.remove(id)
        hasItemEdits = true
        // A row the user rewrote keeps the figure it arrived with even though
        // the screen stops drawing it, so this is the same subtraction either
        // way: what that row contributed to the total is what comes back out.
        kilocalories = max(0, kilocalories - removed.kilocalories)
        // And the accuracy figure is re-averaged over what is left. A row the
        // user threw out is not part of this meal, so how sure the model was
        // about it is not part of how sure it is about this meal. Nothing is
        // invented by doing so — the surviving rows' figures are the same
        // answers they always were, over a shorter list.
        estimateConfidencePercent = EstimateConfidence.percent(of: items.map(\.confidence))
    }

    /// Rewrites a line as the user's own words — `Polenta r50g` for something
    /// the photo could not weigh.
    ///
    /// An empty field changes nothing. Emptying a row is what the remove
    /// control is for, and a blank line in the list would be a line the next
    /// estimate is asked about and cannot read.
    mutating func editItem(_ id: RecognisedItem.ID, to text: String) {
        let written = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].name != written else { return }

        items[index].name = written
        // The confidence goes with the old words. It said how sure the model
        // was about a food it had read, and it has not read this one — the same
        // reason `isPriced` stops drawing the row's calorie figure the moment
        // it is rewritten. Leaving it would let a rewritten line go on
        // vouching for itself until a re-analysis happened to replace it.
        items[index].confidence = nil
        userWrittenItems.insert(id)
        hasItemEdits = true
        estimateConfidencePercent = EstimateConfidence.percent(of: items.map(\.confidence))
    }

    /// Adds a line the model missed, at the end of the list where the `Add
    /// item` row sits.
    ///
    /// The new row keeps `kilocalories` at zero and its note at `unknown`, and
    /// neither is drawn: an item the user wrote has no confidence, no weight
    /// the model estimated and no price yet. Both are filled in by the next
    /// re-analysis, which is what prices this row and the only way a draft
    /// holding one can be logged.
    mutating func addItem(_ text: String) {
        let written = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty else { return }

        let item = RecognisedItem(name: written, kilocalories: 0, note: .unknown)
        items.append(item)
        userWrittenItems.insert(item.id)
        hasItemEdits = true
    }

    /// Whether the figure beside a row is the model's to show.
    func isPriced(_ id: RecognisedItem.ID) -> Bool {
        !userWrittenItems.contains(id)
    }

    /// Puts a fresh estimate over the old one, keeping what the user decided.
    ///
    /// The label, whether they set it themselves, and the favourite mark are
    /// theirs and survive: they were choices about the meal, not about the
    /// breakdown, and re-deriving them would undo a correction. Everything the
    /// model owns is replaced wholesale, and with it the two flags that said
    /// the old estimate was stale.
    ///
    /// **Only correct when the reply is about the whole meal**, which is why it
    /// is not what a re-analysis calls. `applying(_:)` decides that, and reaches
    /// this only in the case where it holds.
    private mutating func replaceEstimate(with estimate: MealEstimate) {
        title = estimate.title
        kilocalories = estimate.kilocalories
        macros = estimate.macros
        advice = estimate.advice
        items = estimate.items
        estimateConfidencePercent = estimate.confidencePercent
        userWrittenItems = []
        hasItemEdits = false
    }

    // MARK: - Answering a re-analysis

    /// The draft this one becomes when a re-analysis answers, or `nil` for a
    /// reply that cannot be applied to it.
    ///
    /// **A re-analysis asks about the rows the user changed and about nothing
    /// else** — see `itemSentence` — so what comes back is an answer about the
    /// changed rows and not a new reading of the meal. Applying it therefore
    /// means splicing, not replacing, and the whole point of the exercise is
    /// what it leaves alone: an untouched row keeps its name, its kilocalories,
    /// its `macros` and its `note` byte for byte, so a figure CIQUAL grounded
    /// stays grounded and a photo row keeps the weight the photograph gave it.
    ///
    /// **Three things about the meal deliberately do not move on a splice: the
    /// title, the advisor line and the macros.** The reply's title names the
    /// handful of items it was asked about — `Rice` after a correction to one
    /// line — and writing it over the meal would rename `Salmon with polenta`
    /// after an edit to the spinach. Its advisor line is the same story said in
    /// a sentence: advice written about one corrected row, drawn under the
    /// whole meal's macros, would be advice about a meal nobody described. The
    /// standing line describes the meal before one row changed, which is a
    /// closer description of what is on the screen than a remark about the row
    /// on its own, and closer than nothing. The macros are the harder case and
    /// the answer is `FoodTableGrounding`'s again: the model is asked for
    /// macros once, for the whole meal, and never per row, so the meal's macro
    /// figure has no part in it attributable to the rows that changed and
    /// nothing that can honestly be taken out. Splitting it by kilocalorie
    /// share would answer that question with a number nobody produced. They
    /// stand until a reply about the whole meal replaces them, below.
    ///
    /// **When every row was changed there is nothing left to protect**, the
    /// reply describes the entire meal, and this is the wholesale replacement
    /// it always was — title, macros and all. That is not a special case bolted
    /// on: it is what the splice collapses to when the untouched half is empty.
    ///
    /// `nil` for a splice whose reply carries no breakdown at all. A meal
    /// priced without being split is a usable answer to "what is this meal",
    /// and no answer at all to "what are these rows" — the rows the user wrote
    /// would silently vanish from the list, taking their corrections with them.
    /// The caller shows the retry state instead.
    func applying(_ estimate: MealEstimate) -> MealResultDraft? {
        let untouched = items.filter { !userWrittenItems.contains($0.id) }

        guard !untouched.isEmpty else {
            var replaced = self
            replaced.replaceEstimate(with: estimate)
            return replaced
        }

        guard !estimate.items.isEmpty else {
            return nil
        }

        var merged = self
        merged.items = splicing(estimate.items)
        // Averaged over the list that now stands, which is the untouched rows'
        // own answers plus the reply's answers about the rows it was asked
        // about. Every figure in it is the model's about the food it names, so
        // there is nothing here to apportion — unlike the macros a paragraph
        // up, which the model was never asked to split.
        merged.estimateConfidencePercent = EstimateConfidence.percent(of: merged.items.map(\.confidence))
        // The rows that did not change contribute the figures they already
        // carry, and the rows that did contribute the model's own total for
        // exactly what it was asked to price. Both halves are numbers a model
        // wrote about the food they name; nothing here is apportioned.
        merged.kilocalories = untouched.reduce(estimate.kilocalories) { $0 + $1.kilocalories }
        merged.userWrittenItems = []
        merged.hasItemEdits = false
        return merged
    }

    /// The item list with the changed rows replaced by the reply's, in order.
    ///
    /// One rule, which covers every count the reply can come back with: each
    /// changed row takes the next row from the reply, and the last changed row
    /// takes everything the reply has left. A model that answered two corrected
    /// lines with two lines replaces them one for one; one that split a line
    /// into three puts all three where that line was; one that merged two lines
    /// into one leaves the surplus row dropped, because there is no second
    /// answer to put in it.
    private func splicing(_ fresh: [RecognisedItem]) -> [RecognisedItem] {
        guard let lastChanged = items.lastIndex(where: { userWrittenItems.contains($0.id) }) else {
            return items
        }

        var remaining = fresh[...]
        var merged: [RecognisedItem] = []

        for (index, item) in items.enumerated() {
            guard userWrittenItems.contains(item.id) else {
                merged.append(item)
                continue
            }
            if index == lastChanged {
                merged.append(contentsOf: remaining)
                remaining = []
            } else if let next = remaining.first {
                merged.append(next)
                remaining = remaining.dropFirst()
            }
        }

        return merged
    }

    /// Whether the remove mark is drawn on a row at all.
    ///
    /// **The last row cannot be thrown out.** A breakdown the user has emptied
    /// says they rejected every line the estimate was made of, while the figures
    /// above it still describe those lines — and `Add` over that would log a
    /// total for a breakdown its owner disowned. Correcting a whole meal is
    /// already possible without emptying it: the last row is a sentence, and
    /// rewriting it is what the field is for.
    ///
    /// A meal that arrived without a breakdown is a different thing and is left
    /// alone. `MealEstimate.items` may be empty — a model that priced a meal
    /// without splitting it gave a usable answer — and a meal repeated from the
    /// Recent list never had one. Those figures are the model's for the whole
    /// meal and nobody has disowned them; there is simply no row here to remove.
    var canRemoveItems: Bool {
        items.count > 1
    }

    /// Whether `Re-analyse` is a thing the footer can honestly offer.
    ///
    /// **There has to be something to ask about, and only text the model has
    /// not read is that.** A row the user rewrote and a row they added are a
    /// question; an unchanged breakdown is the answer they are already looking
    /// at, and spending their credit to be told it again is the thing this
    /// guard exists to stop.
    ///
    /// A removal is the case worth naming, because it is a change and it is not
    /// a question — the user has said a line does not belong, which is a fact
    /// the device applies itself, and `removeItem` does. So a screen where the
    /// only edit was a removal keeps the caller's own action: there is nothing
    /// left to send, and a request built from the rows that survived would be a
    /// request to re-price exactly the rows nobody touched.
    ///
    /// That subsumes the empty-list half this used to state separately. An id
    /// is in `userWrittenItems` only while the row it names is in `items` —
    /// `removeItem` takes it out with the row — so a non-empty set is a
    /// non-empty list, and an emptied list cannot produce a button that does
    /// nothing. The footer and the three models all read this one property, so
    /// the drawing and the refusal cannot disagree; they used to, and a footer
    /// reading `Re-analyse` over an emptied list did nothing at all while
    /// hiding the action it had replaced.
    ///
    /// A list that was empty when it arrived stays the caller's own action:
    /// `MealEstimate.items` may arrive empty, and so may a stored meal's, so
    /// `Add` and `Delete` are already what those screens offer over an empty
    /// heading.
    ///
    /// A meal repeated from the Recent list used to be the clearest case of
    /// that and is no longer one at all: it carries the breakdown of the meal
    /// it repeats, item for item, so it arrives here empty only when that meal
    /// had none of its own.
    var canReanalyse: Bool {
        !userWrittenItems.isEmpty
    }

    /// The rows the user has written, as one line of text, which is what a
    /// re-analysis is asked about.
    ///
    /// **Only those rows, and that is the fix for the bug this file's history
    /// is about.** Sending the whole list asked the model to price five things
    /// when one had changed, and it answered about all five — so a row the user
    /// never touched came back at a different number, because a second guess at
    /// the same food is a different guess. Asking about the changed rows alone
    /// makes that structurally impossible rather than merely discouraged: a row
    /// that is not in the request cannot be in the reply, and `applying(_:)`
    /// reads the reply only into the rows it asked about.
    ///
    /// It also scopes the grounding pass for free. `FoodTableGrounding` runs
    /// inside the client, over the items of the reply it is handed, so a reply
    /// that only contains the changed rows can only correct the changed rows —
    /// no second rule was needed there, and none was written.
    ///
    /// **The cost, stated plainly: the model loses the rest of the plate.** A
    /// line corrected inside a shared dish — rice in a curry, bread under a
    /// stew — is priced as that line alone, with no sauce it soaked up and no
    /// oil it was cooked in. Sending the untouched rows as context that must
    /// not be re-priced would keep that, and would be a promise enforced by the
    /// model's obedience, which is precisely what failed here. A bounded loss
    /// of context on the row the user is correcting is worth an unbounded
    /// silence on the rows they are not.
    ///
    /// Names only. The calories beside them are the previous estimate's, and
    /// handing the model its own last answer back would invite it to agree with
    /// itself rather than to price what the user has written.
    var itemSentence: String {
        items
            .filter { userWrittenItems.contains($0.id) }
            .map(\.name)
            .joined(separator: ", ")
    }
}
