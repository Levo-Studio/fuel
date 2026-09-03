import Foundation
import Observation

// MARK: - Model

/// The state behind screens 01 to 04.
///
/// It owns the whole flow rather than one screen each, because the four screens
/// are one decision with three intermediate states: the provider chosen on 01
/// names the model on 02 and 03, and the key typed on 01 is what 02 is testing.
/// Splitting that across three models would mean passing the draft key between
/// them, which is the last value that should be travelling anywhere.
///
/// **Nothing here is ever logged.** Not the key, not a prefix, not its length,
/// not whether one is present. There is no `print`, no `Logger`, and no
/// `#if DEBUG` exception — a build configuration is not a security boundary.
/// The redacted `description` and empty mirror at the bottom of the file close
/// the accidental routes as well.
@MainActor
@Observable
final class OnboardingModel {

    // MARK: - Stage

    /// Which of the four screens is on show. Screens 02 and 03 are one stage in
    /// two phases — the same layout, drawn with different step markers — which
    /// is why there are three stages and not four.
    enum Stage: Equatable {
        case key
        case keyTest
        case goal
    }

    // MARK: - Steps

    /// The four rows of the key test, in the order the design lists them.
    enum Step: CaseIterable, Equatable {
        case openingConnection
        case sendingTestRequest
        case responseReceived
        case modelReady
    }

    /// How a step's 20pt marker slot is drawn: a check, a spinner ring, or a
    /// dot.
    enum StepState: Equatable {
        case done
        case active
        case pending
    }

    // MARK: - Failure

    /// Why the key test stopped short.
    ///
    /// `format` is separate from the three network outcomes because it costs no
    /// request — it is the offline check speaking — and because it names a
    /// mistake the user can see in what they typed.
    enum Failure: Equatable {
        case format(APIKeyFormatVerdict.Problem)
        case invalidKey
        case noCredit
        case network

        /// The Keychain refused to hold the key. The test itself passed, so
        /// this is not a verdict on the key; without a stored key the app
        /// cannot go on, so it stops here rather than moving to screen 04 and
        /// discovering it at the first photo.
        case storageFailed
    }

    /// The phase the key-test screen is in. Screen 02 is `running`, screen 03
    /// is `passed`, and `failed` is the state the design notes specify and the
    /// screens do not draw.
    enum Phase: Equatable {
        case running
        case passed
        case failed(Failure)
    }

    // MARK: - Dependencies

    private let keychain: KeychainStore
    private let validator: KeyValidating
    private let store: FuelStore

    /// Where the provider choice lives.
    ///
    /// The segment on screen 01 and the segment on screen 16 are one decision
    /// asked twice, so they are one stored value and not two. This model held
    /// its own copy before, wrote the key into the Keychain under it, and never
    /// passed it on — a user who chose Mistral got a valid Mistral key, a
    /// preference still saying Claude, and a shutter and an `Analyse` button
    /// that both went looking for a Claude key that did not exist.
    ///
    /// Writing the preference on completion would have closed that, and would
    /// have left two values that have to be kept in step. Reading and writing
    /// straight through leaves nothing to keep in step: there is one provider
    /// in the app, and Settings is already bound to it.
    private let preferences: SettingsPreferences

    /// How long one passed step rests before the next is ticked off.
    ///
    /// The test is a single call, so the four rows cannot be driven by real
    /// progress. They are not faked either: a passed call did perform all four,
    /// and this only paces the reveal of something already known to be true.
    /// The value is the design layer's own key-test duration rather than a
    /// number chosen here, and tests pass zero so a suite never waits on it.
    private let stepInterval: Duration

    /// Called once the goal settings are written and onboarding is over.
    private let onFinished: () -> Void

    // MARK: - State

    private(set) var stage: Stage = .key

