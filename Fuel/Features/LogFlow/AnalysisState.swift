import Foundation

// MARK: - Analysis step

/// The four states screens 08 to 11 draw, in order.
///
/// One screen rendered four times, not four screens: the bar and the label
/// move, nothing else does. The steps are paced rather than reported — there
/// is one request, and the provider says nothing on the way — so they stand
/// for elapsed work in the same way the key test's four steps do.
nonisolated enum AnalysisStep: CaseIterable, Hashable, Sendable {

    case analysingMeal
    case identifyingIngredients
    case estimatingAmounts
    case calculatingNutrition

    /// How much of the 120×2 bar is filled. The export draws 25%, 50%, 75%
    /// and 100% — quarters, one per step.
    var progress: Double {
        guard let index = Self.allCases.firstIndex(of: self) else { return 0 }
        return Double(index + 1) / Double(Self.allCases.count)
    }
}

// MARK: - Failure

/// A failed scan, in the three shapes the interface can act on.
///
/// It is `AIError` with everything the screen cannot use taken out. Five of
/// the provider errors want the same thing from the user — try again — and
/// collapsing them here rather than in the view means the mapping is one
/// function with a test instead of a `switch` repeated at every call site.
nonisolated enum AnalysisFailure: Equatable, Sendable {

    /// The provider refused the key. The remedy is Settings, not a retry.
    case invalidKey

    /// The key works and the account behind it cannot pay. Carries the
    /// provider's own billing page, which came from `AIError` and never from a
    /// response body.
    case noCredit(billingPage: URL)

    /// Everything else worth showing: a lost connection, a provider that
    /// refused, a reply Fuel could not read, a photo too large to send, a
    /// camera that did not deliver a frame.
    ///
    /// **It carries where it died, and the title above it now says so.** The
    /// export draws one generic retry state with one wording, in the theme's
    /// ordinary ink; the owner asked for the title in `FuelPalette.error` and
    /// a plain-language cause line under it once this case existed to make
    /// that honest. `AnalysisCopy.failureHint` reads the origin and chooses
    /// one of four fixed sentences — never a provider's own words, never a
    /// status code — so what used to be a single undifferentiated screen for
    /// four different failures is now telling the user which of the four it
    /// was, in words a non-technical reader can act on.
    case retry(Origin)

    // MARK: - Origin

    /// How far a retryable failure got before it died.
    ///
    /// Four, because they are four different investigations, and because the
    /// one sentence the design draws is honest about exactly one of them.
    nonisolated enum Origin: Equatable, Sendable {

        /// It never left the device: a photo too large to send, a camera that
        /// did not deliver a frame, a store that refused a write.
        ///
        /// **Reachable, and not by the rare one of the three.** A photo over
        /// `MealPhotoCompressor.maximumBytes` is the pathological case the
        /// type itself says it is, but the camera failing to deliver a frame
        /// — `CameraLogModel.capture()`'s own catch — and a re-analysis the
        /// store refused to write — `MealDetailModel.writeBack()`'s — are
        /// ordinary hardware and disk failures with nothing rare about them.
        case device

        /// It was sent and nothing came back — no route, a dropped
        /// connection, a timeout.
        case transport

        /// The provider answered and refused: a `429`, a `500`, an
        /// `overloaded_error`, a `404` for a model id.
        case provider

        /// The provider answered with an estimate Fuel could not read —
        /// prose, a wrong shape, or a reply cut off at the token ceiling.
        case reply
    }

    /// `nil` for a cancelled scan.
    ///
    /// Someone who has just tapped `CANCEL` is shown nothing at all — offering
    /// them a second go at the scan they abandoned is the bug this case
    /// separation exists to prevent.
    init?(_ error: AIError) {
        switch error {
        case .cancelled:
            return nil
        case .invalidKey, .missingKey:
            // `missingKey` means the key went away between the check that
            // enabled the shutter and the request. Different cause, identical
            // remedy: the user goes to Settings and puts a key in.
            self = .invalidKey
        case .noCredit(_, let billingPage):
            self = .noCredit(billingPage: billingPage)
        case .network:
            self = .retry(.transport)
        case .providerRefused:
            self = .retry(.provider)
        case .malformedResponse, .truncatedReply:
            self = .retry(.reply)
        case .imageTooLarge:
            self = .retry(.device)
        }
    }
}
