import Foundation
import Security
import Testing

@testable import Fuel

// MARK: - Availability

/// Whether this process may talk to the Keychain at all.
///
/// The repository's own build command passes `CODE_SIGNING_ALLOWED=NO`, so that
/// a clone builds and runs without an Apple Developer account. An unsigned
/// process on the simulator carries no keychain access group, and every
/// Security call it makes comes back `errSecMissingEntitlement` before it ever
/// reaches this wrapper's code — nothing about `KeychainStore` is exercised,
/// the calls simply cannot leave the sandbox.
///
/// So the storage suite asks first and is skipped, loudly and with a reason,
/// rather than failing for something that is not a defect. Under a signed run —
/// Xcode's own Cmd-U, a device, or the same `xcodebuild test` without
/// `CODE_SIGNING_ALLOWED=NO` — the probe succeeds and the suite runs in full.
///
/// The probe deliberately does not go through `KeychainStore`: it must be able
/// to see the raw `OSStatus`, and it must not depend on the type it is meant to
/// decide whether to test.
nonisolated enum KeychainAvailability {

    static let isUsable: Bool = {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "apps.levo-studio.Fuel.tests.availability-probe",
            kSecAttrAccount as String: "probe",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        // An empty Keychain answers `errSecItemNotFound`, which is a working
        // Keychain. Only a missing entitlement means the suite cannot run.
        return SecItemCopyMatching(query as CFDictionary, nil) != errSecMissingEntitlement
    }()

    static let skipReason: Comment = "the Keychain needs a signed process; this build has CODE_SIGNING_ALLOWED=NO"
}

// MARK: - Storage

/// These tests hit the real Keychain, so they take two precautions.
///
/// Every test writes under a service name of its own, built from a UUID. That
/// keeps them off the production service — a test that used it would overwrite
/// and then delete the real key of whoever ran the suite — and it keeps them
/// out of each other's way, since Swift Testing runs tests in parallel.
///
/// And every test cleans up what it wrote, so a run leaves no items behind on
/// the simulator or on a developer's machine.
@Suite("Keychain storage", .enabled(if: KeychainAvailability.isUsable, KeychainAvailability.skipReason))
struct KeychainStorageTests {

    // MARK: - Fixtures

    /// Shaped like a real Anthropic key, but it is not one and never was. No
    /// real key belongs in a repository, least of all a public one.
    static let anthropicKey = APIKey("sk-ant-api03-000000000000000000000000")
    static let mistralKey = APIKey("0000000000000000abcdefabcdefabcd")