    /// Which segment on screen 01 is selected.
    ///
    /// Not stored here. It is the preference itself, so the choice the user
    /// makes on screen 01 is the choice the log flow reads when it opens and
    /// the choice screen 16 draws — including after the user has changed it
    /// twice and gone back a screen, because there is only ever the one value
    /// to change. Claude is the default the preference already carries, and is
    /// the selected segment in every frame of the export.
    var provider: AIProvider { preferences.provider }

    /// What the user has typed into the secure field.
    ///
    /// A `String` because that is what a `SecureField` binds to; it is wrapped
    /// in an `APIKey` the moment it is used for anything, and cleared as soon
    /// as the key is safely in the Keychain, so the draft does not sit in
    /// memory for the rest of onboarding.
    var keyDraft: String = ""

    private(set) var phase: Phase = .running

    /// How many of the four steps are ticked off. The step after them is the
    /// active one while the phase is `running`.
    private(set) var completedSteps: Int = 0

    /// Screen 04's selection. Goal mode is the drawn default — its card is the
    /// expanded one, and its dot is the filled one.
    private(set) var countsAgainstGoal = true

    /// The goal values, starting from the defaults in the design notes.
    var targets: DailyTargets = .default

    /// The in-flight test call.
    ///
    /// Held so `returnToKeyEntry` can cancel it — a user who taps `Cancel` and
    /// starts editing must not have the previous answer land on top of them a
    /// second later. Readable so a test can await the call it just started
    /// instead of sleeping and hoping.
    private(set) var validation: Task<Void, Never>?

    // MARK: - Creation

    init(
        keychain: KeychainStore = KeychainStore(),
        validator: KeyValidating,
        store: FuelStore,
        preferences: SettingsPreferences,
        stepInterval: Duration = .seconds(FuelMotion.progress.duration),
        onFinished: @escaping () -> Void = {}
    ) {
        self.keychain = keychain
        self.validator = validator
        self.store = store
        self.preferences = preferences
        self.stepInterval = stepInterval
        self.onFinished = onFinished
    }

    // MARK: - Screen 01

    /// Switches the provider segment.
    ///
    /// The draft is dropped rather than carried across, and the other
    /// provider's *stored* key is deliberately not read back into the field.
    /// Both halves matter: a half-typed Claude key must not reappear under
    /// Mistral, and a key already in the Keychain has no reason to be pulled
    /// back out into a `String` just to be looked at. Each provider keeps its
    /// own Keychain entry, so switching loses nothing that was saved.
    ///
    /// The Keychain is not touched here at all — not the entry being left and
    /// not the one being arrived at. Switching is a preference write and
    /// nothing else, which is what lets a user who holds both keys move
    /// between them without losing either.
    func selectProvider(_ provider: AIProvider) {
        guard provider != self.provider else { return }
        preferences.provider = provider
        keyDraft = ""
    }

    /// Leaves screen 01 for the key test.
    ///
    /// The offline format check runs first and, when it rejects, no validator
    /// is called at all — that is the whole point of having it, so an obvious
    /// typo never costs the user a request. The rejection still moves to the
    /// key-test screen, because the failed state drawn there is the only place
    /// the design says a key problem is reported; screen 01 has no error
    /// affordance in the export.
    func submitKey() {
        let key = APIKey(keyDraft)
        completedSteps = 0
        stage = .keyTest

        switch APIKeyFormat.check(key, for: provider) {
        case .rejected(let problem):
            phase = .failed(.format(problem))
        case .plausible:
            phase = .running
            validation = Task { [weak self] in
                await self?.runValidation(of: key)
            }
        }
    }

    // MARK: - Screens 02 and 03

    private func runValidation(of key: APIKey) async {
        let outcome = await validator.validate(key, for: provider)
        guard !Task.isCancelled else { return }

        switch outcome {
        case .passed:
            await recordPass(of: key)
        case .invalidKey:
            // The provider answered, so the connection opened, the request
            // went out and a response came back. Only the last row fails.
            fail(.invalidKey, after: .responseReceived)
        case .noCredit:
            fail(.noCredit, after: .responseReceived)
        case .retry:
            // Nothing was reached, so not even the first row is done.
            fail(.network, after: nil)
        }
    }

