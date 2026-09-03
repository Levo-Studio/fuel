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

    static var stepperDecrease: String {
        String(localized: "result.stepper.decrease")
    }

    static var stepperIncrease: String {
        String(localized: "result.stepper.increase")
    }

    static var stepperDecreaseLabel: String {
        String(localized: "result.stepper.decrease.label")
    }

    static var stepperIncreaseLabel: String {
        String(localized: "result.stepper.increase.label")
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

    // MARK: - Breakdown

    /// The second line of a breakdown row.
    ///
    /// Chosen by the shape of the note rather than by which screen is asking,
    /// because the note already carries the mode: a photo item knows a
    /// confidence and an approximate weight, a typed item knows only whether
    /// the amount was written down. A note this build cannot read draws
    /// nothing, and the row keeps its name and its calories — the part the
    /// user is reading.
    static func itemNote(_ note: RecognisedItem.Note) -> String? {
        switch note {
        case .photo(let confidence, let grams):
            let format = switch confidence {
            case .confident: String(localized: "result.photo.item.confident")
            case .unsure: String(localized: "result.photo.item.unsure")
            }
            return String(format: format, grams)
        case .text(let amount):
            return switch amount {
            case .recognised: String(localized: "result.text.item.recognised")
            case .estimated: String(localized: "result.text.item.estimated")
            }
        case .unknown:
            return nil
        }
    }

    // MARK: - Footer

    static var new: String {
        String(localized: "result.new")
    }

    static var add: String {
        String(localized: "result.add")
    }
}
