import Foundation

// MARK: - Copy

/// The words screens 14 and 15 share.
///
/// The two result screens are the same screen with a different thing at the
/// top: everything from the meal-label pill down is drawn identically, so the
/// labels on it are one set of keys rather than two. What differs — the flow
/// label top right, the heading over the breakdown — is handed to
/// `MealResultView` by the screen that knows which mode it is.
///
/// Nothing here holds English text; each entry names a key in
/// `Localizable.xcstrings`. Casing is the style's, not the value's: `‹ Back`
/// is stored in its natural case and uppercased by `FuelTypography.eyebrow`.
nonisolated enum MealResultCopy {

    // MARK: - Header

    static var back: String {
        String(localized: "result.back")
    }

    static var backLabel: String {
        String(localized: "result.back.label")
    }

    // MARK: - Label and favourite

    static func mealLabel(_ label: MealLabel) -> String {
        switch label {
        case .breakfast: String(localized: "result.label.breakfast")
        case .lunch: String(localized: "result.label.lunch")
        case .snack: String(localized: "result.label.snack")
        case .dinner: String(localized: "result.label.dinner")
        }
    }

    static var mealLabelHint: String {
        String(localized: "result.label.hint")
    }

    static func favourite(isOn: Bool) -> String {
        isOn
            ? String(localized: "result.favourite.on")
            : String(localized: "result.favourite.off")
    }

    static var favouriteLabel: String {
        String(localized: "result.favourite.label")
    }

    // MARK: - Calories and macros

    static var unit: String {
        String(localized: "result.unit")
    }

    static func kilocaloriesValue(_ kilocalories: Int) -> String {
        String(format: String(localized: "result.kilocalories.value"), kilocalories)
    }

    static var macroProtein: String {
        String(localized: "result.macro.protein")
    }

    static var macroCarbs: String {
        String(localized: "result.macro.carbs")
    }

    static var macroFat: String {
        String(localized: "result.macro.fat")
    }

    static func grams(_ value: Int) -> String {
        String(format: String(localized: "result.macro.grams"), value)
    }

    // MARK: - Accuracy

    /// The score on the row above the figure — `80% ACC`.
    ///
    /// Casing is the value's rather than the style's, exactly as `CAPTURED
    /// PHOTO` and `CANCEL` are stored: `overlayCaption` does not transform,
    /// because the export draws those runs already uppercase. Which is also
    /// where a ruling on the abbreviation would land — see
    /// `MealAccuracyLabel`, whose type follows this string's casing rather
    /// than the other way round.
    static func accuracy(_ percent: Int) -> String {
        String(format: String(localized: "result.accuracy"), percent)
    }

    /// What VoiceOver says instead. `80% ACC` spoken letter by letter is not a
    /// word, and an abbreviation that exists to save room on a row has no room
    /// to save in speech.
    static func accuracySpoken(_ percent: Int) -> String {
        String(format: String(localized: "result.accuracy.spoken"), percent)
    }

    // MARK: - Breakdown

    /// The remove mark at the trailing edge of a breakdown row, for VoiceOver.
    ///
    /// There is no glyph key beside it: the mark is an SF Symbol, because
    /// neither bundled face carries the `✕` the export writes on screen 07.
    /// `MealResultView.removeControl` has the cmap evidence and the precedent.
    static var itemRemoveLabel: String {
        String(localized: "result.item.remove.label")
    }

    static var itemAdd: String {
        String(localized: "result.item.add")
    }

    static var itemEditHint: String {
        String(localized: "result.item.edit.hint")
    }

    static var itemEditTitle: String {
        String(localized: "result.item.edit.title")
    }

    static var itemEditMessage: String {
        String(localized: "result.item.edit.message")
    }

    static var itemEditPlaceholder: String {
        String(localized: "result.item.edit.placeholder")
    }

    static var itemEditCancel: String {
        String(localized: "result.item.edit.cancel")
    }

    static var itemEditConfirm: String {
        String(localized: "result.item.edit.confirm")
    }

    // MARK: - Footer

    /// The leading footer control, which is a trash mark and no word.
    static var discardLabel: String {
        String(localized: "result.discard.label")
    }

    /// What the confirmation says on the two screens where the estimate has
    /// not been written down yet, so discarding it is literally what happens.
    static var discardConfirmation: FuelDialogCopy {
        FuelDialogCopy(
            title: String(localized: "result.discard.title"),
            confirm: String(localized: "result.discard.confirm"),
            cancel: String(localized: "result.discard.cancel")
        )
    }

    static var add: String {
        String(localized: "result.add")
    }

    /// What `Add` becomes once the user has changed the breakdown.
    static var reanalyse: String {
        String(localized: "result.reanalyse")
    }
}
