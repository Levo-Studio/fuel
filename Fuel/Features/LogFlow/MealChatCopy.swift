import Foundation

// MARK: - Copy

/// Everything the conversation sheet says.
///
/// **None of it is drawn.** The export has no chat of any kind — no sheet, no
/// transcript, no field, no second corner control — so every key below is
/// marked `Not in the export.` in the catalog, and the whole surface is the
/// owner's instruction rather than a frame anyone can grep for.
nonisolated enum MealChatCopy {

    // MARK: - The control that opens it

    /// The trailing corner control on the meal-detail footer, for VoiceOver.
    /// The mark itself is an SF Symbol and so has no key of its own.
    static var open: String {
        String(localized: "chat.open")
    }

    // MARK: - Header

    static var title: String {
        String(localized: "chat.title")
    }

    /// The line under the title, which is the only place the rule of the whole
    /// feature is stated to the user: amounts move, and the figures follow.
    static var hint: String {
        String(localized: "chat.hint")
    }

    static var close: String {
        String(localized: "chat.close")
    }

    // MARK: - The field

    static var placeholder: String {
        String(localized: "chat.placeholder")
    }

    static var send: String {
        String(localized: "chat.send")
    }

    /// What the same control says while a reply is arriving, when it stops the
    /// message instead of sending one.
    static var stop: String {
        String(localized: "chat.stop")
    }

    // MARK: - The transcript

    /// What a reply reads as when the model moved something but wrote no
    /// usable sentence about it. The rows under it say what moved.
    static var adjusted: String {
        String(localized: "chat.adjusted")
    }

    /// What a reply reads as when the model asked for a change, nothing moved,
    /// and it said nothing either — the emptiest answer an adjustment can get,
    /// and one this screen still has to state rather than leave blank.
    static var unchanged: String {
        String(localized: "chat.unchanged")
    }

    /// The same emptiness after a question, which is a different thing to read.
    ///
    /// Nothing was being adjusted, so there is nothing for the meal to be
    /// unchanged against; what happened is that the model answered with no
    /// usable words, and that is what this says.
    static var noAnswer: String {
        String(localized: "chat.noAnswer")
    }

    /// The note under a reply that asked to change something and changed
    /// nothing.
    ///
    /// **The load-bearing string of this feature.** A sentence claiming a
    /// change, with no change under it and nothing saying so, reads as a change
    /// that happened, and a screen that spends the user's credit must not let
    /// them infer that. It follows a turn that asked for one and no other —
    /// under an answer to a question it would be Fuel correcting the user for
    /// asking. See `MealChatMessage.movedNothing`.
    static var nothingChanged: String {
        String(localized: "chat.nothingChanged")
    }

    /// What the sheet says before anything has been said in it.
    static var empty: String {
        String(localized: "chat.empty")
    }

    /// The reply row before a word of it has arrived — and the whole of that
    /// row for as long as it is arriving, where the user has asked for less
    /// motion and the sentence is therefore drawn only once it is complete.
    ///
    /// **The one thing a question shows instead of the analysis states**, so it
    /// carries the entire answer to "is anything happening" on its own.
    static var writing: String {
        String(localized: "chat.writing")
    }

    /// One changed row's new weight.
    static func grams(_ value: Int) -> String {
        String(localized: "chat.change.grams \(value)")
    }

    /// A changed row whose weight is not stated — an addition the table priced
    /// without one cannot occur, but a row can be renamed without being
    /// reweighed, and the column still has to read as something.
    static var noAmount: String {
        String(localized: "chat.change.noAmount")
    }
}
