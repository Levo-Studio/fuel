import Foundation

// MARK: - Copy

/// Every word the camera half of the log flow prints: screen 07, the four
/// analysis states, and the photo result.
///
/// Nothing here holds English text — each entry names a key in
/// `Localizable.xcstrings`. Where a value is already uppercase it is because
/// the export draws it uppercase and the style it is set in does *not*
/// transform: `FuelTypography.overlayAction` and `overlayCaption` both say so.
/// The keys whose style does transform — `eyebrow`, `flowLabel`,
/// `sectionLabel` — keep their natural case here.
///
/// Three groups of words have no counterpart in the export and are marked
/// `Not in the export` in the catalog, the way Onboarding and Settings marked
/// theirs: the keyless state, the analysis failures, and the accessibility
/// labels. The export draws no disabled camera and no failed scan; both are
/// built in its visual language because the app has to answer for them.
nonisolated enum CameraCopy {

    // MARK: - Screen 07

    static var shutterLabel: String {
        String(localized: "camera.shutter.label")
    }

    static var shutterHint: String {
        String(localized: "camera.shutter.hint")
    }

    /// The `▣` in the circle top right.
    static var galleryGlyph: String {
        String(localized: "camera.gallery.glyph")
    }

    static var galleryLabel: String {
        String(localized: "camera.gallery.label")
    }

    static var noKeyTitle: String {
        String(localized: "camera.noKey.title")
    }

    static var noKeyHint: String {
        String(localized: "camera.noKey.hint")
    }

    // MARK: - Screens 08 to 11

    static func analysisStep(_ step: AnalysisStep) -> String {
        switch step {
        case .analysingMeal: String(localized: "camera.analysis.step.meal")
        case .identifyingIngredients: String(localized: "camera.analysis.step.ingredients")
        case .estimatingAmounts: String(localized: "camera.analysis.step.amounts")
        case .calculatingNutrition: String(localized: "camera.analysis.step.nutrition")
        }
    }

    static var analysisCancel: String {
        String(localized: "camera.analysis.cancel")
    }

    /// What the bar is worth, spoken. The drawn quarter says nothing on its
    /// own once it is read out away from the label under it.
    static func analysisProgress(_ step: AnalysisStep) -> String {
        let position = (AnalysisStep.allCases.firstIndex(of: step) ?? 0) + 1
        return String(
            format: String(localized: "camera.analysis.progress.value"),
            position,
            AnalysisStep.allCases.count
        )
    }

    // MARK: - Failures

    static func failureTitle(_ failure: AnalysisFailure) -> String {
        switch failure {
        case .invalidKey: String(localized: "camera.failure.invalidKey.title")
        case .noCredit: String(localized: "camera.failure.noCredit.title")
        case .retry: String(localized: "camera.failure.retry.title")
        }
    }

    static func failureHint(_ failure: AnalysisFailure) -> String {
        switch failure {
        case .invalidKey: String(localized: "camera.failure.invalidKey.hint")
        case .noCredit: String(localized: "camera.failure.noCredit.hint")
        case .retry: String(localized: "camera.failure.retry.hint")
        }
    }

    static var failureBilling: String {
        String(localized: "camera.failure.noCredit.action")
    }

    static var failureRetry: String {
        String(localized: "camera.failure.action.retry")
    }

    static var failureDismiss: String {
        String(localized: "camera.failure.action.dismiss")
    }

    // MARK: - Screen 14

    static var resultBack: String {
        String(localized: "camera.result.back")
    }

    static var resultBackLabel: String {
        String(localized: "camera.result.back.label")
    }

    static var resultFlow: String {
        String(localized: "camera.result.flow")
    }

    /// The stand-in the export draws where the photo goes. Only shown when
    /// there is no photo to draw — a preview, or a frame that did not survive.
    static var resultPhotoCaption: String {
        String(localized: "camera.result.photo.caption")
    }

    static var resultPhotoLabel: String {
        String(localized: "camera.result.photo.label")
    }

    static func mealLabel(_ label: MealLabel) -> String {
        switch label {
        case .breakfast: String(localized: "camera.result.label.breakfast")
        case .lunch: String(localized: "camera.result.label.lunch")
        case .snack: String(localized: "camera.result.label.snack")
        case .dinner: String(localized: "camera.result.label.dinner")
        }
    }

    static var mealLabelHint: String {
        String(localized: "camera.result.label.hint")
    }

    static func favourite(isOn: Bool) -> String {
        isOn
            ? String(localized: "camera.result.favourite.on")
            : String(localized: "camera.result.favourite.off")
    }

    static var favouriteLabel: String {
        String(localized: "camera.result.favourite.label")
    }

    static var resultUnit: String {
        String(localized: "camera.result.unit")
    }

    static func kilocaloriesValue(_ kilocalories: Int) -> String {
        String(format: String(localized: "camera.result.kilocalories.value"), kilocalories)
    }

    static var stepperDecrease: String {
        String(localized: "camera.result.stepper.decrease")
    }

    static var stepperIncrease: String {
        String(localized: "camera.result.stepper.increase")
    }

    static var stepperDecreaseLabel: String {
        String(localized: "camera.result.stepper.decrease.label")
    }

    static var stepperIncreaseLabel: String {
        String(localized: "camera.result.stepper.increase.label")
    }

    static var macroProtein: String {
        String(localized: "camera.result.macro.protein")
    }

    static var macroCarbs: String {
        String(localized: "camera.result.macro.carbs")
    }

    static var macroFat: String {
        String(localized: "camera.result.macro.fat")
    }

    static func grams(_ value: Int) -> String {
        String(format: String(localized: "camera.result.macro.grams"), value)
    }

    /// `Recognised`, because this list came from a photo. The text mode's
    /// heading is `Broken down` and belongs to that screen.
    static var itemsHeading: String {
        String(localized: "camera.result.items.heading")
    }

    /// The confidence line under a recognised item.
    ///
    /// `nil` for a note this screen cannot draw. A photo estimate carries
    /// photo notes; a text note or one written by a build that knew a shape
    /// this one does not still leaves the row its name and its calories, which
    /// is the part the user is reading.
    static func itemNote(_ note: RecognisedItem.Note) -> String? {
        guard case .photo(let confidence, let grams) = note else { return nil }
        let format = switch confidence {
        case .confident: String(localized: "camera.result.item.confident")
        case .unsure: String(localized: "camera.result.item.unsure")
        }
        return String(format: format, grams)
    }

    static var resultNew: String {
        String(localized: "camera.result.new")
    }

    static var resultAdd: String {
        String(localized: "camera.result.add")
    }
}
