import Foundation

// MARK: - Model

/// The text half of the log flow: screen 12, the four analysis states, and
/// screen 15.
///
/// The same shape as the camera half without the picture — a key has to be
/// there, a sentence is sent, an estimate comes back editable, and only `Add`
/// writes anything down.
///
/// **The sentence the user typed lives here and nowhere else.** It is not
/// logged, not written to a file, not put in `UserDefaults` and not carried
/// into an error: `AnalysisFailure` has three cases and no text. The only
/// place a meal's content is ever written down is the SwiftData entry
/// `commit()` creates, and even there it is the estimate's title rather than
/// the wording.
///
/// **Without a stored key there is no request to make.** `hasKey(for:)` is
/// asked before the client is touched, and it is the only Keychain call the
/// feature can make — `MealKeyPresence` cannot return a key. A tab drawn in
/// the keyless state that still sent the request would look right and be
/// wrong, so the guard sits on the action rather than on the drawing.
@MainActor
@Observable
final class TextLogModel {

    // MARK: - Stage

    /// Which of the text half's screens is showing.
    nonisolated enum Stage: Equatable, Sendable {

        /// Screen 12 with a working `Analyse` button.
        case entry

        /// Screen 12 with no key stored, so no estimate can be made. The
        /// export draws no such state; it is built in the same visual language
        /// as its camera counterpart and its copy is marked `Not in the
        /// export` in the catalog.
        case noKey

        /// Screens 08 to 11, with nothing behind them — there is no photograph
        /// in this mode to freeze.
        case analysing(AnalysisStep)

        /// An estimate that did not arrive. Also not in the export.
        case failed(AnalysisFailure)

        /// Screen 15. The draft it draws is held separately, so editing a
        /// figure does not rebuild the stage.
        case result
    }

    private(set) var stage: Stage = .entry

    /// What the user has typed. Bound straight to the field on screen 12.
    ///
    /// Kept after the estimate rather than cleared, because screen 15 quotes
    /// it back and `‹ Back` returns to the field the user wrote in.
    /// Discarding clears it — that is what makes the next one a new entry
    /// rather than a second go at the same one. The export draws neither
    /// transition; a photo cannot be edited on the way back, so the camera
    /// mode had no version of this question to answer.
    ///
    /// A re-analysis does not touch it. What it sends is the edited item list,
    /// and overwriting the user's own sentence with a list Fuel assembled
    /// would put words in the quote that they never typed.
    var typedText: String = ""

    private(set) var draft: MealResultDraft?

    /// When `Analyse` was tapped. Fixed there rather than read again at
    /// `commit()`, so a result screen left open for ten minutes still files
    /// the meal at the time it was eaten.
    private(set) var enteredAt: Date = .distantPast

    // MARK: - Dependencies

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

    /// How long each analysis step is held before the next one. Injected so a
    /// test can walk all four instantly; the duration itself is
    /// `FuelMotion.analysisStepHold`.
    private let pace: @Sendable () async -> Void

    /// The running estimate, so `CANCEL` can stop it.
    private var estimation: Task<Void, Never>?

    /// Which estimate the model is currently listening to.
    ///
    /// **Cancelling a `Task` does not stop the answer it is already waiting
    /// on.** A request suspended inside `URLSession` keeps its socket open
    /// until the provider replies or the connection drops, so a scan the user
    /// cancelled goes on running for as long as the network takes — and then
    /// comes back and writes to `stage`. If a second estimate has been started
    /// in the meantime, the first one's late arrival lands on it: its
    /// `.cancelled` runs `dismissFailure()`, which cancels the request that
    /// replaced it and puts the user back in the field with no explanation, and
    /// its `.network` puts a failure over an estimate that is still in flight.
    ///
    /// Every run takes a number, and `present`, `represent` and `fail` refuse
    /// to act for a number that is no longer the current one. Cheap, and it is
    /// the only thing that can tell two runs apart — a `Task` handle cannot,
    /// because the stale one is the handle that was overwritten.
    private var currentRun = 0

    /// Whether the request in flight is a re-estimate of an edited breakdown
    /// rather than the sentence the user typed.
    ///
    /// It decides two things that differ between the two: what `Try again` on
    /// a failure sends, and where dismissing that failure lands. A re-analysis
    /// has a result screen behind it and a first estimate has the field.
    private var isReanalysing = false

