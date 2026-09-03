import Foundation
import SwiftUI

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

    private(set) var draft: MealResultDraft?

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
        draft = MealResultDraft(
            title: estimate.title,
            kilocalories: estimate.kilocalories,
            macros: estimate.macros,
            items: estimate.items,
            label: store.provisionalLabel(at: capturedAt),
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

    // MARK: - Editing the result

    /// The breakdown's own controls: the `✕` on a row, the row itself, and the
    /// `Add item` row under the list.
    ///
    /// All three are the draft's operations rather than this model's, so the
    /// rule they share — the list has been changed, so the estimate above it is
    /// stale — is written once and holds for every screen that draws a draft.
    func removeItem(_ id: RecognisedItem.ID) {
        guard var draft else { return }
        draft.removeItem(id)
        self.draft = draft
    }

    func editItem(_ id: RecognisedItem.ID, to text: String) {
        guard var draft else { return }
        draft.editItem(id, to: text)
        self.draft = draft
    }

    func addItem(_ text: String) {
        guard var draft else { return }
        draft.addItem(text)
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
