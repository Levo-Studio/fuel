import Foundation

// MARK: - The meal being talked about

/// What a conversation needs from the screen it is attached to: the meal as it
/// now stands, and somewhere to put the result.
///
/// A protocol rather than a closure pair, for the reason `MealKeyPresence` is
/// one: it names the two things this feature is allowed to do to a meal, and a
/// test can answer both without a store.
@MainActor
protocol MealChatSubject: AnyObject {

    /// The meal as it currently stands, read fresh for every message.
    ///
    /// **Fresh, and that is the whole reason this is a property and not an
    /// initialiser argument.** The second message in a conversation is about
    /// the meal the first one produced, so a snapshot taken when the sheet
    /// opened would have the model raising the rice twice from 150 g.
    var adjustableMeal: AdjustableMeal { get }

    /// Writes an adjustment through. `false` if the store refused it, in which
    /// case nothing on screen may claim it happened.
    func apply(_ adjusted: AdjustedMeal) -> Bool
}

// MARK: - One line of the transcript

/// Something that was said, in the shape the sheet draws it.
///
/// **Held in memory for as long as the meal-detail screen is open, and written
/// down nowhere.** See `MealChatModel` for why the transcript is not stored.
nonisolated struct MealChatMessage: Identifiable, Equatable, Sendable {

    nonisolated enum Author: Sendable, Equatable {

        case you
        case fuel
    }

    let id: UUID
    let author: Author

    /// What is drawn, and — for a reply — what travels back to the provider as
    /// the assistant's own turn.
    ///
    /// A reply whose model wrote nothing usable gets a fixed sentence of
    /// Fuel's instead, and that sentence is what the next request carries as
    /// what was said. It is accurate to the conversation the user is looking
    /// at, which is the thing a follow-up is a follow-up to.
    let text: String

    /// The rows this turn moved, for the short list under the sentence. Always
    /// empty on a turn the user wrote, and empty on a reply that moved
    /// nothing — see `movedNothing`.
    let changes: [Change]

    init(id: UUID = UUID(), author: Author, text: String, changes: [Change] = []) {
        self.id = id
        self.author = author
        self.text = text
        self.changes = changes
    }

    /// Whether this is a reply that left the meal exactly as it was.
    ///
    /// **Drawn, rather than left for the user to work out.** A sentence with
    /// no change under it and nothing saying so reads as a change that
    /// happened — which is the one thing a screen that spends the user's
    /// credit must not do.
    var movedNothing: Bool {
        author == .fuel && changes.isEmpty
    }

    /// One row, after the turn moved it.
    nonisolated struct Change: Identifiable, Equatable, Sendable {

        let id: UUID
        let name: String
        let grams: Int?

        init(id: UUID = UUID(), name: String, grams: Int?) {
            self.id = id
            self.name = name
            self.grams = grams
        }
    }
}

// MARK: - Model

/// The conversation on the meal-detail screen: what has been said, what is in
/// flight, and what it did to the meal.
///
/// **Not in the export.** There is no chat anywhere in `design/` — no sheet, no
/// transcript, no field. The whole feature is the owner's instruction, and the
/// sheet it lives in is the platform's own large-detent presentation rather
/// than a surface invented for it. See `MealChatSheet` for what is recomposed
/// from which drawn values.
///
/// **The transcript lives as long as the screen and no longer.** It is not on
/// `FoodEntry`, not in the store, not in a file, and not in a log. Three
/// reasons, in the order they decided it:
///
/// - What a conversation is *for* is the meal it adjusted, and the meal is
///   already an entry. The words are the means; the figures are the artefact,
///   and they persist.
/// - Fuel has no screen that lists past conversations and the export draws
///   none, so a stored transcript would be write-only data — growing on every
///   meal, with no way for the user to read it back and no way to clear it.
/// - The sentences a person types about what they ate are the most personal
///   free text in this app. `CLAUDE.md` says the only place a meal's content
///   is written down is its SwiftData entry; a transcript would be a second
///   place, and one nobody asked for.
///
/// It does survive closing and reopening the sheet, because it belongs to the
/// screen rather than to the presentation — a user who looks something up and
/// comes back has not started a new conversation.
///
/// **Nothing here is ever logged.** Not the message, not the reply, not the
/// meal. `AnalysisFailure` carries no text, and no provider's own words reach
/// the interface.
@MainActor
@Observable
final class MealChatModel {

    // MARK: - Stage

    /// Which of the three things the sheet is showing.
    ///
    /// The analysis states run **inside the sheet** rather than over the screen
    /// behind it, which is where the log flow puts them. The sheet is what the
    /// user is looking at and where `CANCEL` has to be reachable; running the
    /// wait behind a surface that covers it would be a progress bar nobody can
    /// see attached to a cancel nobody can press.
    nonisolated enum Stage: Equatable, Sendable {

        case conversation
        case analysing(AnalysisStep)
        case failed(AnalysisFailure)
    }

