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
    /// it back and `‹ Back` returns to the field the user wrote in. `New`
    /// clears it — that is what makes it a new entry rather than a second go
    /// at the same one. The export draws neither transition; a photo cannot be
    /// edited on the way back, so the camera mode had no version of this
    /// question to answer.
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
        estimation = Task { [weak self] in await self?.run(described) }
    }

    /// The `CANCEL` control under the progress bar.
    ///
    /// Cancelling the task is enough: the request comes back as
    /// `AIError.cancelled`, which `AnalysisFailure` refuses to build, and the
    /// flow returns to the field without saying anything. The sentence is
    /// still in it.
    func cancelEstimate() {
        estimation?.cancel()
    }

    /// The retry state's action: the same sentence, the same request, from the
    /// top.
    func retry() {
        analyse()
    }

    // MARK: - The estimate

    private func run(_ described: String) async {
        do {
            let stepper = Task { [weak self] in await self?.walkSteps() }
            let estimate: MealEstimate
            do {
                estimate = try await client.estimate(text: described)
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

    /// Walks steps two to four. The first is set the moment `Analyse` is
    /// tapped, and the fourth is held until the answer arrives.
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
            label: store.provisionalLabel(at: enteredAt),
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
            returnToEntry()
            return
        }
        stage = .failed(failure)
    }

    // MARK: - Editing the result

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
        estimation?.cancel()
        estimation = nil
        draft = nil
        stage = keys.hasKey(for: provider) ? .entry : .noKey
    }

    /// `New` on the result screen, and what a commit leaves behind: an empty
    /// field, ready for the next meal.
    func discard() {
        typedText = ""
        returnToEntry()
    }
}
