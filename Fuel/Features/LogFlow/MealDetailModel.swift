import Foundation

// MARK: - Model

/// The result screen driven from a meal that is already in the store.
///
/// **The screen is screens 14 and 15 unchanged** — `MealResultView`, with the
/// same rows, the same remove marks, the same `Add item` row and the same
/// `Add`-becomes-`Re-analyse` rule. What differs is entirely in here: there is
/// no photo and no sentence above the label pill, nothing to discard, and the
/// footer's verb is `Delete`.
///
/// **The three kinds of change are written back at three different moments,
/// and the difference is deliberate.**
///
/// - The label and the favourite mark go to the store the moment they are
///   tapped. They are decisions about the meal that stand on their own, and a
///   store that refused one leaves the draft alone, so what is drawn is always
///   what is stored.
/// - An item edit is written back by nothing. The figures above the list are
///   the estimate's, and an edited list with the old figures over it is exactly
///   the state `MealResultDraft.hasItemEdits` exists to put `Re-analyse` in
///   front of. Leaving on `‹ Back` with edits pending therefore leaves the
///   stored meal as it was, which is the honest reading of a correction the
///   user never asked to be priced.
/// - The re-analysis writes the whole estimate, in place. See
///   `FuelStore.update` for why in place and not a new row.
///
/// **Nothing here re-analyses on its own.** `reanalyse()` runs from a tap,
/// refuses an unchanged list, and asks the Keychain whether a key exists before
/// the client is touched — the same three rules the two log modes hold to, for
/// the same reason: every request spends the user's own credit.
///
/// **Nothing is ever logged.** The meal's title, its items and the sentence
/// assembled from them stay in this object and in the entry; no `print`, no
/// file, and `AnalysisFailure` carries no text.
@MainActor
@Observable
final class MealDetailModel {

    // MARK: - Stage

    /// Which screen is showing.
    ///
    /// Three cases and no `deleted`: a deletion ends with the screen gone, and
    /// `delete()` reports that to the caller rather than parking the model on a
    /// state whose only job is to be dismissed.
    nonisolated enum Stage: Equatable, Sendable {

        /// The result screen, on a meal that is already logged.
        case detail

        /// Screens 08 to 11, with nothing behind them: a stored meal is
        /// re-estimated from its item list, and there is no frame to freeze.
        case analysing(AnalysisStep)

        /// A re-analysis that did not arrive. Not in the export.
        case failed(AnalysisFailure)
    }

    private(set) var stage: Stage = .detail

    /// What the screen draws. Seeded from the entry and, from then on, the only
    /// thing the user edits.
    private(set) var draft: MealResultDraft

    // MARK: - Dependencies

    /// The row this screen was opened on. Held rather than re-fetched, so every
    /// write lands on the meal the user tapped even if the day changes
    /// underneath.
    private let entry: FoodEntry

    private let store: FuelStore
    private let client: any AIClient
    private let keys: any MealKeyPresence

    /// Which provider the key is looked for under, injected for the reason the
    /// log modes take it: the stored choice belongs to Settings, and a second
    /// copy of that decision here would drift.
    private let provider: AIProvider

    /// How long each analysis step is held. Injected so a test can walk all
    /// four instantly.
    private let pace: @Sendable () async -> Void

    private var estimation: Task<Void, Never>?

    /// Which re-analysis the screen is currently listening to.
    ///
    /// **Cancelling a `Task` does not stop the answer it is already waiting
    /// on.** A request suspended inside `URLSession` keeps its socket open
    /// until the provider replies, so a re-analysis the user cancelled comes
    /// back whenever the network is done with it — and writes to `stage`. If a
    /// second one has been started in the meantime, the first one's late
    /// arrival lands on it: it puts the screen back on the meal, or a failure
    /// over a request that is still in flight. The same guard is in both log
    /// modes, for the same reason.
    private var currentRun = 0

