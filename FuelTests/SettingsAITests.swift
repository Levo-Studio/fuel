import Foundation
import Security
import Testing

@testable import Fuel

// MARK: - Doubles

/// Stands in for the provider client.
///
/// **No test in this file touches the network.** The live call belongs to
/// `Core/AI/`; what Settings owns is the decision of what to do with an
/// outcome, and that is decided here. The double also counts its calls, which
/// is how the "the format check runs first" tests can prove a request was never
/// made rather than merely that the note came out right.
///
/// An actor rather than a class with a counter: the protocol is `Sendable`, the
/// model calls it across an `await`, and a mutable counter behind neither would
/// be a data race the compiler is right to reject.
private actor RecordingValidator: KeyValidating {

    private let outcome: KeyValidationOutcome
    private(set) var providersAsked: [AIProvider] = []

    init(_ outcome: KeyValidationOutcome = .passed) {
        self.outcome = outcome
    }

    var callCount: Int { providersAsked.count }

    func validate(_ key: APIKey, for provider: AIProvider) async -> KeyValidationOutcome {
        providersAsked.append(provider)
        return outcome
    }
}

// MARK: - Fixtures

/// Shaped like real keys and belonging to nobody. No real key goes into a
/// repository, least of all a public one.
private enum Fixtures {

    static let claudeKey = "sk-ant-api03-000000000000000000000000"
    static let otherClaudeKey = "sk-ant-api03-111111111111111111111111"
    static let mistralKey = "0000000000000000abcdefabcdefabcd"

    /// Fails the offline check on the prefix alone, so it can never be worth a
    /// request under Claude.
    static let malformedKey = "not-an-anthropic-key-but-long-enough"

    /// A store in a namespace nobody else uses. Swift Testing runs tests in
    /// parallel and the production service holds the user's own key.
    static func makeStore() -> KeychainStore {
        KeychainStore(service: "apps.levo-studio.Fuel.tests.settings.\(UUID().uuidString)")
    }

    /// Clears the whole test service, whatever was written into it.
    static func removeEverything(from store: KeychainStore) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    /// Defaults of its own, so a test never reads or writes the app's.
    static func makeDefaults() -> UserDefaults {
        let suite = "apps.levo-studio.Fuel.tests.settings.\(UUID().uuidString)"
        // Force-unwrapped deliberately: `UserDefaults(suiteName:)` returns nil
        // only for a name that collides with the app's own domain or with
        // `NSGlobalDomain`, and a UUID does neither. A nil here means the
        // fixture is broken, and the test should say so loudly.
        return UserDefaults(suiteName: suite)!
    }