    private(set) var stage: Stage = .conversation

    private(set) var messages: [MealChatMessage] = []

    /// What is in the field.
    ///
    /// Clamped rather than validated on send: every character is a token the
    /// user pays for on this request and on every later one in the same
    /// conversation, and a field that stops accepting input is honest in a way
    /// that silently sending less than was typed is not. See
    /// `MealChatContract.maximumMessageLength`.
    var message: String = "" {
        didSet {
            guard message.count > MealChatContract.maximumMessageLength else { return }
            message = String(message.prefix(MealChatContract.maximumMessageLength))
        }
    }

    /// Whether the send control has anything to send.
    var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Dependencies

    private weak var subject: (any MealChatSubject)?

    private let client: any AIClient
    private let keys: any MealKeyPresence
    private let provider: AIProvider
    private let pace: @Sendable () async -> Void

    private var conversation: Task<Void, Never>?

    /// Which message the sheet is currently listening to.
    ///
    /// **Cancelling a `Task` does not stop the answer it is already waiting
    /// on**, so a message the user called off comes back whenever the network
    /// is done with it — and would otherwise write its adjustment over a meal
    /// nobody was still asking about. The same guard is in both log modes and
    /// in `MealDetailModel`, for the same reason.
    private var currentRun = 0

    /// What the last message that was sent said, so `retry()` can send it
    /// again without the user retyping it.
    private var pendingMessage: String?

