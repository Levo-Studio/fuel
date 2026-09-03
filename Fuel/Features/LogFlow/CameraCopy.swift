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

    /// `Photo entry`, the flow label top right. Screen 15's is `Text entry`
    /// and belongs to the text mode.
    static var resultFlow: String {
        String(localized: "result.photo.flow")
    }

    /// `Recognised`, because this list came from a photo. The text mode's
    /// heading is `Broken down`.
    static var resultItemsHeading: String {
        String(localized: "result.photo.heading")
    }

    /// The stand-in the export draws where the photo goes. Only shown when
    /// there is no photo to draw — a preview, or a frame that did not survive.
    static var resultPhotoCaption: String {
        String(localized: "result.photo.caption")
    }

    static var resultPhotoLabel: String {
        String(localized: "result.photo.label")
    }
}