    init(
        store: FuelStore,
        client: any AIClient,
        keys: any MealKeyPresence = KeychainStore(),
        provider: AIProvider = .claude,
        now: @escaping () -> Date = Date.init,
        pace: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: FuelMotion.analysisStepHold) }
    ) {
        self.store = store
        self.client = client
        self.keys = keys
        self.provider = provider
        self.now = now
        self.pace = pace
    }

    // MARK: - Availability

    /// Whether an estimate can be made at all.
    ///
    /// Asked every time the tab appears rather than once at launch: a key can
    /// be removed in Settings while the app is running, and the button has to
    /// go dead when it is.
    func refreshAvailability() {
        switch stage {
        case .entry, .noKey:
            stage = keys.hasKey(for: provider) ? .entry : .noKey
        case .analysing, .failed, .result:
            // An estimate already in flight is not interrupted by the answer
            // to a question it asked before it started.
            break
        }
    }

    // MARK: - Estimating

    /// The sentence as it would be sent: the field's text without the spaces
    /// and newlines around it.
    ///
    /// A field holding a space is an empty field to the person looking at it,
    /// and sending it would spend a request on nothing.
    private var describedMeal: String {
        typedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The `Analyse` button.
    ///
    /// The button is drawn the way the export draws it whether or not the
    /// field has anything in it — the design has no second state for it, and
    /// inventing a dimmed one would be a deviation — so an empty field is
    /// refused here, the way the onboarding screen refuses an empty key.
    func analyse() {
        guard keys.hasKey(for: provider) else {
            stage = .noKey
            return
        }
        let described = describedMeal
        guard !described.isEmpty else { return }

        enteredAt = now()
        stage = .analysing(.analysingMeal)
        estimation = start { [weak self] run in await self?.run(described, as: run) }
    }

    /// Starts a run, retires whatever was running before it, and hands the new
    /// run its number.
    ///
    /// The previous task is cancelled as well as retired. Retiring alone would
    /// keep it from writing anything, which is the correctness half; cancelling
    /// is the half that stops the user paying for an answer nobody will read.
    private func start(_ work: @escaping @MainActor (Int) async -> Void) -> Task<Void, Never> {
        estimation?.cancel()
        currentRun += 1
        let run = currentRun
        return Task { await work(run) }
    }

    /// Whether `run` is still the estimate the screen is waiting for.
    private func isCurrent(_ run: Int) -> Bool {
        run == currentRun
    }

    /// Retires whatever is running, so nothing it comes back with is acted on.
    private func retireRun() {
        estimation?.cancel()
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
    func cancelEstimate() {
        retireRun()
        dismissFailure()
    }

    /// The retry state's action: the same request as the one that failed, from
    /// the top — the typed sentence after an estimate, the edited list after a
    /// re-analysis.
    func retry() {
        if isReanalysing {
            isReanalysing = false
            reanalyse()
            return
        }
        analyse()
    }

    // MARK: - Re-analysing

    /// The footer's `Re-analyse`, which is what `Add` becomes once the user has
    /// changed the breakdown.
    ///
    /// **The edited list is sent, not the sentence.** The list is what the user
    /// has just corrected, and the sentence is what produced the version they
    /// corrected. The sentence itself is untouched — screen 15 still quotes
    /// back what they wrote, and `‹ Back` still returns them to it.
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
        estimation = start { [weak self] run in await self?.rerun(described, as: run) }
    }

    // MARK: - The estimate

    private func run(_ described: String, as run: Int) async {
        do {
            let estimate = try await stepping(described, as: run)

            try Task.checkCancellation()
            present(estimate, as: run)
        } catch {
            fail(with: error, as: run)
        }
    }

    private func rerun(_ described: String, as run: Int) async {
        do {
            let estimate = try await stepping(described, as: run)

            try Task.checkCancellation()
            represent(estimate, as: run)
        } catch {
            fail(with: error, as: run)
        }
    }

    /// Walks the four analysis states around one request.
    ///
    /// Shared by the first estimate and the re-analysis because the export
    /// draws one set of four states and says nothing about what is being
    /// waited on.
    private func stepping(_ described: String, as run: Int) async throws -> MealEstimate {
        let stepper = Task { [weak self] in await self?.walkSteps(as: run) }
        do {
            let estimate = try await client.estimate(text: described)
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

    /// Walks steps two to four. The first is set the moment `Analyse` is
    /// tapped, and the fourth is held until the answer arrives.
    ///
    /// **Guarded by run identity, not only by its own cancellation.** This
    /// task is unstructured — `stepping()` creates it with a bare `Task { }`,
    /// not a child task — so cancelling the estimate that owns it does not
    /// cancel it. The only thing that reliably stops it is `stepper.cancel()`
    /// in `stepping()`, called once that estimate's request has resolved, and
    /// there is a window before that where a superseded run's stepper is
    /// still ticking. `isCurrent(run)` is checked separately from
    /// `Task.isCancelled` for that window: `currentRun` is bumped
    /// synchronously the moment a run is superseded, before any cancellation
    /// has had a chance to propagate, so it closes the window the other check
    /// cannot. Both are kept — `Task.isCancelled` still stops a stepper whose
    /// own request has simply finished.
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
            label: store.provisionalLabel(at: enteredAt),
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
    /// A failed estimate has the field behind it and goes back to it, with the
    /// sentence still in it. A failed re-analysis has the result the user was
    /// editing behind it, and their edits are exactly what must not be thrown
    /// away by a request that did not arrive.
    func dismissFailure() {
        guard draft != nil else {
            returnToEntry()
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
                loggedAt: enteredAt,
                source: .text,
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

    /// `‹ Back` from the result, and a cancelled estimate: the draft goes, the
    /// sentence stays, and the user is back in the field they wrote it in.
    func returnToEntry() {
        retireRun()
        estimation = nil
        isReanalysing = false
        draft = nil
        stage = keys.hasKey(for: provider) ? .entry : .noKey
    }

    /// The result screen's discard control once its confirmation is answered,
    /// and what a commit leaves behind: an empty field, ready for the next
    /// meal.
    func discard() {
        typedText = ""
        returnToEntry()
    }
}
