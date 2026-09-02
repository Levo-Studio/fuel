import Foundation

// MARK: - Key check

/// The outcome of the live key test the design draws on screens 02 and 03.
///
/// Two cases, because the interface has two states: the four steps complete
/// and the connection is confirmed, or the note reads "Key was not accepted."
/// A failing check carries the reason as an `AIError` so the interface can
/// tell an invalid key apart from an exhausted balance — one is a key to
/// re-enter, the other is a billing page to open — and from a network failure,
/// which is a retry rather than a verdict on the key at all.
nonisolated enum KeyCheckResult: Sendable, Equatable {

    /// The key is valid and the account behind it can pay for a request.
    case passed

    /// The key was not accepted, or could not be tested.
    case failed(AIError)
}

// MARK: - Client

/// What a provider client does, independent of which provider it is.
///
/// Three operations, and there is no fourth. The clients hold no conversation,
/// no session and no history: every call is one request and one answer, which
/// is what lets the key be read from the Keychain at the moment of the call
/// and released with the request body.
///
/// **There is no Levo Studio endpoint behind any of this.** A request goes
/// from the device to `api.anthropic.com` or `api.mistral.ai` and nowhere
/// else. There is no proxy, no fallback, and no branch that routes a keyless
/// user through a shared account — not behind a flag, not for testing.
nonisolated protocol AIClient: Sendable {

    /// The provider this client talks to.
    var provider: AIProvider { get }

    /// Spends the smallest possible request confirming that `key` works.
    ///
    /// Takes the key as an argument rather than reading it from the Keychain,
    /// because the design tests a key *before* it is stored — screen 01 hands
    /// over what the user just pasted, and only a passing check earns it a
    /// place on the device.
    ///
    /// Never throws: a failure is an outcome the interface draws, not an
    /// exception. Everything that can go wrong maps onto `KeyCheckResult`.
    func checkKey(_ key: APIKey) async -> KeyCheckResult

    /// Estimates a meal from a photo.
    ///
    /// The photo is already compressed by `MealPhotoCompressor` — the size
    /// check happens there, before any request is built, so an oversized photo
    /// costs nothing.
    func estimate(photo: MealPhoto) async throws -> MealEstimate

    /// Estimates a meal from the sentence the user typed.
    func estimate(text: String) async throws -> MealEstimate
}

// MARK: - Key access

/// Reads the provider key at the moment of a call.
///
/// A tiny type with one job, and the job is a rule: **the key is fetched when
/// the request is built and is not held in a property for longer than the call
/// needs it.** A client that cached its key in a stored `APIKey` would keep the
/// user's credential resident for the lifetime of the app, and would go on
/// using a key the user removed in Settings.
nonisolated struct ProviderKeySource: Sendable {

    private let store: KeychainStore
    private let provider: AIProvider

    init(store: KeychainStore = KeychainStore(), provider: AIProvider) {
        self.store = store
        self.provider = provider
    }

    /// The stored key, or `AIError.missingKey` if there is none.
    ///
    /// A Keychain failure is reported as `missingKey` rather than passed
    /// through: `KeychainError` names an `OSStatus`, and an `OSStatus` has no
    /// meaning on a screen. Either way the answer to the caller is the same —
    /// there is no usable key for this provider right now.
    func key() throws -> APIKey {
        guard let key = try? store.readKey(for: provider), !key.secret.isEmpty else {
            throw AIError.missingKey
        }
        return key
    }
}

// MARK: - Status mapping

extension AIError {

    /// Maps an HTTP status and the response body onto the three states the
    /// design draws.
    ///
    /// The mapping is by **what the provider means**, not by status code
    /// alone, and the order below is the rule rather than an accident:
    ///
    /// 1. An explicit credit signal in the body wins **at any status**. That
    ///    is why this check runs before the `401`/`403` one and not after: a
    ///    provider is free to wrap an exhausted balance in whatever status it
    ///    likes — Anthropic answers `400` with `credit balance is too low` —
    ///    and a status-first mapping would read that as a bad key and tell the
    ///    user to re-enter one that is perfectly valid. When a provider has
    ///    said in words what is wrong, the words win.
    /// 2. `401` and `403` are both "key not accepted". Rejected and not
    ///    permitted are the same thing to a user, with the same remedy: enter
    ///    a different key. Mistral maps entitlement problems to `403`, and
    ///    splitting the two would mean a state the design does not draw.
    /// 3. Everything else is a retry — including a bare `429`. Both providers
    ///    document `429` as rate limiting: Anthropic names it
    ///    `rate_limit_error`, Mistral ships a `Retry-After` header. Sending a
    ///    merely throttled user to a billing page is wrong, and waiting is the
    ///    correct advice.
    ///
    /// **Nothing read here leaves this function.** The body is matched against
    /// two fixed substrings and discarded; no fragment of it, and no status
    /// line, is carried into the returned error.
    static func from(status: Int, body: Data, provider: AIProvider) -> AIError {
        if mentionsExhaustedCredit(body) {
            return .noCredit(for: provider)
        }

        if status == 401 || status == 403 {
            return .invalidKey
        }

        // A 400 that is not about credit, a 429, a 500, a gateway timeout.
        // The design draws no fourth state, and inventing one for "the
        // provider is having a bad day" would be a deviation; a plain retry is
        // also the correct advice.
        return .network
    }

    private static func mentionsExhaustedCredit(_ body: Data) -> Bool {
        guard
            body.count < 8 * 1024,
            let text = String(data: body, encoding: .utf8)?.lowercased()
        else {
            return false
        }
        return text.contains("insufficient_quota") || text.contains("credit balance is too low")
    }
}
