import Foundation
import SwiftUI

// MARK: - Key presence

/// Whether a provider key exists, without reading one.
///
/// The whole feature asks exactly this question and never the other one. A
/// protocol rather than a `KeychainStore` parameter so a test can answer it
/// without a keychain-access group, and so nothing in the log flow is even
/// able to pull a secret into memory: `hasKey(for:)` is the only method, and
/// `KeychainStore` implements it by asking the Keychain for an item's presence
/// with `kSecReturnData` off.
nonisolated protocol MealKeyPresence: Sendable {

    func hasKey(for provider: AIProvider) -> Bool
}

extension KeychainStore: MealKeyPresence {}

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

    /// Everything else worth showing: a lost connection, a reply Fuel could
    /// not read, a photo too large to send, a camera that did not deliver a
    /// frame.
    case retry

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
        case .network, .malformedResponse, .imageTooLarge:
            self = .retry
        }
    }
}

// MARK: - Result draft

/// The estimate as the result screen holds it: still editable, not yet an
/// entry.
///
/// A value rather than a `FoodEntry`, because screen 14 is a decision. The
/// user can move the calories, cycle the label and mark it a favourite, and
/// none of that should exist in the database until they tap `Add` — a scan
/// they walk away from must leave nothing behind.
nonisolated struct PhotoResultDraft: Equatable, Sendable {

    /// Model-written text. Already capped at 120 characters at the parse
    /// boundary in `Core/AI`, so it is not capped again here — but it is not
    /// assumed short either, and it is rendered as plain text with no markup
    /// path.
    var title: String

    var kilocalories: Int
    var macros: MacroTotals
    var items: [RecognisedItem]

    /// What the meal-label rule gives this moment, until the user says
    /// otherwise.
    var label: MealLabel

    /// `true` once the pill has been tapped. It decides whether the commit
    /// writes the label back over the store's own derivation.
    var isLabelUserSet: Bool

    var isFavourite: Bool
}

// MARK: - Model

/// The camera half of the log flow: screen 07, the four analysis states, and
/// screen 14.
///
/// Everything it holds of the photo lives in memory. The frame is captured,
/// compressed, sent and released; no temporary file is written, nothing is
/// logged, and the only place the meal's content is ever written down is the
/// SwiftData entry `commit()` creates.
@MainActor
@Observable
final class CameraLogModel {

    // MARK: - Stage

    /// Which of the camera half's screens is showing.
    nonisolated enum Stage: Equatable, Sendable {

        /// Screen 07 with a working shutter.
        case viewfinder

        /// Screen 07 with no key stored, so no scan can be made. The export
        /// draws no such state; it is built in the same visual language and
        /// its copy is marked `Not in the export` in the catalog.
        case noKey

        /// Screens 08 to 11.
        case analysing(AnalysisStep)

        /// A scan that did not produce an estimate. Also not in the export.
        case failed(AnalysisFailure)

        /// Screen 14. The draft it draws is held separately, so editing a
        /// figure does not rebuild the stage.
        case result
    }

    private(set) var stage: Stage = .viewfinder

    /// The captured frame, kept only while it is being analysed and shown.
    private(set) var photo: UIImage?

    private(set) var draft: PhotoResultDraft?

    /// When the shutter was pressed. Fixed there rather than read again at
    /// `commit()`, so a result screen left open for ten minutes still files
    /// the meal at the time it was eaten.
    private(set) var capturedAt: Date = .distantPast

    // MARK: - Dependencies

    let camera: any MealCamera

    private let store: FuelStore
    private let client: any AIClient
    private let keys: any MealKeyPresence

    /// Which provider the key is looked for under.
    ///
    /// Injected rather than read from a preference, because the stored
    /// provider choice belongs to Settings and this feature must not grow a
    /// second copy of that decision.
    private let provider: AIProvider

    private let now: () -> Date

    /// How long each analysis step is held before the next one.
    ///
    /// Injected so a test can walk all four instantly. The duration itself is
    /// `FuelMotion.analysisStepHold` — the export draws four states and says
    /// nothing about their timing, and a value the design does not dictate
    /// still belongs to the design layer rather than to this initialiser.
    private let pace: @Sendable () async -> Void

    /// The running scan, so `CANCEL` can stop it.
    private var scan: Task<Void, Never>?

    // MARK: - Constants

    /// What one tap of the result stepper is worth, floored at zero.
    ///
    /// From `design/Fuel Design Notes.md`, "Result stepper": ±10 kcal per tap.
    /// It is behaviour rather than geometry, which is why it sits here and not
    /// in `FuelMetrics`.
    static let calorieStep = 10