    /// `nil` when there is no such meal — it was deleted on another screen, or
    /// the store cannot be read. A failable initialiser rather than an empty
    /// screen, because there is no drawn state for a detail screen with no
    /// meal behind it.
    init?(
        entryID: UUID,
        store: FuelStore,
        client: any AIClient,
        keys: any MealKeyPresence = KeychainStore(),
        provider: AIProvider = .claude,
        pace: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: FuelMotion.analysisStepHold) }
    ) {
        guard let entry = (try? store.entry(withID: entryID)) ?? nil else { return nil }

        self.entry = entry
        self.store = store
        self.client = client
        self.keys = keys
        self.provider = provider
        self.pace = pace
        self.draft = MealResultDraft(
            title: entry.title,
            kilocalories: entry.kilocalories,
            macros: entry.macros,
            items: entry.items,
            label: entry.label,
            isLabelUserSet: entry.isLabelUserSet,
            isFavourite: entry.isFavourite
        )
    }

    // MARK: - Editing the breakdown

    /// The `✕` on a row, the row itself, and the `Add item` row under the list.
    ///
    /// All three are the draft's operations, so the rule they share — the list
    /// has changed, so the estimate above it is stale — is the one written on
    /// `MealResultDraft` and not a second copy of it here.
    func removeItem(_ id: RecognisedItem.ID) {
        draft.removeItem(id)
    }

    func editItem(_ id: RecognisedItem.ID, to text: String) {
        draft.editItem(id, to: text)
    }

    func addItem(_ text: String) {
        draft.addItem(text)
    }

    // MARK: - Editing the meal

    /// The label pill. Cycles Breakfast → Lunch → Snack → Dinner and wraps.
    ///
    /// Written through immediately, and the draft follows the store rather than
    /// leading it: a cycle the store refused would otherwise leave the pill
    /// showing a meal the day list does not file the entry under.
    ///
    /// `overrideLabel` marks the entry as the user's, which is what it is — the
    /// pill was tapped — so nothing re-derives it back.
    func cycleLabel() {
        let next = draft.label.next
        do {
            try store.overrideLabel(next, on: entry)
        } catch {
            return
        }
        draft.label = next
        draft.isLabelUserSet = true
    }

    /// The ☆ / ★ control, written through for the same reason the pill is.
    func toggleFavourite() {
        let next = !draft.isFavourite
        do {
            try store.setFavourite(next, on: entry)
        } catch {
            return
        }
        draft.isFavourite = next
    }

    // MARK: - Re-analysing

    /// The footer's `Re-analyse`, which is what `Delete` becomes once the user
    /// has changed the breakdown.
    ///
    /// The edited list is what is sent — the same sentence the log modes send,
    /// assembled by `MealResultDraft.itemSentence`. There is no original
    /// sentence to fall back on: the meal it was made from was a photograph, a
    /// sentence the flow no longer holds, or a meal repeated from the Recent
    /// list.
    ///
    /// **It only ever runs from a tap**, it refuses a list that is unchanged
    /// or empty rather than charging for a request about nothing, and with no
    /// key stored it makes no request at all.
    func reanalyse() {
        // The same rule the footer reads, so a press that reaches here is a
        // press the button was honestly offering.
        guard draft.canReanalyse else { return }

        let described = draft.itemSentence

        // No key, no request — and the draft survives, because the failure this
        // lands on returns to the meal rather than throwing the edits away.
        guard keys.hasKey(for: provider) else {
            stage = .failed(.invalidKey)
            return
        }

        stage = .analysing(.analysingMeal)
        estimation?.cancel()
        currentRun += 1
        let run = currentRun
        estimation = Task { [weak self] in await self?.rerun(described, as: run) }
    }

    /// The `CANCEL` under the progress bar.
    ///
    /// **Cancelling the task is not enough.** `Task.cancel()` does not stop a
    /// request already waiting on a socket, so leaving the run current meant a
    /// request that completed in the window between the tap and the
    /// continuation resuming still passed `isCurrent` — and wrote a fresh
    /// estimate over a meal the user had just stopped re-analysing. Retiring
    /// the run closes that window; the screen returns to the meal with its
    /// edits intact either way.
    func cancelReanalysis() {
        estimation?.cancel()
        currentRun += 1
        stage = .detail
    }

    /// The retry state's action: the same request from the top.
    func retry() {
        reanalyse()
    }

    /// Leaving a failure state. There is only one thing behind it — the meal
    /// the user was editing — and their edits are exactly what a request that
    /// did not arrive must not cost them.
    func dismissFailure() {
        stage = .detail
    }

    // MARK: - The request

    private func rerun(_ described: String, as run: Int) async {
        do {
            let estimate = try await stepping(described)

            try Task.checkCancellation()
            writeBack(estimate, as: run)
        } catch {
            fail(with: error, as: run)
        }
    }

    /// Walks the four analysis states around one request.
    ///
    /// The third copy of this in `Features/LogFlow/` — the two log modes each
    /// hold one — and it is a copy on purpose rather than by neglect: pulling
    /// the pacing out into something all three share would rewrite both of
    /// them, and both are being reviewed by someone else. It is a refactor for
    /// the owner to call, not one to slip into a feature.
    private func stepping(_ described: String) async throws -> MealEstimate {
        let stepper = Task { [weak self] in await self?.walkSteps() }
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

    /// Walks steps two to four. The first is set the moment `Re-analyse` is
    /// tapped, and the fourth is held until the answer arrives.
    private func walkSteps() async {
        for step in AnalysisStep.allCases.dropFirst() {
            await pace()
            guard !Task.isCancelled else { return }
            stage = .analysing(step)
        }
    }

    /// Puts the fresh estimate over the stored meal and over the draft, in that
    /// order.
    ///
    /// **The store goes first, and the draft only follows a write that
    /// succeeded.** The alternative is a screen showing figures the store does
    /// not hold, which the user would find out about the next time they opened
    /// Today. A refused write lands on the retry state with the edits still in
    /// place, so the footer still reads `Re-analyse` and nothing has been lost
    /// — at the cost of a second request if they take it.
    private func writeBack(_ estimate: MealEstimate, as run: Int) {
        guard isCurrent(run) else { return }
        do {
            try store.update(
                entry,
                title: estimate.title,
                kilocalories: estimate.kilocalories,
                macros: estimate.macros,
                items: estimate.items
            )
        } catch {
            // `.device`: the estimate arrived and it is the store that
            // refused it. Nothing about the request went wrong.
            stage = .failed(.retry(.device))
            return
        }
        // Keeps the label, whether the user set it, and the favourite mark.
        draft.replaceEstimate(with: estimate)
        stage = .detail
    }

    /// Whether `run` is still the re-analysis the screen is waiting for.
    private func isCurrent(_ run: Int) -> Bool {
        run == currentRun
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
            // A cancelled re-analysis says nothing, and the meal is still
            // behind it.
            stage = .detail
            return
        }
        stage = .failed(failure)
    }

    // MARK: - Deleting

    /// The footer's `Delete`, once its confirmation has been answered.
    ///
    /// **`ModelContext.delete` is an ask-first operation in this repository and
    /// the owner has asked for it.** The confirmation is the view's — the
    /// system dialog, exactly as the discard control uses on the scan screens —
    /// and nothing is lost until it is answered.
    ///
    /// The `Bool` says whether the row actually went, so the screen stays open
    /// on a store that refused rather than returning to Today as though the
    /// meal had been thrown away.
    @discardableResult
    func delete() -> Bool {
        // A re-analysis in flight is about to be about a meal that is gone.
        estimation?.cancel()
        currentRun += 1
        estimation = nil
        do {
            try store.delete(entry)
            return true
        } catch {
            return false
        }
    }
}