    private func recordPass(of key: APIKey) async {
        do {
            try keychain.store(key, for: provider)
        } catch {
            // The error is discarded rather than shown: it carries a Security
            // framework status code, which is infrastructure detail the user
            // cannot act on, and it is the one error in this flow that sits
            // next to a key in a stack trace.
            fail(.storageFailed, after: nil)
            return
        }

        // The key is safe in the Keychain; the copy in memory has no further
        // use, and the field it came from is about to leave the screen.
        keyDraft = ""

        for step in Step.allCases {
            completedSteps = index(of: step) + 1
            guard step != Step.allCases.last else { break }
            try? await Task.sleep(for: stepInterval)
            guard !Task.isCancelled else { return }
        }
        phase = .passed
    }

    /// Stops the sequence, leaving every step up to and including `lastDone`
    /// ticked off and the rest pending.
    private func fail(_ failure: Failure, after lastDone: Step?) {
        completedSteps = lastDone.map { index(of: $0) + 1 } ?? 0
        phase = .failed(failure)
    }

    /// How a step's marker is drawn right now.
    ///
    /// A step is only ever `active` while the phase is `running`, which is what
    /// makes the spinner stop on failure without a second flag to forget.
    func state(of step: Step) -> StepState {
        let position = index(of: step)
        if position < completedSteps { return .done }
        if position == completedSteps, phase == .running { return .active }
        return .pending
    }

    private func index(of step: Step) -> Int {
        Step.allCases.firstIndex(of: step) ?? 0
    }

    /// The outlined footer button on screen 02, and the `Change key` button of
    /// the failed state — both go back to the field.
    ///
    /// The draft is kept so a user correcting one character does not retype the
    /// whole key.
    func returnToKeyEntry() {
        validation?.cancel()
        validation = nil
        completedSteps = 0
        phase = .running
        stage = .key
    }

    /// Screen 03's `Continue`.
    func continueFromKeyTest() {
        guard phase == .passed else { return }
        stage = .goal
    }

    // MARK: - Screen 04

    func selectGoalMode() {
        countsAgainstGoal = true
    }

    func selectCountOnly() {
        countsAgainstGoal = false
    }

    /// Writes the answer and ends onboarding.
    ///
    /// Onboarding being over is not a flag: it is the existence of the settings
    /// row, and `setCountingMode` creates it. Count-only writes no goal — the
    /// row keeps the default targets so Settings can switch back later — which
    /// is why the mode is passed as a `CountingMode` rather than as a boolean
    /// beside a set of numbers.
    ///
    /// Returns `false` when the write failed, and the flow simply stays put so
    /// the user can tap again. There is no drawn state for a failed local save,
    /// and inventing one would be a design deviation; advancing anyway would be
    /// worse, since the next launch would ask the same questions again.
    @discardableResult
    func complete() -> Bool {
        let mode: CountingMode = countsAgainstGoal ? .goal(targets) : .countOnly
        do {
            try store.setCountingMode(mode)
        } catch {
            return false
        }
        onFinished()
        return true
    }
}

// MARK: - Redacted text representations

/// The same closure `APIKey` applies to itself, applied to the one type that
/// holds a key outside it.
///
/// `keyDraft` is a plain `String` and so is not redacted by `APIKey`'s own
/// conformances. A class's default `description` would not print it, but `dump`
/// and any reflection-driven crash reporter walk stored properties, and that is
/// enough of a route to close deliberately rather than to rely on.
extension OnboardingModel: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    nonisolated private static let redacted = "OnboardingModel(redacted)"

    nonisolated var description: String { Self.redacted }

    nonisolated var debugDescription: String { Self.redacted }

    nonisolated var customMirror: Mirror {
        Mirror(self, children: [Mirror.Child](), displayStyle: .class)
    }
}
