import Foundation
import SwiftUI

// MARK: - Model

/// The camera half of the log flow: screen 07, the four analysis states, and
/// screen 14.
///
/// The frame is captured, compressed and sent; no temporary file is written
/// and nothing is logged. A discarded scan's photo goes no further than that
/// — the in-memory frame is released and nothing about it is ever written
/// down. A committed one does go further: `commit()` passes the same
/// compressed bytes the request carried to the SwiftData entry, so
/// `MealDetailView` can draw the meal's own photograph the way screen 14
/// does. Either way, the SwiftData entry stays the only place any of a meal's
/// content is ever written down at all.
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

    /// The same frame, compressed — the exact bytes the scan sent to the
    /// model, kept so `commit()` can hand them to the store rather than
    /// compressing the photo a second time.
    ///
    /// Set once compression succeeds and untouched by a re-analysis: that
    /// request sends the edited item list, not the photograph, so there is
    /// no fresher compression to replace this with.
    private(set) var capturedPhotoData: Data?

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

    /// Which scan the model is currently listening to.
    ///
    /// **Cancelling a `Task` does not stop the answer it is already waiting
    /// on.** A request suspended inside `URLSession` keeps its socket open
    /// until the provider replies or the connection drops, so a scan the user
    /// cancelled goes on running for as long as the network takes — and then
    /// comes back and writes to `stage`. If a second scan has been started in
    /// the meantime, the first one's late arrival lands on it: its `.cancelled`
    /// runs `dismissFailure()`, which throws the new frame away and cancels the
    /// request that replaced it, and its `.network` puts a failure over a scan
    /// that is still in flight.
    ///
    /// Every run takes a number, and `present`, `represent` and `fail` refuse
    /// to act for a number that is no longer the current one. Cheap, and it is
    /// the only thing that can tell two runs apart — a `Task` handle cannot,
    /// because the stale one is the handle that was overwritten.
    private var currentRun = 0

    /// Whether the request in flight is a re-estimate of an edited breakdown
    /// rather than a scan of the frame.
    ///
    /// It decides two things that differ between the two: what `Try again` on
    /// a failure sends, and where dismissing that failure lands. A re-analysis
    /// has a result screen behind it and a first scan has a viewfinder.
    private var isReanalysing = false

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
            // `.device`: the shutter never produced a frame, so nothing was
            // sent and nothing is owed to the provider.
            stage = .failed(.retry(.device))
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
        scan = start { [weak self] run in await self?.run(image, as: run) }
    }

    /// Starts a run, retires whatever was running before it, and hands the new
    /// run its number.
    ///
    /// The previous task is cancelled as well as retired. Retiring alone would
    /// keep it from writing anything, which is the correctness half; cancelling
    /// is the half that stops the user paying for an answer nobody will read.
    private func start(_ work: @escaping @MainActor (Int) async -> Void) -> Task<Void, Never> {
        scan?.cancel()
        currentRun += 1
        let run = currentRun
        return Task { await work(run) }
    }

    /// Whether `run` is still the scan the screen is waiting for.
    private func isCurrent(_ run: Int) -> Bool {
        run == currentRun
    }

    /// Retires whatever is running, so nothing it comes back with is acted on.
    private func retireRun() {
        scan?.cancel()
        currentRun += 1
    }

    /// The `CANCEL` control under the progress bar.
    ///
    /// **Cancelling the task is not enough, and relying on it was a hole in
    /// the run numbering.** `Task.cancel()` does not stop a request that is
    /// already waiting on a socket, so the old code left the run current and
    /// waited for it to come back as `AIError.cancelled`. A request that
    /// happened to complete in the window between the tap and the
    /// continuation resuming still passed `isCurrent`, and presented a result
    /// over a cancel the user had just made.
    ///
    /// Retiring the run closes that window: from the tap onwards nothing that
    /// request comes back with is acted on, whichever way it lands. Where the
    /// user goes next is the same question as where dismissing a failure
    /// takes them, and has the same answer.
    func cancelScan() {
        retireRun()
        dismissFailure()
    }

    // MARK: - Re-analysing

    /// The footer's `Re-analyse`, which is what `Add` becomes once the user has
    /// changed the breakdown.
    ///
    /// **The photograph is not sent again.** The frame is what produced the
    /// list the user has just corrected, and asking the model to look at it a
    /// second time invites it to re-derive exactly what they overruled — at the
    /// price of the image tokens they are paying for. The edited list is the
    /// better description of the meal, so this goes through the same text
    /// estimate the typed mode uses. There is no second request shape.
    ///
    /// **It only ever runs from a tap.** Nothing here is called when a draft
    /// changes, and the guard on `canReanalyse` means a second press after a
    /// successful re-analysis — or a press over a list with nothing left in it
    /// — is refused rather than charged for.
    func reanalyse() {
        guard let draft, draft.canReanalyse else { return }

        let described = draft.itemSentence

        // No key, no request — and the draft survives, because the failure
        // state this lands on returns to the result screen rather than
        // throwing it away. `missingKey` and a refused key have the same
        // remedy, which is why `AnalysisFailure` already collapses them.
        guard keys.hasKey(for: provider) else {
            isReanalysing = true
            stage = .failed(.invalidKey)
            return
        }

        isReanalysing = true
        stage = .analysing(.analysingMeal)
        scan = start { [weak self] run in await self?.rerun(described, as: run) }
    }

    // MARK: - The scan

    private func run(_ image: UIImage, as run: Int) async {
        do {
            // Compression happens before anything is sent, and before the
            // steps start walking, so an unsendable photo costs no request.
            let compressed = try MealPhotoCompressor.compress(image)
            capturedPhotoData = compressed.jpegData

            let estimate = try await stepping(as: run) { try await self.client.estimate(photo: compressed) }

            try Task.checkCancellation()
            present(estimate, as: run)
        } catch {
            fail(with: error, as: run)
        }
    }

    private func rerun(_ described: String, as run: Int) async {
        do {
            let estimate = try await stepping(as: run) { try await self.client.estimate(text: described) }

            try Task.checkCancellation()
            represent(estimate, as: run)
        } catch {
            fail(with: error, as: run)
        }
    }

    /// Walks the four analysis states around one request.
    ///
    /// Shared by the scan and the re-analysis because the export draws one set
    /// of four states and says nothing about what is being waited on.
    private func stepping(as run: Int, _ request: () async throws -> MealEstimate) async throws -> MealEstimate {
        let stepper = Task { [weak self] in await self?.walkSteps(as: run) }
        do {
            let estimate = try await request()
            // Awaited rather than only cancelled, so a step cannot land on the
            // stage after the result has replaced it.
            stepper.cancel()
            _ = await stepper.value
            return estimate
        } catch {
            stepper.cancel()
            _ = await stepper.value
            throw error
        }
    }

    /// Walks steps two to four. The first is set the moment the shutter fires,
    /// and the fourth is held until the answer arrives.
    ///
    /// **Guarded by run identity, not only by its own cancellation.** This
    /// task is unstructured — `stepping()` creates it with a bare `Task { }`,
    /// not a child task — so cancelling the scan that owns it does not cancel
    /// it. The only thing that reliably stops it is `stepper.cancel()` in
    /// `stepping()`, called once that scan's request has resolved, and there
    /// is a window before that where a superseded run's stepper is still
    /// ticking. `isCurrent(run)` is checked separately from `Task.isCancelled`
    /// for that window: `currentRun` is bumped synchronously the moment a run
    /// is superseded, before any cancellation has had a chance to propagate,
    /// so it closes the window the other check cannot. Both are kept —
    /// `Task.isCancelled` still stops a stepper whose own request has simply
    /// finished.
    ///
    /// Bounded and cosmetic on its own — every stage this can still write is
    /// an analysing step, and both the run it belongs to and the one that
    /// replaced it are showing the same four screens — but it was the one
    /// stage writer the run numbering elsewhere in this file did not reach.
    private func walkSteps(as run: Int) async {
        for step in AnalysisStep.allCases.dropFirst() {
            await pace()
            guard !Task.isCancelled, isCurrent(run) else { return }
            stage = .analysing(step)
        }
    }

    private func present(_ estimate: MealEstimate, as run: Int) {
        guard isCurrent(run) else { return }
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

    /// Puts a re-estimate over the draft, keeping the label and the favourite
    /// mark the user set on it.
    private func represent(_ estimate: MealEstimate, as run: Int) {
        guard isCurrent(run) else { return }
        guard var draft else { return present(estimate, as: run) }
        draft.replaceEstimate(with: estimate)
        self.draft = draft
        isReanalysing = false
        stage = .result
    }

    private func fail(with error: any Error, as run: Int) {
        // A run that is no longer the current one says nothing at all. Its
        // failure belongs to a request the user has already left behind, and
        // acting on it here would take the one that replaced it with it.
        guard isCurrent(run) else { return }
        // The clients throw `AIError` already; `transportFailure` is here for
        // the structured-concurrency cancellation that can arrive around them.
        let aiError = (error as? AIError) ?? AIError.transportFailure(error)
        guard let failure = AnalysisFailure(aiError) else {
            // A cancelled request says nothing. Where that leaves the user
            // depends on what they cancelled, which is what `dismissFailure`
            // already answers.
            dismissFailure()
            return
        }
        stage = .failed(failure)
    }

    /// Leaving a failure state.
    ///
    /// A failed scan has nothing behind it and goes back to the viewfinder. A
    /// failed re-analysis has the result the user was editing behind it, and
    /// their edits are exactly what must not be thrown away by a request that
    /// did not arrive.
    func dismissFailure() {
        guard draft != nil else {
            discard()
            return
        }
        isReanalysing = false
        stage = .result
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
                items: draft.items,
                capturedPhotoData: capturedPhotoData
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

    /// Throws the scan away and returns to the viewfinder: the result screen's
    /// discard control once its confirmation is answered, and a commit that
    /// has just written the meal down.
    ///
    /// A failure state reaches this too, but through `dismissFailure()` rather
    /// than directly — leaving one only throws the scan away when there is no
    /// draft behind it to go back to.
    ///
    /// **This releases the in-memory frame, not the photo behind a meal that
    /// was just committed.** On the discard path — no meal was ever written —
    /// this is the whole lifetime of the photo: captured, sent, drawn, gone.
    /// `commit()` calls this too, but only after `store.log` has already put
    /// the compressed bytes in the entry, so a committed meal keeps its
    /// photograph; what ends here is only this object's own copy of it.
    func discard() {
        retireRun()
        scan = nil
        isReanalysing = false
        photo = nil
        capturedPhotoData = nil
        draft = nil
        stage = keys.hasKey(for: provider) ? .viewfinder : .noKey
    }

    /// The retry state's action: the same request as the one that failed, from
    /// the top — the frame after a scan, the edited list after a re-analysis.
    func retry() {
        if isReanalysing {
            isReanalysing = false
            reanalyse()
            return
        }
        guard let photo else {
            discard()
            return
        }
        analyse(photo)
    }
}