    static func removeEverything(from defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - The format check

@Suite("Settings key handling")
@MainActor
struct SettingsKeyTests {

    /// The offline check runs before the network one, and a key it rejects
    /// never becomes a request.
    @Test("A malformed key never reaches the validator")
    func malformedKeyIsNotValidated() async {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let validator = RecordingValidator()
        let model = APIKeySettingsModel(keychain: store, validator: validator)

        model.draft = Fixtures.malformedKey
        await model.submitDraft(for: .claude)

        #expect(await validator.callCount == 0)
        #expect(model.note == .notAccepted)
        #expect(store.hasKey(for: .claude) == false)
    }

    /// An empty field is the other half of the same rule: the cheapest possible
    /// mistake also costs nothing.
    @Test("An empty key never reaches the validator")
    func emptyKeyIsNotValidated() async {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let validator = RecordingValidator()
        let model = APIKeySettingsModel(keychain: store, validator: validator)

        model.draft = ""
        await model.submitDraft(for: .claude)

        #expect(await validator.callCount == 0)
        #expect(model.note == .notAccepted)
    }

    /// A Mistral key pasted under Claude is caught offline, which is the case
    /// the prefix check exists for.
    @Test("A Mistral key under Claude is rejected offline")
    func wrongProviderKeyIsRejectedOffline() async {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let validator = RecordingValidator()
        let model = APIKeySettingsModel(keychain: store, validator: validator)

        model.draft = Fixtures.mistralKey
        await model.submitDraft(for: .claude)

        #expect(await validator.callCount == 0)
        #expect(model.note == .notAccepted)
    }

    /// The re-check path is not a shortcut past the format check.
    @Test("Re-check format-checks the stored key too")
    func recheckFormatChecksFirst() async throws {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let validator = RecordingValidator()
        let model = APIKeySettingsModel(keychain: store, validator: validator)

        // Planted straight into the Keychain, which is the only way a key that
        // cannot pass the format check gets in there — an older format, or a
        // key stored by a build that checked something else.
        try store.store(APIKey(Fixtures.malformedKey), for: .claude)
        await model.recheck(for: .claude)

        #expect(await validator.callCount == 0)
        #expect(model.note == .notAccepted)
    }

    /// With nothing stored there is nothing to test, so no request is made —
    /// and the note stays empty, because the design draws no state for a
    /// missing key.
    @Test("Re-check with no stored key makes no request")
    func recheckWithoutKeyMakesNoRequest() async {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let validator = RecordingValidator()
        let model = APIKeySettingsModel(keychain: store, validator: validator)

        await model.recheck(for: .claude)

        #expect(await validator.callCount == 0)
        #expect(model.note == .none)
    }
}

// MARK: - Outcomes

@Suite("Settings key test outcomes")
@MainActor
struct SettingsKeyOutcomeTests {

    /// Each outcome drives its own note. Three of the four say something:
    /// `passed` and `notAccepted` are drawn, and `noCredit` is the undrawn
    /// state the owner ruled must be shown anyway, because a user who cannot
    /// pay for a scan and is told nothing is stuck. Only `retry` lands on the
    /// empty note — it concluded nothing, so it claims nothing.
    @Test(
        "An outcome drives its note",
        arguments: [
            (KeyValidationOutcome.passed, KeyTestNote.passed),
            (.invalidKey, .notAccepted),
            (.noCredit, .noCredit),
            (.retry, .none)
        ]
    )
    func outcomeDrivesNote(outcome: KeyValidationOutcome, expected: KeyTestNote) async {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let model = APIKeySettingsModel(keychain: store, validator: RecordingValidator(outcome))

        model.draft = Fixtures.claudeKey
        await model.submitDraft(for: .claude)

        #expect(model.note == expected)
    }

    /// A key the provider accepted is kept, and the field it was typed into is
    /// emptied rather than left holding a secret.
    @Test("A passing key is stored and the draft is cleared")
    func passingKeyIsStored() async {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let model = APIKeySettingsModel(keychain: store, validator: RecordingValidator(.passed))

        model.draft = Fixtures.claudeKey
        await model.submitDraft(for: .claude)

        #expect(store.hasKey(for: .claude))
        #expect(model.draft.isEmpty)
    }

    /// A key with no credit still authenticated, so it is worth keeping.
    @Test("A key with no credit is still stored")
    func noCreditKeyIsStored() async {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let model = APIKeySettingsModel(keychain: store, validator: RecordingValidator(.noCredit))

        model.draft = Fixtures.claudeKey
        await model.submitDraft(for: .claude)

        #expect(store.hasKey(for: .claude))
    }

    /// The one undrawn state that could not stay empty: a user who cannot pay
    /// for a scan gets both a note saying so and the way out of it.
    @Test("No credit produces a note and a billing link", arguments: AIProvider.allCases)
    func noCreditProducesNoteAndLink(provider: AIProvider) async {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let model = APIKeySettingsModel(keychain: store, validator: RecordingValidator(.noCredit))

        model.draft = provider == .claude ? Fixtures.claudeKey : Fixtures.mistralKey
        await model.submitDraft(for: provider)

        #expect(model.note == .noCredit)
        #expect(model.note.titleKey(for: provider) != nil)
        #expect(model.note.showsBillingLink)
        #expect(ProviderBilling.url(for: provider).scheme == "https")
    }

    /// The link is the only one in Settings and it has to reach a real console.
    /// A typo in a URL literal goes red here rather than at a user's tap.
    @Test("Each provider's billing link points at that provider")
    func billingLinksAreDistinctAndPlausible() {
        let anthropic = ProviderBilling.url(for: .claude)
        let mistral = ProviderBilling.url(for: .mistral)

        #expect(anthropic.host() == "console.anthropic.com")
        #expect(mistral.host() == "console.mistral.ai")
        #expect(anthropic != mistral)
    }

    /// The no-credit line names the account being topped up, and Claude's is
    /// Anthropic's — so the two providers cannot share one string.
    @Test("The no-credit note names the provider")
    func noCreditNoteNamesTheProvider() {
        let claude = KeyTestNote.noCredit.titleKey(for: .claude)
        let mistral = KeyTestNote.noCredit.titleKey(for: .mistral)

        #expect(claude != nil)
        #expect(mistral != nil)
        #expect(claude != mistral)
    }

    /// Only the no-credit state draws a second action in that row.
    @Test("No other note offers a link")
    func onlyNoCreditShowsTheLink() {
        #expect(KeyTestNote.noCredit.showsBillingLink)
        #expect(KeyTestNote.none.showsBillingLink == false)
        #expect(KeyTestNote.passed.showsBillingLink == false)
        #expect(KeyTestNote.notAccepted.showsBillingLink == false)
    }

    /// A rejected key does not take a working one away. Typing a bad key over a
    /// good one is a typo, not a decision to stop using Fuel.
    @Test("A rejected key does not overwrite the stored one")
    func rejectedKeyDoesNotOverwrite() async throws {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        try store.store(APIKey(Fixtures.claudeKey), for: .claude)
        let model = APIKeySettingsModel(keychain: store, validator: RecordingValidator(.invalidKey))

        model.draft = Fixtures.otherClaudeKey
        await model.submitDraft(for: .claude)

        let stored = try store.readKey(for: .claude)
        #expect(stored?.secret == Fixtures.claudeKey)
    }

    /// A call that concluded nothing changes nothing.
    @Test("A retry outcome leaves the stored key alone")
    func retryLeavesStoredKeyAlone() async throws {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        try store.store(APIKey(Fixtures.claudeKey), for: .claude)
        let model = APIKeySettingsModel(keychain: store, validator: RecordingValidator(.retry))

        model.draft = Fixtures.otherClaudeKey
        await model.submitDraft(for: .claude)

        let stored = try store.readKey(for: .claude)
        #expect(stored?.secret == Fixtures.claudeKey)
    }
}

// MARK: - Switching provider

@Suite("Settings provider switching")
@MainActor
struct SettingsProviderTests {

    /// The whole point of one Keychain item per provider: a user can hold both
    /// keys and move between them without losing the one they are not using.
    @Test("Switching provider keeps the other provider's key")
    func switchingProviderKeepsBothKeys() async throws {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let model = APIKeySettingsModel(keychain: store, validator: RecordingValidator(.passed))

        model.draft = Fixtures.claudeKey
        await model.submitDraft(for: .claude)

        model.providerChanged()
        model.draft = Fixtures.mistralKey
        await model.submitDraft(for: .mistral)

        model.providerChanged()

        let storedClaude = try store.readKey(for: .claude)
        let storedMistral = try store.readKey(for: .mistral)
        #expect(storedClaude?.secret == Fixtures.claudeKey)
        #expect(storedMistral?.secret == Fixtures.mistralKey)
    }

    /// A result belonging to the provider the user just left would be read as
    /// belonging to the one they arrived at.
    @Test("Switching provider clears the note and the draft")
    func switchingProviderClearsTheRow() async {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let model = APIKeySettingsModel(keychain: store, validator: RecordingValidator(.passed))

        model.draft = Fixtures.claudeKey
        await model.submitDraft(for: .claude)
        #expect(model.note == .passed)

        model.draft = "half a paste"
        model.providerChanged()

        #expect(model.note == .none)
        #expect(model.draft.isEmpty)
    }

    /// The selected provider survives a relaunch, and it is the provider the
    /// key was asked for.
    @Test("The selected provider round-trips")
    func providerRoundTrips() {
        let defaults = Fixtures.makeDefaults()
        defer { Fixtures.removeEverything(from: defaults) }

        let preferences = SettingsPreferences(defaults: defaults)
        #expect(preferences.provider == .claude)

        preferences.provider = .mistral

        #expect(SettingsPreferences(defaults: defaults).provider == .mistral)
    }
}

// MARK: - Leaks

@Suite("Settings key leaks")
@MainActor
struct SettingsKeyLeakTests {

    /// Every way Swift has of turning the model into text has to come back
    /// without the key in it. `@Observable` synthesises stored properties that
    /// reflection walks straight into, so this is not theoretical.
    @Test("The model cannot be interpolated into a string holding the key")
    func modelDoesNotLeakThroughText() {
        let store = Fixtures.makeStore()
        defer { Fixtures.removeEverything(from: store) }
        let model = APIKeySettingsModel(keychain: store, validator: RecordingValidator())
        model.draft = Fixtures.claudeKey

        var dumped = ""
        dump(model, to: &dumped)

        for rendering in ["\(model)", String(describing: model), String(reflecting: model), dumped] {
            #expect(rendering.contains(Fixtures.claudeKey) == false)
        }
    }

    /// The same guarantee on the type the key actually travels in, exercised
    /// through the feature rather than through the wrapper's own suite.
    @Test("A key cannot be interpolated into a string holding the secret")
    func keyDoesNotLeakThroughText() {
        let key = APIKey(Fixtures.claudeKey)

        var dumped = ""
        dump(key, to: &dumped)

        for rendering in ["\(key)", String(describing: key), String(reflecting: key), dumped] {
            #expect(rendering.contains(Fixtures.claudeKey) == false)
        }
    }

    /// The note is a closed set of four, and none of them carries text or a
    /// payload of its own — a note that could hold a provider message would be
    /// one interpolation away from carrying a key back to the screen.
    @Test("A note carries no payload")
    func noteCarriesNoPayload() {
        #expect(KeyTestNote.passed == .passed)
        #expect(KeyTestNote.none.titleKey(for: .claude) == nil)
        #expect(KeyTestNote.passed.titleKey(for: .claude) != nil)
        #expect(KeyTestNote.notAccepted.titleKey(for: .claude) != nil)
        #expect(KeyTestNote.noCredit.titleKey(for: .claude) != nil)
    }
}

// MARK: - Appearance

@Suite("Settings appearance")
@MainActor
struct SettingsAppearanceTests {

    /// Dark and mono are what the app opens on, matching the palette's own
    /// default and the pairing the export treats as the default.
    @Test("The defaults are dark and mono")
    func defaultsAreDarkMono() {
        let defaults = Fixtures.makeDefaults()
        defer { Fixtures.removeEverything(from: defaults) }

        let preferences = SettingsPreferences(defaults: defaults)

        #expect(preferences.theme == .dark)
        #expect(preferences.accent == .mono)
    }

    @Test("A chosen theme round-trips", arguments: FuelTheme.allCases)
    func themeRoundTrips(theme: FuelTheme) {
        let defaults = Fixtures.makeDefaults()
        defer { Fixtures.removeEverything(from: defaults) }

        SettingsPreferences(defaults: defaults).theme = theme

        #expect(SettingsPreferences(defaults: defaults).theme == theme)
    }

    @Test("A chosen accent round-trips", arguments: FuelAccent.allCases)
    func accentRoundTrips(accent: FuelAccent) {
        let defaults = Fixtures.makeDefaults()
        defer { Fixtures.removeEverything(from: defaults) }

        SettingsPreferences(defaults: defaults).accent = accent

        #expect(SettingsPreferences(defaults: defaults).accent == accent)
    }

    /// A value written by some other version of the app, or by nothing at all,
    /// falls back rather than crashing.
    @Test("An unreadable stored appearance falls back")
    func unknownStoredValuesFallBack() {
        let defaults = Fixtures.makeDefaults()
        defer { Fixtures.removeEverything(from: defaults) }
        defaults.set("sepia", forKey: "settings.appearance.theme")
        defaults.set("magenta", forKey: "settings.appearance.accent")

        let preferences = SettingsPreferences(defaults: defaults)

        #expect(preferences.theme == .dark)
        #expect(preferences.accent == .mono)
    }

    /// The swatch row is drawn in this order and no other. A reordered enum
    /// would reorder the row silently.
    @Test("The accents are the five in the drawn order")
    func accentsAreInDrawnOrder() {
        #expect(FuelAccent.allCases == [.mono, .blue, .green, .sand, .lilac])
    }

    /// There is no `System` segment, because the export draws two.
    @Test("The appearance control has exactly two segments")
    func themeHasTwoSegments() {
        #expect(FuelTheme.allCases == [.light, .dark])
    }
}
