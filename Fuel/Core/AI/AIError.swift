import Foundation

// MARK: - Error

/// Everything that can go wrong on the way to an estimate, in the shape the
/// interface can act on.
///
/// The design draws exactly three failure states — invalid key, no credit with
/// a link to the provider's billing page, and a plain retry for a network
/// failure — and this type exists so the feature layer can `switch` onto them
/// instead of reading a message. The two remaining cases are failures the
/// design does not draw because they must not reach the model at all: a photo
/// too large to send, and a reply that is not the JSON that was asked for.
///
/// **No case carries a provider message, an HTTP body, a status line, or a
/// stack trace.** A raw provider string is untrusted text of unknown length in
/// an unknown language, and putting it on screen would both break the design
/// and hand a third party a channel into Fuel's interface. The visible words
/// live in the string catalog, which is a later feature's job — this type
/// carries no user-facing text of its own.
nonisolated enum AIError: Error, Equatable {

    /// `401`, or `403`. The key the user gave is not accepted by the provider.
    /// Drawn as "Key was not accepted."
    case invalidKey

    /// `429`, or an `insufficient_quota` / credit-exhausted body. The key is
    /// fine; the account behind it cannot pay for the request.
    ///
    /// Carries the provider's own billing page so the interface can offer the
    /// link the design asks for. The URL is a constant in this file, never
    /// something parsed out of a provider response — a link taken from a
    /// response body is a link an attacker could choose.
    case noCredit(provider: AIProvider, billingPage: URL)

    /// The request never reached the provider, or the response never came
    /// back. The design's plain retry state.
    case network

    /// The provider answered, but not with the JSON that was asked for —
    /// prose instead of an object, a missing field, a number that is not a
    /// number. Reported rather than repaired: an entry with silently zeroed
    /// macros looks like a real meal in the day's total and is worse than a
    /// visible failure.
    case malformedResponse

    /// The photo is still over the provider's request limit after compression.
    /// Raised before any request is built, so the user is not billed for a
    /// call the provider would reject.
    case imageTooLarge

    /// There is no key stored for the provider the call was made against.
    /// A programming error rather than a user-facing state — onboarding
    /// cannot be skipped, and Settings disables the log modes without a key —
    /// but it is a real outcome of reading the Keychain and is named rather
    /// than crashed on.
    case missingKey
}

// MARK: - Billing pages

extension AIError {

    /// The billing page a `noCredit` error links to, per provider.
    ///
    /// Written out here, and `nonisolated` on a type nothing else can reach,
    /// so there is exactly one place a URL that Fuel opens can come from.
    static func billingPage(for provider: AIProvider) -> URL {
        switch provider {
        case .claude:
            // Anthropic's billing settings, where a user tops up their
            // credit balance. Force-unwrapped because a literal that fails
            // to parse is a typo, not a runtime condition.
            URL(string: "https://console.anthropic.com/settings/billing")!
        case .mistral:
            URL(string: "https://console.mistral.ai/billing/")!
        }
    }

    /// Convenience for the clients, which all raise this the same way.
    static func noCredit(for provider: AIProvider) -> AIError {
        .noCredit(provider: provider, billingPage: billingPage(for: provider))
    }
}
