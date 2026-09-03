import Foundation

// MARK: - Placeholder

/// The example shown in screen 12's field while it is empty, and where in the
/// rotation it currently is.
///
/// **Not in the export.** The field is drawn with a sentence already in it, at
/// full ink — that is typed text, not a placeholder, and the design has none.
/// The owner asked for one, so it is composed out of what the export does
/// draw: the ink of a label that is not the one in play, and the trailing
/// ellipsis the analysis steps are drawn with.
///
/// A value rather than view state so the rules can be read and tested without
/// a screen: what shows while the field is empty, what shows once it is not,
/// and what advancing does at the end of the list. The examples are handed in
/// rather than read from the catalog here, which is what lets a test cycle
/// three known strings instead of asserting English copy.
nonisolated struct TextEntryPlaceholder: Equatable, Sendable {

    private let examples: [String]

    /// Which example is showing. Starts at the first, which is also the only
    /// one anybody sees under Reduce Motion.
    private(set) var index: Int

    init(examples: [String]) {
        self.examples = examples
        self.index = 0
    }

    /// The example to draw, or `nil` once the field has anything in it.
    ///
    /// Emptiness is the platform's, not the model's: the model trims before it
    /// decides whether a sentence is worth a request, but a field holding a
    /// space has been typed into, and drawing an example under the user's own
    /// cursor position would be the one thing this must never do. Analyse still
    /// refuses that field, which is a separate rule and unchanged.
    func example(whileTyped typed: String) -> String? {
        guard typed.isEmpty, !examples.isEmpty else { return nil }
        return examples[index % examples.count]
    }

    /// Moves to the next example, wrapping at the end.
    mutating func advance() {
        guard !examples.isEmpty else { return }
        index = (index + 1) % examples.count
    }
}