    /// A store in a namespace nobody else uses.
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "apps.levo-studio.Fuel.tests.\(UUID().uuidString)")
    }

    private func removeEverything(from store: KeychainStore) {
        for provider in AIProvider.allCases {
            try? store.deleteKey(for: provider)
        }
    }

    // MARK: - Round trip

    @Test("a stored key reads back unchanged")
    func roundTrip() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        try store.store(Self.anthropicKey, for: .claude)

        #expect(try store.readKey(for: .claude) == Self.anthropicKey)
        #expect(store.hasKey(for: .claude))
    }

    @Test("storing over an existing key updates it instead of duplicating it")
    func overwriteUpdates() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        try store.store(Self.anthropicKey, for: .claude)
        let corrected = APIKey("sk-ant-api03-111111111111111111111111")
        try store.store(corrected, for: .claude)

        // Reading answers with the new value. If the second write had added a
        // second item rather than updating the first, the Keychain could return
        // either one, and a single delete would leave the other behind — which
        // the check after the delete would catch.
        #expect(try store.readKey(for: .claude) == corrected)

        try store.deleteKey(for: .claude)
        #expect(store.hasKey(for: .claude) == false)
    }

    // MARK: - Deleting

    @Test("deleting removes the item rather than blanking it")
    func deleteRemoves() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        try store.store(Self.anthropicKey, for: .claude)
        try store.deleteKey(for: .claude)

        // Both checks matter: a wrapper that wrote an empty string instead of
        // deleting would still answer `true` to `hasKey` and would hand back an
        // empty key instead of nothing.
        #expect(store.hasKey(for: .claude) == false)
        #expect(try store.readKey(for: .claude) == nil)
    }

    @Test("deleting a key that is not there succeeds")
    func deleteIsIdempotent() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        try store.deleteKey(for: .mistral)
        try store.deleteKey(for: .mistral)
    }

    // MARK: - Missing key

    @Test("a missing key is a normal nil, not a thrown error")
    func missingKeyIsNotAnError() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        #expect(try store.readKey(for: .claude) == nil)
        #expect(store.hasKey(for: .claude) == false)
    }

    // MARK: - Provider independence

    @Test("the two providers keep separate keys")
    func providersAreIndependent() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        try store.store(Self.anthropicKey, for: .claude)
        try store.store(Self.mistralKey, for: .mistral)

        #expect(try store.readKey(for: .claude) == Self.anthropicKey)
        #expect(try store.readKey(for: .mistral) == Self.mistralKey)
    }

    @Test("removing one provider's key leaves the other's alone")
    func removingOneProviderKeepsTheOther() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        try store.store(Self.anthropicKey, for: .claude)
        try store.store(Self.mistralKey, for: .mistral)

        try store.deleteKey(for: .claude)

        // The user switched provider; they must not have to fetch the Mistral
        // key again afterwards.
        #expect(try store.readKey(for: .claude) == nil)
        #expect(try store.readKey(for: .mistral) == Self.mistralKey)
    }

    @Test("overwriting one provider's key does not touch the other's")
    func overwritingOneProviderKeepsTheOther() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        try store.store(Self.anthropicKey, for: .claude)
        try store.store(Self.mistralKey, for: .mistral)

        try store.store(APIKey("sk-ant-api03-222222222222222222222222"), for: .claude)

        #expect(try store.readKey(for: .mistral) == Self.mistralKey)
    }
}

// MARK: - Providers

/// Kept out of the storage suite deliberately: these hold whether or not the
/// process can reach the Keychain, and the closed provider set is the kind of
/// thing that should never be silently skipped.
@Suite("AI providers")
struct AIProviderTests {

    @Test("there are exactly two providers")
    func providerCount() {
        // A third provider is the owner's decision. If this fails, the change
        // that added one was not asked for.
        #expect(AIProvider.allCases.count == 2)
    }

    @Test("provider accounts are distinct")
    func providerAccountsAreDistinct() {
        // One entry per provider only works if the accounts differ; equal
        // accounts would mean the second key silently replaced the first.
        let accounts = Set(AIProvider.allCases.map(\.keychainAccount))
        #expect(accounts.count == AIProvider.allCases.count)
    }
}

// MARK: - Redaction

/// The one guarantee that is easy to break by accident: a key must not be able
/// to reach a string. Every route Swift offers is checked, because a future
/// `Codable` or `CustomStringConvertible` change would silently reopen one.
@Suite("API key redaction")
struct APIKeyRedactionTests {

    private static let secret = "sk-ant-api03-deadbeefdeadbeefdeadbeef"

    @Test("string interpolation does not contain the key")
    func interpolationIsRedacted() {
        let key = APIKey(Self.secret)
        #expect("\(key)".contains(Self.secret) == false)
    }

    @Test("String(describing:) does not contain the key")
    func describingIsRedacted() {
        let key = APIKey(Self.secret)
        #expect(String(describing: key).contains(Self.secret) == false)
    }

    @Test("the debug description does not contain the key")
    func debugDescriptionIsRedacted() {
        let key = APIKey(Self.secret)
        #expect(String(reflecting: key).contains(Self.secret) == false)
    }

    @Test("dump does not contain the key")
    func dumpIsRedacted() {
        let key = APIKey(Self.secret)
        var output = ""
        dump(key, to: &output)
        #expect(output.contains(Self.secret) == false)
    }

    @Test("reflection exposes no children")
    func mirrorHasNoChildren() {
        let key = APIKey(Self.secret)
        #expect(Mirror(reflecting: key).children.isEmpty)
    }