    /// `messages` is a transcript the conversation opens with, and the only
    /// thing that ever passes one is a preview: the canvas cannot await an
    /// exchange, and a sheet drawn with nothing said in it shows one of the
    /// four states this screen has. Nothing in the app supplies it, and
    /// nothing reads it back out except the sheet.
    init(
        subject: any MealChatSubject,
        client: any AIClient,
        keys: any MealKeyPresence = KeychainStore(),
        provider: AIProvider = .claude,
        pace: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: FuelMotion.analysisStepHold) },
        messages: [MealChatMessage] = []
    ) {
        self.messages = messages
        self.subject = subject
        self.client = client
        self.keys = keys
        self.provider = provider
        self.pace = pace
    }

    // MARK: - Sending

    /// The send control.
    ///
    /// **It only ever runs from a tap**, it refuses an empty field rather than
    /// charging for a request about nothing, and with no key stored it makes
    /// no request at all — the same three rules the two log modes and the
    /// re-analysis hold to, for the same reason: every request spends the
    /// user's own credit.
    func send() {
        let written = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty, subject != nil else { return }

        message = ""
        messages.append(MealChatMessage(author: .you, text: written))
        pendingMessage = written

        // No key, no request — and the transcript survives, because the
        // failure this lands on returns to the conversation rather than
        // throwing it away.
        guard keys.hasKey(for: provider) else {
            stage = .failed(.invalidKey)
            return
        }

        start(written)
    }

    /// The retry state's action: the same message from the top.
    ///
    /// It does not append a second copy of what the user wrote — the turn is
    /// already in the transcript, and a request that failed did not un-say it.
    func retry() {
        guard let pendingMessage else { return }
        guard keys.hasKey(for: provider) else {
            stage = .failed(.invalidKey)
            return
        }
        start(pendingMessage)
    }

    private func start(_ written: String) {
        stage = .analysing(.analysingMeal)
        conversation?.cancel()
        currentRun += 1
        let run = currentRun
        conversation = Task { [weak self] in await self?.exchange(written, as: run) }
    }

    /// The `CANCEL` under the progress bar.
    ///
    /// **Cancelling the task is not enough**, for the reason `currentRun`
    /// exists: retiring the run closes the window in which an answer already
    /// on its way back could still land on a meal the user has stopped asking
    /// about.
    func cancel() {
        conversation?.cancel()
        currentRun += 1
        stage = .conversation
    }

    /// Leaving a failure state, with the transcript still behind it.
    func dismissFailure() {
        stage = .conversation
    }

    /// Stops anything in flight, for a screen that is going away.
    func stopListening() {
        conversation?.cancel()
        currentRun += 1
        conversation = nil
    }

    // MARK: - The request

    private func exchange(_ written: String, as run: Int) async {
        guard let subject else { return }
        let before = subject.adjustableMeal

        do {
            let outcome = try await stepping(before, message: written, as: run)
            try Task.checkCancellation()
            record(outcome, over: before, as: run)
        } catch {
            fail(with: error, as: run)
        }
    }

    /// Walks the four analysis states around one request.
    ///
    /// The fourth copy of this in `Features/LogFlow/` — the two log modes and
    /// `MealDetailModel` each hold one — and a copy on purpose rather than by
    /// neglect, for the reason that file already gives: pulling the pacing out
    /// into something they all share would rewrite three models that are being
    /// reviewed separately. It is a refactor for the owner to call.
    private func stepping(
        _ meal: AdjustableMeal,
        message written: String,
        as run: Int
    ) async throws -> MealAdjustmentOutcome {
        let stepper = Task { [weak self] in await self?.walkSteps(as: run) }
        do {
            let outcome = try await client.adjust(meal, history: history, message: written)
            // Awaited rather than only cancelled, so a step cannot land on the
            // stage after the answer has replaced it.
            stepper.cancel()
            _ = await stepper.value
            return outcome
        } catch {
            stepper.cancel()
            _ = await stepper.value
            throw error
        }
    }

    /// Walks steps two to four, guarded by run identity as well as by its own
    /// cancellation — `currentRun` is bumped synchronously the moment a run is
    /// superseded, before any cancellation has had time to propagate to this
    /// unstructured task.
    private func walkSteps(as run: Int) async {
        for step in AnalysisStep.allCases.dropFirst() {
            await pace()
            guard !Task.isCancelled, isCurrent(run) else { return }
            stage = .analysing(step)
        }
    }

    /// The exchange so far, in the shape a request carries it.
    ///
    /// The turn that is being sent is not in here: `send()` appends the user's
    /// line to the transcript for the sheet to draw, and
    /// `MealChatContract.turn(for:message:)` carries it in the request as the
    /// current question. So the last line is dropped, and what is left is
    /// whole exchanges — the alternation a provider expects, because a turn is
    /// only ever answered into the transcript once its reply has arrived.
    private var history: [MealChatTurn] {
        messages
            .dropLast()
            .map { MealChatTurn(speaker: $0.author == .you ? .user : .model, text: $0.text) }
    }

    // MARK: - The answer

    /// Puts the answer into the transcript, and its adjustment into the store.
    ///
    /// **The store goes first, and the transcript only claims a change that a
    /// write accepted.** A refused write lands on the retry state with the
    /// user's own line still in the transcript, so nothing on screen says a
    /// meal moved that did not — the same order and the same reasoning as
    /// `MealDetailModel.writeBack`.
    ///
    /// An answer that moved nothing is not a failure and is not treated as
    /// one: the model's sentence goes up with `movedNothing` set, and the
    /// sheet says so under it.
    private func record(_ outcome: MealAdjustmentOutcome, over before: AdjustableMeal, as run: Int) {
        guard isCurrent(run), let subject else { return }

        var changes: [MealChatMessage.Change] = []
        if let adjusted = outcome.meal {
            guard subject.apply(adjusted) else {
                // `.device`: the answer arrived and it is the store that
                // refused it. Nothing about the request went wrong.
                stage = .failed(.retry(.device))
                return
            }
            changes = Self.changes(from: before.items, to: adjusted.items)
        }

        messages.append(
            MealChatMessage(
                author: .fuel,
                text: outcome.reply ?? Self.sentence(forSomethingMoved: !changes.isEmpty),
                changes: changes
            )
        )
        pendingMessage = nil
        stage = .conversation
    }

    /// The rows that are different, for the short list under a reply.
    ///
    /// By identity rather than by position: a row that was added has an id
    /// nothing in the previous list had, and a row that moved is the same id
    /// with a different weight or, where the raw annotation was restated, a
    /// different name.
    private static func changes(
        from before: [RecognisedItem],
        to after: [RecognisedItem]
    ) -> [MealChatMessage.Change] {
        let previous = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return after.compactMap { item in
            if let was = previous[item.id], was.weightInGrams == item.weightInGrams, was.name == item.name {
                return nil
            }
            return MealChatMessage.Change(id: item.id, name: item.name, grams: item.weightInGrams)
        }
    }

    /// What a reply reads as when the model wrote no usable sentence.
    ///
    /// Two fixed strings rather than one, because the two states are not the
    /// same thing to a reader and the difference is exactly the one this
    /// feature has to be honest about.
    private static func sentence(forSomethingMoved moved: Bool) -> String {
        moved ? MealChatCopy.adjusted : MealChatCopy.unchanged
    }

    private func isCurrent(_ run: Int) -> Bool {
        run == currentRun
    }

    private func fail(with error: any Error, as run: Int) {
        // A run that is no longer current says nothing at all: its failure
        // belongs to a message the user has already left behind.
        guard isCurrent(run) else { return }
        // The clients throw `AIError` already; `transportFailure` is here for
        // the structured-concurrency cancellation that can arrive around them.
        let aiError = (error as? AIError) ?? AIError.transportFailure(error)
        guard let failure = AnalysisFailure(aiError) else {
            // A cancelled message says nothing, and the conversation is still
            // behind it.
            stage = .conversation
            return
        }
        stage = .failed(failure)
    }
}
