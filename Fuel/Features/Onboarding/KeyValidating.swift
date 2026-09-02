import Foundation

// MARK: - Outcome

/// What the single smallest-possible test call decided about a key.
///
/// Four cases, because those are the four the design draws a state for: the key
/// works, the provider rejected it, the account has nothing left to spend, or
/// the request never got an answer. A provider's own error body is deliberately
/// not carried — no raw provider message reaches the interface, and an
/// associated `String` here would be the first place one arrived.
nonisolated enum KeyValidationOutcome: Equatable, Sendable {

    /// The provider answered and the model is reachable with this key.
    case passed

    /// `401` or `403`. The key is wrong, revoked, belongs to the other
    /// provider, or is not permitted to reach the model. Both statuses land
    /// here because they are the same thing to the user and have the same
    /// remedy: a different key.
    case invalidKey

    /// The account cannot pay for the request.
    ///
    /// Matched on an **explicit credit signal in the response body** — Mistral's
    /// `insufficient_quota`, Anthropic's `credit balance is too low` — at
    /// whatever status it arrives under. Emphatically **not** a bare `429`:
    /// both providers document that as rate limiting, and telling a throttled
    /// user to go top up is wrong.
    ///
    /// Mistral publishes no distinct out-of-credit signal, so an exhausted
    /// Mistral balance may surface as `retry` instead. That is the honest
    /// answer; a conformer must not invent a signal to make this case
    /// reachable on both providers.
    case noCredit

    /// Nothing is known about the key, so this is not a verdict on it.
    ///
    /// A bare `429`, any status the two cases above do not claim, and every
    /// transport failure — offline, timeout, DNS.
    case retry
}

// MARK: - Seam

/// The one thing onboarding needs from `Core/AI`: spend a single request and
/// say which of the four outcomes happened.
///
/// It is declared here, in the feature, rather than in `Core/AI`, because it is
/// the *caller's* requirement — onboarding needs a verdict, not a client — and
/// stating it here is what keeps the flow testable with no network at all. When
/// the real provider client lands it conforms to this; nothing in this folder
/// changes.
///
/// The method takes the key as a parameter instead of the conformer holding
/// one, so no validator can outlive the screen with a credential inside it.
///
/// Non-throwing on purpose. Every failure mode a caller can act on is already
/// one of the four cases, and an escaping `Error` would be exactly the channel
/// a raw provider message used to reach the interface through.
nonisolated protocol KeyValidating: Sendable {

    func validate(_ key: APIKey, for provider: AIProvider) async -> KeyValidationOutcome
}
