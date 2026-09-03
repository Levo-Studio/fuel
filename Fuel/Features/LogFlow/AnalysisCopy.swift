import Foundation

// MARK: - Copy

/// The words the four analysis states print, and the words a failed estimate
/// prints.
///
/// Neither set belongs to a log mode. The export's four step labels — analyse,
/// identify, estimate, calculate — describe the work rather than the input, and
/// both AI modes do exactly that work; the failures are the same three
/// remedies whichever way the meal was described.
///
/// Two hints are the exception, and they are the reason `AILogMode` reaches
/// this file at all: telling someone to "take the photo again" after they typed
/// a sentence is wrong. Everything else is one key.
///
/// Nothing here holds English text — each entry names a key in
/// `Localizable.xcstrings`. The `CANCEL` values are stored uppercase because
/// the export draws them uppercase and `FuelTypography.overlayAction` does not
/// transform.
nonisolated enum AnalysisCopy {

    // MARK: - Screens 08 to 11

    static func step(_ step: AnalysisStep) -> String {
        switch step {
        case .analysingMeal: String(localized: "logFlow.analysis.step.meal")
        case .identifyingIngredients: String(localized: "logFlow.analysis.step.ingredients")
        case .estimatingAmounts: String(localized: "logFlow.analysis.step.amounts")
        case .calculatingNutrition: String(localized: "logFlow.analysis.step.nutrition")
        }
    }

    static var cancel: String {
        String(localized: "logFlow.analysis.cancel")
    }

    /// What the bar is worth, spoken. The drawn quarter says nothing on its
    /// own once it is read out away from the label under it.
    static func progress(_ step: AnalysisStep) -> String {
        String(
            format: String(localized: "logFlow.analysis.progress.value"),
            (AnalysisStep.allCases.firstIndex(of: step) ?? 0) + 1,
            AnalysisStep.allCases.count
        )
    }

    // MARK: - Failures

    static func failureTitle(_ failure: AnalysisFailure) -> String {
        switch failure {
        case .invalidKey: String(localized: "logFlow.failure.invalidKey.title")
        case .noCredit: String(localized: "logFlow.failure.noCredit.title")
        case .retry: String(localized: "logFlow.failure.retry.title")
        }
    }

    /// The line under a failure title.
    ///
    /// The remedy for a refused key and the description of a lost request both
    /// name what the user did, so they are per mode. An exhausted balance names
    /// only the account, which is the same sentence either way.
    static func failureHint(_ failure: AnalysisFailure, mode: AILogMode) -> String {
        switch failure {
        case .invalidKey:
            switch mode {
            case .photo: String(localized: "logFlow.failure.invalidKey.hint.photo")
            case .text: String(localized: "logFlow.failure.invalidKey.hint.text")
            }
        case .noCredit:
            String(localized: "logFlow.failure.noCredit.hint")
        case .retry:
            switch mode {
            case .photo: String(localized: "logFlow.failure.retry.hint.photo")
            case .text: String(localized: "logFlow.failure.retry.hint.text")
            }
        }
    }

    static var failureBilling: String {
        String(localized: "logFlow.failure.noCredit.action")
    }

    static var failureRetry: String {
        String(localized: "logFlow.failure.action.retry")
    }

    static var failureDismiss: String {
        String(localized: "logFlow.failure.action.dismiss")
    }
}
