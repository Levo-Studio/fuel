import Foundation

// MARK: - Analysis step

/// What the screen says while an analysis runs, in the order the work happens.
///
/// One screen rendered once per caption, not one screen per caption: the bar
/// and the label move, nothing else does. Screens 08 to 11 draw four of these;
/// the export's own note calls them "one per step, not four different
/// designs", and the two either side of them are drawn exactly as the four
/// are.
///
/// **What is actually observable during an analysis is one boundary, and the
/// captions are honest about which side of it they sit on.** A scan is:
/// compress the frame (photo only, and synchronous — the main actor never gets
/// a frame out during it, so it can have no caption of its own), then one
/// `AIClient.estimate` call, then the draft. That call is opaque from here: it
/// reads the key, signs and sends the request, waits for the whole reply,
/// parses it, looks every item up in the bundled CIQUAL table and prices the
/// portions, and none of that is reported on the way. So:
///
/// - `sendingRequest` is **anchored**. The model sets it at the moment it hands
///   the request to the client, and it is true while the key is read, the body
///   is built and — for a photo — the image goes up.
/// - The four in the middle are **paced**, exactly as the export's four always
///   were and for the reason `FuelMotion.analysisStepHold` gives: there is one
///   request and the provider says nothing on the way, so they stand for
///   elapsed work in the same way the key test's four steps do. They name the
///   model's own work in the order it is asked for.
/// - `waitingForModel` is the **end of the narration**, and it is the answer to
///   a request that outlasts everything Fuel can say about it. Nothing cycles
///   and nothing repeats: once there is nothing left to claim, the screen says
///   what is actually true, which is that it is waiting.
///
/// **There is no caption for reading the reply, for the food-table lookup or
/// for the arithmetic, and there deliberately is not.** All three happen inside
/// `AIClient.estimate`, after the answer has landed, and take milliseconds
/// between them. A caption for any of them could only ever be shown once the
/// work it names had finished, which is the fabrication this repository refuses
/// elsewhere.
nonisolated enum AnalysisStep: CaseIterable, Hashable, Sendable {

    /// The request going out. Anchored: set where `AIClient.estimate` is
    /// called, not by the clock.
    case sendingRequest

    case analysingMeal
    case identifyingIngredients
    case estimatingAmounts
    case calculatingNutrition

    /// Everything sayable has been said and the answer is not back yet.
    ///
    /// The one caption that is still true after a minute, which is what lets
    /// the walk stop here rather than cycle.
    case waitingForModel

    /// How much of the 120×2 bar is filled.
    ///
    /// **The export's quarters, unchanged, and the two added captions take no
    /// share of their own.** Screens 08 to 11 draw the bar at 25, 50, 75 and
    /// 100 per cent and `Fuel Design Notes.md` says in as many words that it
    /// fills in quarters, so those four figures are drawn values rather than a
    /// rule to be generalised. Dividing by the count instead would move three
    /// of the four drawn frames — 08 to a third, 10 to two thirds, 11 to five
    /// sixths — which is a departure from the export in exchange for nothing
    /// the user can see.
    ///
    /// So the captions either side of them borrow rather than displace:
    ///
    /// - `sendingRequest` is the bare track. The export draws no filled bar
    ///   before its first state, and this caption stands before it.
    /// - `waitingForModel` holds at full, beside `calculatingNutrition`.
    ///   They mean the same thing about the bar and this file says so already:
    ///   full means **Fuel has said everything it can say about a request that
    ///   is still out**, not that the estimate has arrived. Screen 11 draws a
    ///   full bar under `Berechne Nährwerte …` and the result is a different
    ///   screen; two captions sharing that meaning share the share.
    var progress: Double {
        switch self {
        case .sendingRequest: 0
        case .analysingMeal: 0.25
        case .identifyingIngredients: 0.5
        case .estimatingAmounts: 0.75
        case .calculatingNutrition, .waitingForModel: 1
        }
    }

    /// The captions a walk beside one request goes through, after the anchored
    /// first one the model has already set.
    ///
    /// Under Reduce Motion this is the last caption alone: one change, from
    /// what is being done to what is being waited for, rather than a caption
    /// rewriting itself four more times while it is being read.
    /// `FuelMotion.resolvePacedNarration` is where that decision lives and why.
    static func walk(reduceMotion: Bool) -> [AnalysisStep] {
        guard FuelMotion.resolvePacedNarration(reduceMotion: reduceMotion) else {
            return [.waitingForModel]
        }
        return Array(allCases.dropFirst())
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
