import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Fuel

// MARK: - Validator double

/// Stands in for the provider client `Core/AI` will supply.
///
/// **Nothing in this suite touches the network.** That is not a convenience:
/// the behaviour worth testing here is what the flow does with each of the four
/// outcomes, and a live endpoint would decide which of them happens, would need
/// a real key to do it, and would bill someone for the privilege.
///
/// It records the providers it was asked about so a test can assert the
/// negative case — that a key the offline check rejected never got here.
actor StubValidator: KeyValidating {

    let outcome: KeyValidationOutcome

    /// One entry per call. Only the provider is kept; the key is deliberately
    /// not retained, so not even the test double holds a credential.
    private(set) var calls: [AIProvider] = []

    init(outcome: KeyValidationOutcome = .passed) {
        self.outcome = outcome
    }

    func validate(_ key: APIKey, for provider: AIProvider) async -> KeyValidationOutcome {
        calls.append(provider)
        return outcome
    }
}

// MARK: - Suite

@Suite("Onboarding")
@MainActor
struct OnboardingTests {

    // MARK: - Fixtures

    /// Shaped like a real Anthropic key and is not one. No real key belongs in
    /// a repository, least of all a public one.
    static let claudeKey = "sk-ant-api03-000000000000000000000000"
    static let mistralKey = "0000000000000000abcdefabcdefabcd"

    private func makeKeychain() -> KeychainStore {
        KeychainStore(service: "apps.levo-studio.Fuel.tests.\(UUID().uuidString)")
    }

    private func clear(_ keychain: KeychainStore) {
        for provider in AIProvider.allCases {
            try? keychain.deleteKey(for: provider)
        }
    }

