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
/// **The clients hold no session and no history of their own.** Every call is
/// one request and one answer, which is what lets the key be read from the
/// Keychain at the moment of the call and released with the request body.
/// `adjust(_:history:message:)` is a conversation and is not an exception to
/// that: the turns so far are an argument, handed over by the screen that is
/// holding them, and nothing about them outlives the call.
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

    /// Estimates a meal from a photo, and from what the user typed under the
    /// viewfinder about it.
    ///
    /// The photo is already compressed by `MealPhotoCompressor` — the size
    /// check happens there, before any request is built, so an oversized photo
    /// costs nothing.
    ///
    /// `context` is detail the photograph cannot carry: the oil something was
    /// fried in, what is in a sauce, a portion smaller than it looks. It
    /// travels **beside the image in the same request** — it does not replace
    /// the photo, it is not a second call, and there is still no second
    /// request shape. `EstimateContract.photoInstruction(with:)` is where it
    /// is bounded and framed, and it is bounded there rather than here so that
    /// an overlong note is refused before a body exists to carry it.
    ///
    /// No default value: a protocol requirement cannot carry one. The two
    /// clients declare `context: String? = nil` on their implementations, so a
    /// concrete caller with nothing to add — every request-shape test in the
    /// suite — goes on saying nothing.
    func estimate(photo: MealPhoto, context: String?) async throws -> MealEstimate

    /// Estimates a meal from the sentence the user typed.
    func estimate(text: String) async throws -> MealEstimate

    /// Adjusts the amounts of a meal that is already logged, from something
    /// the user has said about it.
    ///
    /// **A different question from the two above, and a different contract.**
    /// The three of them share this file, the transport, the key source and
    /// the status mapping; what differs is the shape asked for. See
    /// `MealChatContract` for what goes over the wire and `MealAdjuster` for
    /// why nothing numeric in the reply is read.
    ///
    /// `history` is the exchange so far, oldest first, and belongs to the
    /// caller. `message` is the user's own words and is placed last in the
    /// request, labelled, so it is described rather than obeyed.
    ///
    /// The outcome carries the model's sentence and, separately, the meal —
    /// which is `nil` when nothing it asked for could be made. That is an
    /// answer rather than a failure, and it is not thrown.
    func adjust(
        _ meal: AdjustableMeal,
        history: [MealChatTurn],
        message: String
    ) async throws -> MealAdjustmentOutcome
}

// MARK: - One turn of a conversation

/// Something that was said about a meal, in the only two shapes there are.
///
/// **In memory for as long as a screen is open, and written down nowhere.**
/// Nothing persists a turn: not the store, not a file, not a log. The durable
/// result of a conversation is the meal it adjusted, which is already an
/// entry; the words that got it there are the user's own sentences about what
/// they ate, and Fuel keeps no more of those than it has to.
nonisolated struct MealChatTurn: Sendable, Equatable {

    nonisolated enum Speaker: Sendable, Equatable {

        case user
        case model
    }

    var speaker: Speaker
    var text: String

    init(speaker: Speaker, text: String) {
        self.speaker = speaker
        self.text = text
    }
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
    ///
    /// One caveat on "at any status": the match also has a size bound, and a
    /// body of 8 KiB or more is **not searched at all** — it falls through to
    /// the retry state. An error body that large is not an error message any
    /// provider writes; it is an HTML page from something in front of the API,
    /// or a response Fuel has misread. Decoding megabytes of unknown bytes to
    /// a `String` and lowercasing them, on the failure path, to look for two
    /// substrings, is work done at the request of whoever sent it. A real
    /// credit message is a sentence.
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
        //
        // `providerRefused` rather than `network`: the round trip completed,
        // and the interface should not be told the answer never came back when
        // it did. Both still reach the user as the retry state.
        return .providerRefused
    }

    /// How much of a refusal is worth reading at all.
    ///
    /// The reason it is a guard rather than a limitation is on
    /// `from(status:body:provider:)` above. It is named rather than written
    /// inline because a streamed refusal has to be *collected* before it can be
    /// mapped, and collecting more than will ever be searched is work done at
    /// the request of whoever sent it — see `HTTPStreamResponse.refusalBody()`.
    static let readableErrorBody = 8 * 1024

    /// Whether the body says, in words, that the balance is spent.
    private static func mentionsExhaustedCredit(_ body: Data) -> Bool {
        guard
            body.count < readableErrorBody,
            let text = String(data: body, encoding: .utf8)?.lowercased()
        else {
            return false
        }
        return text.contains("insufficient_quota") || text.contains("credit balance is too low")
    }
}
