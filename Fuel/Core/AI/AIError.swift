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

    /// The provider said in words that the balance is gone — `insufficient_quota`,
    /// or Anthropic's `credit balance is too low`. The key is fine; the account
    /// behind it cannot pay for the request.
    ///
    /// Matched on the body at any status, never on `429` alone: both providers
    /// document `429` as rate limiting, and a throttled user needs to wait, not
    /// to top up.
    ///
    /// Mistral publishes no distinct out-of-credit signal, so an exhausted
    /// Mistral balance may surface as `network` instead. That is the honest
    /// outcome of what Mistral documents, and it is better than inventing a
    /// signal to make this case reachable on both providers.
    ///
    /// Carries the provider's own billing page so the interface can offer the
    /// link the design asks for. The URL is a constant in this file, never
    /// something parsed out of a provider response — a link taken from a
    /// response body is a link an attacker could choose.
    case noCredit(provider: AIProvider, billingPage: URL)

    /// The request never reached the provider, or the answer never came back:
    /// no route to host, a connection dropped mid-flight, a timeout, a
    /// response that is not HTTP at all.
    ///
    /// **Nothing was learned about the key, the account or the meal**, which
    /// is what separates it from `providerRefused` below. The two used to be
    /// one case, and collapsing them meant the interface could not tell a
    /// phone with no signal from a provider having a bad morning — and said
    /// "the answer did not come back" for both, which is only true of one.
    /// Both are still a retry to the user; the difference is that Fuel now
    /// knows which one it is saying.
    case network

    /// The provider answered, and the answer was a refusal Fuel cannot act
    /// on: a `429`, a `500`, Anthropic's `529 overloaded_error`, a `404` for a
    /// model id, a `400` that is not about credit.
    ///
    /// The round trip completed. Whatever went wrong is at the far end, and
    /// waiting is still the right advice — the design draws no fourth state
    /// and inventing one for "the provider is busy" would be a deviation. It
    /// is named separately because the *cause* is worth telling apart even
    /// where the *remedy* is not: an intermittent failure that is all
    /// `providerRefused` is a different investigation from one that is all
    /// `network`.
    ///
    /// It carries no status and no body, for the reason at the top of this
    /// file.
    case providerRefused

    /// The user backed out. Not a failure, and **not** the retry state.
    ///
    /// A cancelled scan is separated from `network` because the two want
    /// opposite things from the interface: a lost connection should offer a
    /// retry, and someone who has just tapped Cancel should be shown nothing
    /// at all. Folding them together meant leaving the log flow and being
    /// offered a second go at a scan you had abandoned.
    ///
    /// It carries nothing, because there is nothing to say. The feature layer
    /// is expected to swallow it.
    case cancelled

    /// The provider answered, but not with the JSON that was asked for —
    /// prose instead of an object, a missing field, a number that is not a
    /// number. Reported rather than repaired: an entry with silently zeroed
    /// macros looks like a real meal in the day's total and is worse than a
    /// visible failure.
    case malformedResponse

    /// The provider's answer stops in the middle, because the model ran into
    /// the token ceiling the request set — Anthropic says so with
    /// `stop_reason: "max_tokens"`, Mistral with `finish_reason: "length"`.
    ///
    /// A special case of `malformedResponse` and named separately because it
    /// is the one unreadable reply Fuel caused itself: the ceiling is Fuel's
    /// number, not the model's mistake, and a scan that fails this way fails
    /// for a reason a `max_tokens` in this repository could fix. Folded in
    /// with prose and wrong field names, it would be invisible — and a
    /// truncation rate is exactly the kind of thing that shows up as "roughly
    /// every second attempt" and nothing more specific.
    ///
    /// Raised only when the reply also fails to parse. A model that finished
    /// its object and was cut off writing the newline after it has still
    /// answered, and the user has already paid for it.
    case truncatedReply

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
            // Anthropic's billing settings, where a user tops up their credit
            // balance. `platform.claude.com` rather than the older
            // `console.anthropic.com`, which only 301s here — Fuel should not
            // spend the user's first tap on a redirect. Force-unwrapped
            // because a literal that fails to parse is a typo, not a runtime
            // condition.
            URL(string: "https://platform.claude.com/settings/billing")!
        case .mistral:
            URL(string: "https://console.mistral.ai/billing/")!
        }
    }

    /// Convenience for the clients, which all raise this the same way.
    static func noCredit(for provider: AIProvider) -> AIError {
        .noCredit(provider: provider, billingPage: billingPage(for: provider))
    }

    /// Classifies whatever the transport threw.
    ///
    /// Only one distinction is worth drawing here, and it is the one between
    /// "this went wrong" and "you stopped it". Both shapes cancellation takes
    /// are checked: `CancellationError`, thrown by structured concurrency, and
    /// `URLError.cancelled`, which is what `URLSession` reports when the task
    /// backing a request is cancelled. Which one arrives depends on where the
    /// cancellation lands, and a client should not have to care.
    ///
    /// Everything else is the retry state. The error is inspected for its
    /// kind and then dropped: no `localizedDescription`, no underlying error,
    /// no host name travels out of this function.
    static func transportFailure(_ error: any Error) -> AIError {
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .cancelled
        }
        return .network
    }
}
