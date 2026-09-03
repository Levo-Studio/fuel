import Foundation

// MARK: - Copy

/// Every word the text half of the log flow prints: screen 12, and the two
/// labels that make a result screen the text one.
///
/// Nothing here holds English text — each entry names a key in
/// `Localizable.xcstrings`. Casing is the style's: `Text entry` is stored in
/// its natural case and uppercased by `FuelTypography.flowLabel`.
///
/// Two entries have no counterpart in the export and are marked `Not in the
/// export` in the catalog: the keyless state, which the design does not draw,
/// and the field's spoken label. The field's *visible* label is the screen's
/// own heading, which is why VoiceOver is given that same key rather than a
/// second wording invented for it.
nonisolated enum TextLogCopy {

    // MARK: - Screen 12

    static var title: String {
        String(localized: "text.title")
    }

    static var hint: String {
        String(localized: "text.hint")
    }

    static var analyse: String {
        String(localized: "text.analyse")
    }

    /// The examples the empty field rotates through, in the order they are
    /// shown.
    ///
    /// Every one of them names an amount, because the line above the field
    /// says the estimate is only as exact as the amounts are. An example
    /// without one would teach the opposite of the screen's own instruction.
    static var placeholderExamples: [String] {
        [
            String(localized: "text.placeholder.example.eggs"),
            String(localized: "text.placeholder.example.chicken"),
            String(localized: "text.placeholder.example.salmon"),
            String(localized: "text.placeholder.example.latte"),
        ]
    }

    /// An example with the trailing ellipsis that makes it read as unfinished.
    ///
    /// The ellipsis is a format rather than part of each example, so the glyph
    /// and the space before it are written once and the examples stay plain
    /// sentences. The spacing is the export's own: it draws `…` after a space
    /// on all four analysis screens. It is deliberately not the `·` the export
    /// uses to separate figures — a different mark doing a different job.
    static func placeholderLine(_ example: String) -> String {
        String(format: String(localized: "text.placeholder.format"), example)
    }

    static var noKeyTitle: String {
        String(localized: "text.noKey.title")
    }

    static var noKeyHint: String {
        String(localized: "text.noKey.hint")
    }

    // MARK: - Screen 15

    /// `Text entry`, the flow label top right.
    static var resultFlow: String {
        String(localized: "result.text.flow")
    }

    /// `Broken down`, because this list came from a sentence rather than from
    /// a photograph. The photo mode's heading is `Recognised`.
    static var resultItemsHeading: String {
        String(localized: "result.text.heading")
    }

    /// The quoted sentence, for VoiceOver.
    ///
    /// The words are the user's own and are read out as they were typed; this
    /// only says what they are, which the accent rule beside them says
    /// visually.
    static var resultQuoteLabel: String {
        String(localized: "result.text.quote.label")
    }
}