    /// Never the app's suite: these tests write a provider preference, and a
    /// run must not change the provider Fuel opens on for whoever is on the
    /// machine.
    private func makePreferences() -> SettingsPreferences {
        let suite = "apps.levo-studio.Fuel.tests.onboarding.\(UUID().uuidString)"
        return SettingsPreferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    /// A model whose step reveal takes no time, so a suite never waits on the
    /// pacing that exists purely for the eye.
    private func makeModel(
        keychain: KeychainStore,
        validator: StubValidator,
        store: FuelStore,
        preferences: SettingsPreferences? = nil,
        onFinished: @escaping () -> Void = {}
    ) -> OnboardingModel {
        OnboardingModel(
            keychain: keychain,
            validator: validator,
            store: store,
            preferences: preferences ?? makePreferences(),
            stepInterval: .zero,
            onFinished: onFinished
        )
    }

    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true)
    }

    // MARK: - The format check comes first

    @Test("a malformed key never reaches the validator")
    func formatCheckRunsBeforeValidation() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let validator = StubValidator()
        let model = makeModel(keychain: keychain, validator: validator, store: try makeStore())

        model.keyDraft = "not-an-anthropic-key-at-all"
        model.submitKey()
        await model.validation?.value

        #expect(await validator.calls.isEmpty)
        #expect(model.phase == .failed(.format(.missingAnthropicPrefix)))
        #expect(model.completedSteps == 0)
        #expect(!keychain.hasKey(for: .claude))
    }

    @Test("an empty field is rejected without a request")
    func emptyKeyIsRejectedOffline() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let validator = StubValidator()
        let model = makeModel(keychain: keychain, validator: validator, store: try makeStore())

        model.submitKey()
        await model.validation?.value

        #expect(await validator.calls.isEmpty)
        #expect(model.phase == .failed(.format(.empty)))
    }

    @Test("a plausible key does reach the validator")
    func plausibleKeyIsValidated() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let validator = StubValidator()
        let model = makeModel(keychain: keychain, validator: validator, store: try makeStore())

        model.keyDraft = Self.claudeKey
        model.submitKey()
        await model.validation?.value

        #expect(await validator.calls == [.claude])
    }

    // MARK: - The four outcomes

    @Test("a passing key is stored and the screen reads as passed")
    func passedOutcome() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(outcome: .passed), store: try makeStore())

        model.keyDraft = Self.claudeKey
        model.submitKey()
        await model.validation?.value

        #expect(model.phase == .passed)
        #expect(model.completedSteps == OnboardingModel.Step.allCases.count)
        #expect(keychain.hasKey(for: .claude))
        // The draft has no further use once the Keychain holds the key.
        #expect(model.keyDraft.isEmpty)
    }

    @Test(
        "a rejected key stops the test and is not stored",
        arguments: [
            (KeyValidationOutcome.invalidKey, OnboardingModel.Failure.invalidKey, 3),
            (KeyValidationOutcome.noCredit, OnboardingModel.Failure.noCredit, 3),
            (KeyValidationOutcome.retry, OnboardingModel.Failure.network, 0)
        ]
    )
    func failingOutcomes(
        outcome: KeyValidationOutcome,
        failure: OnboardingModel.Failure,
        completed: Int
    ) async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(outcome: outcome), store: try makeStore())

        model.keyDraft = Self.claudeKey
        model.submitKey()
        await model.validation?.value

        #expect(model.phase == .failed(failure))
        #expect(model.completedSteps == completed)
        #expect(!keychain.hasKey(for: .claude))
        // Nothing may move on to screen 04 on a failed key.
        model.continueFromKeyTest()
        #expect(model.stage == .keyTest)
    }

    // MARK: - The step sequence

    @Test("the first step is the active one while the test runs")
    func firstStepIsActiveWhileRunning() throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(), store: try makeStore())

        model.keyDraft = Self.claudeKey
        model.submitKey()

        #expect(model.state(of: .openingConnection) == .active)
        #expect(model.state(of: .sendingTestRequest) == .pending)
        #expect(model.state(of: .modelReady) == .pending)

        model.returnToKeyEntry()
    }

    @Test("a passed test ticks off every step")
    func passedTestCompletesEveryStep() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(outcome: .passed), store: try makeStore())

        model.keyDraft = Self.claudeKey
        model.submitKey()
        await model.validation?.value

        #expect(OnboardingModel.Step.allCases.allSatisfy { model.state(of: $0) == .done })
    }

    @Test("a rejected key stops at the last step and nothing keeps spinning")
    func failedTestStopsAtTheLastStep() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(outcome: .invalidKey), store: try makeStore())

        model.keyDraft = Self.claudeKey
        model.submitKey()
        await model.validation?.value

        #expect(model.state(of: .openingConnection) == .done)
        #expect(model.state(of: .sendingTestRequest) == .done)
        #expect(model.state(of: .responseReceived) == .done)
        #expect(model.state(of: .modelReady) == .pending)
        // A spinner left running under a failure would read as still working.
        #expect(!OnboardingModel.Step.allCases.contains { model.state(of: $0) == .active })
    }

    @Test("a dropped connection ticks off nothing")
    func networkFailureCompletesNoStep() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(outcome: .retry), store: try makeStore())

        model.keyDraft = Self.claudeKey
        model.submitKey()
        await model.validation?.value

        #expect(OnboardingModel.Step.allCases.allSatisfy { model.state(of: $0) == .pending })
    }

    @Test("changing the key returns to the field with the steps reset")
    func changingTheKeyResetsTheSequence() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(outcome: .invalidKey), store: try makeStore())

        model.keyDraft = Self.claudeKey
        model.submitKey()
        await model.validation?.value
        model.returnToKeyEntry()

        #expect(model.stage == .key)
        #expect(model.completedSteps == 0)
        #expect(model.phase == .running)
        // The draft survives, so correcting one character does not mean
        // retyping the whole key.
        #expect(model.keyDraft == Self.claudeKey)
    }

    // MARK: - Two providers, two keys

    @Test("storing one provider's key leaves the other's alone")
    func switchingProviderKeepsBothKeys() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(outcome: .passed), store: try makeStore())

        model.keyDraft = Self.claudeKey
        model.submitKey()
        await model.validation?.value
        model.continueFromKeyTest()

        model.returnToKeyEntry()
        model.selectProvider(.mistral)
        model.keyDraft = Self.mistralKey
        model.submitKey()
        await model.validation?.value

        #expect(try keychain.readKey(for: .claude)?.secret == Self.claudeKey)
        #expect(try keychain.readKey(for: .mistral)?.secret == Self.mistralKey)
    }

    @Test("switching provider drops the half-typed draft")
    func switchingProviderClearsTheDraft() throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(), store: try makeStore())

        model.keyDraft = Self.claudeKey
        model.selectProvider(.mistral)

        #expect(model.keyDraft.isEmpty)
    }

    /// The segment is the stored preference rather than a copy of it, so there
    /// is nothing left behind that could go stale — not for a user who changes
    /// their mind twice, and not for one who goes back to the field afterwards.
    @Test("the segment on screen 01 is the stored provider preference")
    func selectingProviderWritesThePreference() throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let preferences = makePreferences()
        let model = makeModel(
            keychain: keychain,
            validator: StubValidator(),
            store: try makeStore(),
            preferences: preferences
        )

        #expect(model.provider == .claude)
        #expect(preferences.provider == .claude)

        model.selectProvider(.mistral)
        #expect(preferences.provider == .mistral)

        model.selectProvider(.claude)
        model.selectProvider(.mistral)
        model.returnToKeyEntry()

        #expect(model.provider == .mistral)
        #expect(preferences.provider == .mistral)
    }

    // MARK: - Screen 04

    @Test("finishing with a goal writes the goal settings")
    func completingWritesGoalSettings() throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let store = try makeStore()
        var finished = false
        let model = makeModel(
            keychain: keychain,
            validator: StubValidator(),
            store: store,
            onFinished: { finished = true }
        )

        // No row exists until the answer is given — that is what marks
        // onboarding as done.
        #expect(try store.existingGoalSettings() == nil)

        model.selectGoalMode()
        model.targets.kilocalories = 2100
        #expect(model.complete())

        let settings = try #require(try store.existingGoalSettings())
        #expect(settings.countsAgainstGoal)
        #expect(settings.kilocalorieGoal == 2100)
        #expect(settings.proteinGoal == DailyTargets.default.protein)
        #expect(finished)
    }

    @Test("count-only finishes without asking for a goal")
    func countOnlyNeedsNoGoal() throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let store = try makeStore()
        let model = makeModel(keychain: keychain, validator: StubValidator(), store: store)

        model.selectCountOnly()
        #expect(model.complete())

        #expect(try store.countingMode() == .countOnly)
        let settings = try #require(try store.existingGoalSettings())
        #expect(!settings.countsAgainstGoal)
        // The defaults stay on the row so Settings can switch back to a goal
        // without asking the user for numbers they never gave.
        #expect(settings.targets == .default)
    }

    @Test("the goal card starts selected, as it is drawn")
    func goalModeIsTheDrawnDefault() throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(), store: try makeStore())

        #expect(model.countsAgainstGoal)
        #expect(model.targets == .default)
    }

    // MARK: - The calorie field

    /// The counter-check for the lost edit: a goal typed and then confirmed
    /// with the footer button used to be saved as the value it replaced,
    /// because `TextField(value:format:)` writes back on end-editing and a
    /// number pad has no return key. The field commits on every keystroke now,
    /// and this is the rule it commits by.
    @Test("what is typed into the calorie field is the goal that is saved")
    func typedGoalIsCommitted() {
        #expect(GoalFieldInput.kilocalories(from: "2100", previous: 2400) == 2100)
    }

    @Test("a cleared field keeps the goal it had rather than becoming zero")
    func clearedGoalFieldKeepsItsValue() {
        #expect(GoalFieldInput.kilocalories(from: "", previous: 2400) == 2400)
    }

    @Test(
        "the field takes digits and nothing else",
        arguments: [
            ("2100", "2100"),
            ("2 100", "2100"),
            ("2,400 kcal", "2400"),
            ("-50", "50"),
            ("", "")
        ]
    )
    func fieldKeepsOnlyDigits(typed: String, expected: String) {
        #expect(GoalFieldInput.digits(in: typed) == expected)
    }

    /// The counter-check for the placeholder that reached the calorie field.
    ///
    /// `TextField(_:text:)` draws its title as the placeholder whenever the
    /// field is empty, and `.labelsHidden()` does not suppress it — so passing
    /// the choice-card title rendered "Set a calorie goal" at 50pt mono in the
    /// cleared state, through both margins.
    ///
    /// **`prompt: nil` does not suppress it either**, which is the part worth
    /// pinning: it looks like it should, and a field written that way measures
    /// exactly as wide as the titled one. Only an empty title leaves nothing to
    /// draw, which is what `GoalScreen` passes; the title stays on the field as
    /// its accessibility label, which is what it was for.
    @Test("only an empty title leaves a text field with nothing to draw")
    func aTitleIsDrawnAsThePlaceholder() {
        let titled = intrinsicWidth(of: TextField("Set a calorie goal", text: .constant("")))
        let prompted = intrinsicWidth(
            of: TextField("Set a calorie goal", text: .constant(""), prompt: nil)
        )
        let untitled = intrinsicWidth(of: TextField("", text: .constant("")))

        #expect(titled > untitled)
        #expect(prompted > untitled)
    }

    private func intrinsicWidth(of view: some View) -> CGFloat {
        let controller = UIHostingController(rootView: view.fixedSize())
        let unbounded = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        return controller.sizeThatFits(in: unbounded).width
    }

    @Test("a typed goal reaches the settings row")
    func typedGoalIsWritten() throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let store = try makeStore()
        let model = makeModel(keychain: keychain, validator: StubValidator(), store: store)

        model.targets.kilocalories = GoalFieldInput.kilocalories(from: "1800", previous: model.targets.kilocalories)
        #expect(model.complete())

        let settings = try #require(try store.existingGoalSettings())
        #expect(settings.kilocalorieGoal == 1800)
    }

    // MARK: - The key cannot leak

    /// The guarantee `APIKey` makes about itself, held against the one type in
    /// this flow that carries a key outside it.
    ///
    /// `keyDraft` is a plain `String`, so nothing about `APIKey` protects it.
    /// The three routes closed here are every route Swift has of turning a
    /// value into text without naming the property: interpolation,
    /// `String(reflecting:)`, and the reflection `dump` walks.
    @Test("no type in the flow spells the key out")
    func nothingInterpolatesTheKey() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let model = makeModel(keychain: keychain, validator: StubValidator(outcome: .invalidKey), store: try makeStore())

        model.keyDraft = Self.claudeKey

        var dumped = ""
        dump(model, to: &dumped)

        #expect(!"\(model)".contains(Self.claudeKey))
        #expect(!String(reflecting: model).contains(Self.claudeKey))
        #expect(!dumped.contains(Self.claudeKey))

        model.submitKey()
        await model.validation?.value

        var dumpedPhase = ""
        dump(model.phase, to: &dumpedPhase)
        #expect(!"\(model.phase)".contains(Self.claudeKey))
        #expect(!dumpedPhase.contains(Self.claudeKey))
        #expect(!"\(APIKey(Self.claudeKey))".contains(Self.claudeKey))
    }
}