    @Test("the secret is still readable where it is asked for by name")
    func secretIsReachableDeliberately() {
        #expect(APIKey(Self.secret).secret == Self.secret)
    }

    @Test("surrounding whitespace from a paste is trimmed")
    func pastedWhitespaceIsTrimmed() {
        #expect(APIKey("  \(Self.secret)\n").secret == Self.secret)
    }
}

// MARK: - Format check

@Suite("API key format")
struct APIKeyFormatTests {

    // MARK: - Anthropic

    @Test("a well-formed Anthropic key is plausible")
    func anthropicKeyAccepted() {
        let key = APIKey("sk-ant-api03-a1b2c3d4e5f6a7b8c9d0e1f2")
        #expect(APIKeyFormat.check(key, for: .claude) == .plausible)
    }

    @Test("an Anthropic key without the published prefix is rejected")
    func anthropicPrefixRequired() {
        let key = APIKey("api03-a1b2c3d4e5f6a7b8c9d0e1f2a3b4")
        #expect(APIKeyFormat.check(key, for: .claude) == .rejected(.missingAnthropicPrefix))
    }

    @Test("a Mistral key pasted under Claude is caught before a request")
    func mistralKeyUnderClaudeRejected() {
        let key = APIKey("0000000000000000abcdefabcdefabcd")
        #expect(APIKeyFormat.check(key, for: .claude) == .rejected(.missingAnthropicPrefix))
    }

    @Test("an Anthropic key that is only the prefix is too short")
    func truncatedAnthropicKeyRejected() {
        #expect(APIKeyFormat.check(APIKey("sk-ant-"), for: .claude) == .rejected(.tooShort))
    }

    // MARK: - Mistral

    @Test("a Mistral key needs no prefix")
    func mistralNeedsNoPrefix() {
        // The `mist-…` in the design is placeholder text. Mistral publishes no
        // key prefix, so requiring one would reject valid keys. If this test
        // fails, a prefix check was added and it is the check that is wrong.
        let key = APIKey("f7Kq2ZpL9vRxN3aT8cWbY1sJ4dHm6uEg")
        #expect(APIKeyFormat.check(key, for: .mistral) == .plausible)
    }

    @Test("a Mistral key that happens to start with mist- is fine too")
    func mistralPrefixIsNotSpecial() {
        let key = APIKey("mist-f7Kq2ZpL9vRxN3aT8cWbY1sJ4dHm")
        #expect(APIKeyFormat.check(key, for: .mistral) == .plausible)
    }

    @Test("a Mistral key that is too short to be a credential is rejected")
    func shortMistralKeyRejected() {
        #expect(APIKeyFormat.check(APIKey("abc123"), for: .mistral) == .rejected(.tooShort))
    }

    // MARK: - Shared rules

    @Test("an empty key is rejected for every provider", arguments: AIProvider.allCases)
    func emptyKeyRejected(provider: AIProvider) {
        #expect(APIKeyFormat.check(APIKey(""), for: provider) == .rejected(.empty))
        #expect(APIKeyFormat.check(APIKey("   \n "), for: provider) == .rejected(.empty))
    }

    @Test("interior whitespace is rejected", arguments: AIProvider.allCases)
    func interiorWhitespaceRejected(provider: AIProvider) {
        let key = APIKey("sk-ant-api03-a1b2c3 d4e5f6a7b8c9d0e1")
        #expect(APIKeyFormat.check(key, for: provider) == .rejected(.containsWhitespace))
    }

    @Test("a pasted page instead of a key is rejected", arguments: AIProvider.allCases)
    func overlongKeyRejected(provider: AIProvider) {
        let key = APIKey("sk-ant-" + String(repeating: "a", count: 600))
        #expect(APIKeyFormat.check(key, for: provider) == .rejected(.tooLong))
    }

    @Test("the verdict carries the reason rather than a bare failure")
    func verdictCarriesReason() {
        // The interface has to say why. A boolean here would be a regression.
        guard case .rejected(let problem) = APIKeyFormat.check(APIKey(""), for: .claude) else {
            Issue.record("an empty key must be rejected")
            return
        }
        #expect(problem == .empty)
    }
}
