import Foundation
import Security
import Testing

@testable import Fuel

// MARK: - Storage

/// These tests hit the real Keychain. There is no fake and no in-memory double,
/// because the behaviour worth testing here — what the Security framework does
/// with a duplicate, with a missing item, with an accessibility class — is the
/// Security framework's behaviour, and a double would only assert this file's
/// assumptions back at itself.
///
/// **Nothing in this suite is conditional.** An earlier version skipped itself
/// when the Keychain answered `errSecMissingEntitlement`, which is what an
/// unsigned process gets. That is gone: a suite guarding the user's credential
/// that can quietly not run, while the run stays green, is the failure mode it
/// exists to prevent. If these tests cannot reach the Keychain, the run is red
/// and someone looks at why.
///
/// Two precautions, both structural. Every test writes under a service name of
/// its own, built from a UUID — that keeps them off the production service,
/// where a test would overwrite and then delete the real key of whoever ran the
/// suite, and it keeps them out of each other's way, since Swift Testing runs
/// tests in parallel. And every test cleans up what it wrote, so a run leaves
/// nothing behind on the simulator or on a developer's machine.
@Suite("Keychain storage")
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

    /// Clears the whole test service.
    ///
    /// Deletes by service with `kSecAttrSynchronizableAny` rather than looping
    /// over providers through the wrapper, because a test that deliberately
    /// planted a synchronising item has to be able to clean that up too, and
    /// the wrapper — correctly — cannot see one.
    private func removeEverything(from store: KeychainStore) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    // MARK: - Raw inspection

    /// Every item in `service`, as its Keychain attributes.
    ///
    /// This goes around `KeychainStore` on purpose. The two attributes that
    /// carry the security promise — the accessibility class and the sync flag —
    /// are write-only as far as the wrapper's own API is concerned: `readKey`
    /// hands back a key whether it was stored `WhenUnlockedThisDeviceOnly` or
    /// `AfterFirstUnlock`, and whether or not it is synchronising. Asking the
    /// wrapper would therefore assert nothing. The Keychain is asked directly.
    ///
    /// The query matches `kSecAttrSynchronizableAny` rather than pinning the
    /// flag to false, which matters: a query pinned to false cannot see a
    /// synchronising item at all, so a regression that started creating one
    /// would show up here as an empty result rather than as a failure. `Any`
    /// sees both kinds, which is what lets `expectStoredSafely` prove there is
    /// no synced item rather than merely fail to find one.
    private func rawItems(inService service: String) -> [[String: Any]] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return []
        }
        return result as? [[String: Any]] ?? []
    }

    /// Asserts the two attributes the whole file exists for: every item in
    /// `service` is `WhenUnlockedThisDeviceOnly` and is not synchronising.
    ///
    /// Called after both write paths. Without it every other test in this suite
    /// would still pass if someone switched the class to `AfterFirstUnlock` or
    /// dropped the sync flag from the query — the key would round-trip exactly
    /// as before, and would be readable from a locked device or copied into
    /// iCloud.
    private func expectStoredSafely(
        inService service: String,
        expectedItems: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let items = rawItems(inService: service)
        #expect(items.count == expectedItems, sourceLocation: sourceLocation)

        for item in items {
            let accessible = item[kSecAttrAccessible as String] as? String
            #expect(
                accessible == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
                "a key must not be readable from a locked device or restorable onto another one",
                sourceLocation: sourceLocation
            )

            // Absent counts as false: the Keychain omits the attribute for
            // ordinary items and sets it only on synchronising ones.
            let synchronizable = item[kSecAttrSynchronizable as String] as? Bool ?? false
            #expect(
                synchronizable == false,
                "a synced key would travel through Apple's cloud, which Fuel has no version of",
                sourceLocation: sourceLocation
            )
        }
    }

    /// Rewrites every item in `service` with a weaker accessibility class, the
    /// way an older build of Fuel might have left it.
    ///
    /// Goes through the Keychain directly rather than through the wrapper,
    /// because the wrapper has no way of writing a weak item — which is the
    /// point of it.
    private func weakenAccessibility(inService service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        #expect(status == errSecSuccess, "the fixture itself failed to write")
    }

    /// Plants a synchronising item in the slot the store uses for `.claude`.
    ///
    /// The account name is spelled out here rather than read from the wrapper,
    /// which is deliberate on two counts. It is private to `KeychainStore` — a
    /// mapping, not a label — and it is on-device state: pinning the string in
    /// a test means a rename that would orphan every stored key on every user's
    /// device turns up as a red run instead of as a support question.
    ///
    /// `WhenUnlocked` rather than `ThisDeviceOnly` because the Keychain refuses
    /// the combination of a device-only class and synchronisation outright,
    /// which is itself part of why the store's own attributes are safe.
    @discardableResult
    private func plantSynchronisingItem(inService service: String) -> OSStatus {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "claude",
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecValueData as String: Data("sk-ant-api03-999999999999999999999999".utf8)
        ]
        return SecItemAdd(item as CFDictionary, nil)
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

    // MARK: - Security attributes

    @Test("the add path writes this-device-only and never synchronising")
    func addPathWritesSafeAttributes() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        try store.store(Self.anthropicKey, for: .claude)

        expectStoredSafely(inService: store.service, expectedItems: 1)
    }

    @Test("the update path keeps this-device-only and never synchronising")
    func updatePathKeepsSafeAttributes() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        // The second store hits `errSecDuplicateItem` and goes through
        // `SecItemUpdate`, which is a separate attribute payload from the add
        // and therefore a separate place the class can be lost. It is also the
        // path a user takes every time they correct a key, so a regression here
        // would weaken the item of everyone who ever retyped one.
        try store.store(Self.anthropicKey, for: .claude)
        try store.store(APIKey("sk-ant-api03-333333333333333333333333"), for: .claude)

        expectStoredSafely(inService: store.service, expectedItems: 1)
    }

    @Test("a synchronising item in the same slot is invisible to the store")
    func synchronisingItemIsNotVisible() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        let planted = plantSynchronisingItem(inService: store.service)
        try #require(planted == errSecSuccess, "the fixture itself failed to write")

        // The half of the sync guarantee the attribute assertions cannot reach:
        // that the store cannot *touch* an iCloud-backed item, only that it
        // does not create one. A synchronising item sitting in the exact slot
        // the store uses does not exist as far as the store is concerned, so a
        // key that arrived on this device through Apple's cloud can never be
        // the key Fuel sends.
        //
        // This would also go red if someone replaced the pinned false with
        // `kSecAttrSynchronizableAny` while chasing a "why can't it find my
        // key" report, which is the realistic way that filter gets loosened.
        #expect(store.hasKey(for: .claude) == false)
        #expect(try store.readKey(for: .claude) == nil)

        // And a write goes beside it rather than into it: the store adds its
        // own device-only item instead of updating the synced one.
        try store.store(Self.anthropicKey, for: .claude)

        #expect(try store.readKey(for: .claude) == Self.anthropicKey)
        #expect(rawItems(inService: store.service).count == 2)
    }

    @Test("an item left weak by an older build is repaired on the next write")
    func weakItemIsHealedOnWrite() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        try store.store(Self.anthropicKey, for: .claude)
        weakenAccessibility(inService: store.service)

        // Sanity: the fixture really did weaken the item, so the assertion
        // afterwards is about the repair and not about a no-op.
        let weakened = rawItems(inService: store.service).first
        #expect(
            weakened?[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlock as String
        )

        try store.store(APIKey("sk-ant-api03-444444444444444444444444"), for: .claude)

        // `update` claims in a comment that it heals a weak item. This is that
        // claim, checked.
        expectStoredSafely(inService: store.service, expectedItems: 1)
    }

    @Test("storing over an existing key updates it instead of duplicating it")
    func overwriteUpdates() throws {
        let store = makeStore()
        defer { removeEverything(from: store) }

        try store.store(Self.anthropicKey, for: .claude)
        let corrected = APIKey("sk-ant-api03-111111111111111111111111")
        try store.store(corrected, for: .claude)

        #expect(try store.readKey(for: .claude) == corrected)

        // "Updates rather than duplicates" has to be counted, not inferred.
        // `SecItemDelete` removes every matching item, so a leftover duplicate
        // would be deleted along with the first and `hasKey` would still answer
        // false afterwards — the item count is the only thing that tells the
        // two apart.
        #expect(rawItems(inService: store.service).count == 1)
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

/// `AIProvider` is a domain type and needs no Keychain to test. The account
/// names it maps onto are private to `KeychainStore`; their distinctness is
/// covered by the storage tests, which prove that two providers hold two keys.
@Suite("AI providers")
struct AIProviderTests {

    @Test("there are exactly two providers")
    func providerCount() {
        // A third provider is the owner's decision. If this fails, the change
        // that added one was not asked for.
        #expect(AIProvider.allCases.count == 2)
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
