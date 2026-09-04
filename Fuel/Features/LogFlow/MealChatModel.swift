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

    /// The reply that is still arriving, as far as it has been written.
    ///
    /// **`nil` and empty are different, and the difference is what the sheet
    /// draws.** `nil` is a conversation with nothing in flight. Empty is a
    /// message that has been sent and has not yet produced a word — the moment
    /// the sheet says it is writing. Anything else is the sentence so far.
    ///
    /// It is set to whole sentences rather than accumulated from deltas here,
    /// so a screen cannot get the accumulation wrong and a bound applied on the
    /// way in cannot be undone by the next word. See `MealChatEvent.sentence`.
    ///
    /// **It never becomes a transcript line.** What lands in `messages` is the
    /// sentence from the finished turn, parsed out of the complete object; this
    /// is thrown away when the turn ends, whichever way it ends. A stream that
    /// dies half-way through a sentence leaves nothing behind — see
    /// `fail(with:as:)`.
    private(set) var arrivingReply: String?

    /// Whether a message is in flight.
    ///
    /// The composer reads it to offer a stop rather than a send. That control
    /// is the only way out of a wait now that a question is answered without
    /// the analysis states, which is where `CANCEL` used to be.
    var isAnswering: Bool {
        arrivingReply != nil
    }

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

    /// `messages` is a transcript the conversation opens with, and `arriving`
    /// a reply caught half-written. The only thing that ever passes either is a
    /// preview: the canvas cannot await an exchange, and a sheet drawn with
    /// nothing said in it shows one of the states this screen has. Nothing in
    /// the app supplies them, and nothing reads them back out except the sheet.
    init(
        subject: any MealChatSubject,
        client: any AIClient,
        keys: any MealKeyPresence = KeychainStore(),
        provider: AIProvider = .claude,
        pace: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: FuelMotion.analysisStepHold) },
        messages: [MealChatMessage] = [],
        arriving: String? = nil
    ) {
        self.messages = messages
        self.arrivingReply = arriving
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
        // One message at a time. The composer draws a stop rather than a send
        // while one is in flight, and the keyboard's own return key is the
        // other way in here.
        guard !written.isEmpty, !isAnswering, subject != nil else { return }

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

    /// **The analysis states no longer start here**, and that is the whole of
    /// what the owner asked for.
    ///
    /// A message is a question or an adjustment, and Fuel cannot know which
    /// until the model begins answering. Running the four states over both
    /// meant "is this a lot of protein?" got a progress bar, four labels about
    /// identifying ingredients, and then a sentence — theatre over a question
    /// that moved nothing.
    ///
    /// So every message begins in the conversation, with a reply row that says
    /// it is writing, and the states are raised only by
    /// `MealChatEvent.adjusting` — the model's own `changes` or `additions`,
    /// seen in the stream before the reply has finished. A question never
    /// reaches that event and never sees a step. The states that do run still
    /// stand for elapsed work, because the request is still in flight when they
    /// start; the alternative shape considered — wait in silence, then run the
    /// four states once the answer is already in hand — would have made them
    /// stand for nothing.
    private func start(_ written: String) {
        stage = .conversation
        arrivingReply = ""
        conversation?.cancel()
        currentRun += 1
        let run = currentRun
        conversation = Task { [weak self] in await self?.exchange(written, as: run) }
    }

    /// The `CANCEL` under the progress bar, and the composer's stop mark.
    ///
    /// **Cancelling the task is not enough**, for the reason `currentRun`
    /// exists: retiring the run closes the window in which an answer already
    /// on its way back could still land on a meal the user has stopped asking
    /// about.
    func cancel() {
        conversation?.cancel()
        currentRun += 1
        arrivingReply = nil
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
        arrivingReply = nil
    }

    // MARK: - The request

    /// One turn, read as it arrives.
    ///
    /// The three events are the three things that can happen on the way to an
    /// answer, and each is handled where it lands rather than gathered up and
    /// applied at the end: a sentence is drawn, a committed change raises the
    /// analysis states, and the finished turn is what `record` writes through.
    ///
    /// **The run is checked on every event, not only at the end.** A message
    /// the user called off must not go on writing into the sheet while the
    /// connection winds down.
    private func exchange(_ written: String, as run: Int) async {
        guard let subject else { return }
        let before = subject.adjustableMeal
        var stepper: Task<Void, Never>?

        do {
            var outcome: MealAdjustmentOutcome?

            for try await event in client.adjust(before, history: history, message: written) {
                guard isCurrent(run) else { return }

                switch event {
                case .sentence(let sentence):
                    arrivingReply = sentence

                case .adjusting:
                    guard stepper == nil else { break }
                    stage = .analysing(.analysingMeal)
                    stepper = Task { [weak self] in await self?.walkSteps(as: run) }

                case .finished(let value):
                    outcome = value
                }
            }

            try Task.checkCancellation()
            await settle(stepper)

            // A stream that finished without saying so is a reply Fuel could
            // not read, which is what the retry state is for.
            guard let outcome else {
                throw AIError.malformedResponse
            }
            record(outcome, over: before, as: run)
        } catch {
            await settle(stepper)
            fail(with: error, as: run)
        }
    }

    /// Lets the paced walk finish before the stage moves on.
    ///
    /// Awaited rather than only cancelled, so a step cannot land on the stage
    /// after the answer has replaced it.
    ///
    /// The pacing itself is the fourth copy in `Features/LogFlow/` — the two
    /// log modes and `MealDetailModel` each hold one — and a copy on purpose
    /// rather than by neglect, for the reason that file already gives: pulling
    /// it out into something they all share would rewrite three models that are
    /// being reviewed separately. It is a refactor for the owner to call.
    private func settle(_ stepper: Task<Void, Never>?) async {
        stepper?.cancel()
        _ = await stepper?.value
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

        // Whatever happens below, nothing is still arriving. The sentence that
        // lands in the transcript comes from the complete object rather than
        // from what was drawn on the way — the two agree, and the complete one
        // is the one that was parsed.
        arrivingReply = nil

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

        // **A sentence that stopped in the middle is not an answer**, and a
        // stream that died half-way through one must not leave it on screen
        // with nothing to say what happened. It is dropped and the failure is
        // shown — the same rule `MealChatContract.maximumReplyLength` states
        // for the other way a sentence can be unusable: dropped rather than
        // truncated, because a sentence cut short stops mid-word with nothing
        // under it to make sense of it. Nothing is lost that the user can act
        // on: `Try again` re-sends the same message.
        arrivingReply = nil

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