    init(
        store: FuelStore,
        client: any AIClient,
        camera: any MealCamera,
        keys: any MealKeyPresence = KeychainStore(),
        provider: AIProvider = .claude,
        now: @escaping () -> Date = Date.init,
        pace: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: FuelMotion.analysisStepHold) }
    ) {
        self.store = store
        self.client = client
        self.camera = camera
        self.keys = keys
        self.provider = provider
        self.now = now
        self.pace = pace
    }

    // MARK: - Availability

    /// Whether a scan can be made at all.
    ///
    /// Asked every time the tab appears rather than once at launch: a key can
    /// be removed in Settings while the app is running, and the shutter has to
    /// go dead when it is.
    func refreshAvailability() {
        switch stage {
        case .viewfinder, .noKey:
            stage = keys.hasKey(for: provider) ? .viewfinder : .noKey
        case .analysing, .failed, .result:
            // A scan already in flight is not interrupted by the answer to a
            // question it asked before it started.
            break
        }
    }

    // MARK: - Capturing

    /// Presses the shutter.
    ///
    /// A capture failure is a retry rather than silence: the user pressed
    /// something and nothing happened, and the screen has to say so.
    func capture() async {
        guard keys.hasKey(for: provider) else {
            stage = .noKey
            return
        }
        do {
            analyse(try await camera.capturePhoto())
        } catch {
            stage = .failed(.retry)
        }
    }

    /// Starts a scan of an already-held frame — the shutter, or the picture
    /// the user picked from the gallery.
    func analyse(_ image: UIImage) {
        guard keys.hasKey(for: provider) else {
            stage = .noKey
            return
        }

        photo = image
        capturedAt = now()
        stage = .analysing(.analysingMeal)
        scan = Task { [weak self] in await self?.run(image) }
    }

    /// The `CANCEL` control under the progress bar.
    ///
    /// Cancelling the task is enough: the request comes back as
    /// `AIError.cancelled`, which `AnalysisFailure` refuses to build, and the
    /// flow returns to the viewfinder without saying anything.
    func cancelScan() {
        scan?.cancel()
    }

    // MARK: - The scan

    private func run(_ image: UIImage) async {
        do {
            // Compression happens before anything is sent, and before the
            // steps start walking, so an unsendable photo costs no request.
            let compressed = try MealPhotoCompressor.compress(image)

            let stepper = Task { [weak self] in await self?.walkSteps() }
            let estimate: MealEstimate
            do {
                estimate = try await client.estimate(photo: compressed)
            } catch {
                stepper.cancel()
                _ = await stepper.value
                throw error
            }

            // Awaited rather than only cancelled, so a step cannot land on the
            // stage after the result has replaced it.
            stepper.cancel()
            _ = await stepper.value

            try Task.checkCancellation()
            present(estimate)
        } catch {
            fail(with: error)
        }
    }

    /// Walks steps two to four. The first is set the moment the shutter fires,
    /// and the fourth is held until the answer arrives.
    private func walkSteps() async {
        for step in AnalysisStep.allCases.dropFirst() {
            await pace()
            guard !Task.isCancelled else { return }
            stage = .analysing(step)
        }
    }

    private func present(_ estimate: MealEstimate) {
        draft = PhotoResultDraft(
            title: estimate.title,
            kilocalories: estimate.kilocalories,
            macros: estimate.macros,
            items: estimate.items,
            label: provisionalLabel(at: capturedAt),
            isLabelUserSet: false,
            isFavourite: false
        )
        stage = .result
    }

    private func fail(with error: any Error) {
        // The clients throw `AIError` already; `transportFailure` is here for
        // the structured-concurrency cancellation that can arrive around them.
        let aiError = (error as? AIError) ?? AIError.transportFailure(error)
        guard let failure = AnalysisFailure(aiError) else {
            discard()
            return
        }
        stage = .failed(failure)
    }

    /// What the label will be, unless the user overrules it.
    ///
    /// Derived through `MealLabeler` rather than restated, because the
    /// course-of-the-day rule has exactly one implementation and the result
    /// screen must not become a second one. The claimed set is what the day
    /// has already handed out.
    private func provisionalLabel(at date: Date) -> MealLabel {
        let claimed = (try? store.nutritionEntries(on: date))?
            .reduce(into: Set<MealLabel>()) { $0.insert($1.label) } ?? []
        return MealLabeler(calendar: store.calendar).label(forEntryAt: date, claimedLabels: claimed)
    }

    // MARK: - Editing the result

    /// The `−` and `+` beside the calorie figure. Floored at zero: a negative
    /// meal is not a thing, and the day total would quietly absorb it.
    func adjustKilocalories(by delta: Int) {
        guard var draft else { return }
        draft.kilocalories = max(0, draft.kilocalories + delta)
        self.draft = draft
    }

    /// The label pill. Cycles Breakfast → Lunch → Snack → Dinner and wraps,
    /// through `MealLabel.dayOrder`, and marks the label as the user's so
    /// nothing re-derives it back.
    func cycleLabel() {
        guard var draft else { return }
        draft.label = draft.label.next
        draft.isLabelUserSet = true
        self.draft = draft
    }

    func toggleFavourite() {
        guard var draft else { return }
        draft.isFavourite.toggle()
        self.draft = draft
    }

    // MARK: - Leaving

    /// Writes the meal down. The one place any of this reaches disk.
    ///
    /// The `Bool` says whether the write happened, so the flow stays open on a
    /// failure rather than returning to Today as though a meal had been
    /// logged.
    @discardableResult
    func commit() -> Bool {
        guard let draft else { return false }
        do {
            let entry = try store.log(
                title: draft.title,
                kilocalories: draft.kilocalories,
                macros: draft.macros,
                loggedAt: capturedAt,
                source: .photo,
                isFavourite: draft.isFavourite,
                items: draft.items
            )
            // Only when the pill was actually tapped. Writing the derived
            // label back as the user's would freeze a value they never chose.
            if draft.isLabelUserSet {
                try store.overrideLabel(draft.label, on: entry)
            }
            discard()
            return true
        } catch {
            return false
        }
    }

    /// Throws the scan away and returns to the viewfinder — `New` on the
    /// result screen, the retry state's dismissal, a cancelled analysis.
    ///
    /// The frame is released here. That is the whole lifetime of the photo:
    /// captured, sent, drawn, gone.
    func discard() {
        scan?.cancel()
        scan = nil
        photo = nil
        draft = nil
        stage = keys.hasKey(for: provider) ? .viewfinder : .noKey
    }

    /// The retry state's action: same frame, same request, from the top.
    func retry() {
        guard let photo else {
            discard()
            return
        }
        analyse(photo)
    }
}
