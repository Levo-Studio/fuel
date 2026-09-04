import Foundation

// MARK: - Validator

/// Answers onboarding's and Settings' key test with the real provider client.
///
/// It exists because the two sides of this seam are deliberately different
/// shapes, and neither is bent to fit the other. `AIClient.checkKey` answers
/// `passed` or `failed(AIError)`, and `AIError` is the wider type: it also
/// names failures a key check cannot produce. `KeyValidating` answers exactly
/// the four states the design draws. Narrowing one onto the other is wiring,
/// so it happens here, where the app is assembled, rather than inside either
/// feature — `Core/AI` has no business knowing which screens exist, and
/// onboarding has no business knowing that an estimate can come back
/// malformed.
///
/// **No networking is written here.** The clients own the requests, the
/// statuses and the credit-signal matching, `ProviderClients` chooses which
/// client a provider gets, and this type translates its answer.
///
/// The key travels as an argument to `checkKey` rather than being read here,
/// so nothing on this path holds a credential — which is the property
/// `KeyValidating` asks for in writing.
nonisolated struct ProviderKeyValidator: KeyValidating {

    /// Handed to the client rather than used here, and injectable for the same
    /// reason the clients take one: **no test in Fuel touches a live
    /// endpoint**, so the mapping below is exercised against recorded response
    /// shapes.
    ///
    /// A key check streams nothing. The streaming type is what
    /// `ProviderClients` asks for, because the clients it builds also hold
    /// conversations — this path goes on using `send` and one recorded
    /// response.
    private let transport: any StreamingHTTPTransport

    init(transport: any StreamingHTTPTransport = URLSession.fuel) {
        self.transport = transport
    }

    func validate(_ key: APIKey, for provider: AIProvider) async -> KeyValidationOutcome {
        switch await ProviderClients.client(for: provider, transport: transport).checkKey(key) {
        case .passed:
            .passed
        case .failed(let error):
            Self.outcome(for: error)
        }
    }

    /// `AIError` narrowed to the four outcomes the design draws.
    ///
    /// Exhaustive without a `default`, on purpose: a case added to `AIError`
    /// should stop the build here and be classified deliberately, not fall
    /// into the retry state because that is the safe-looking answer.
    ///
    /// The billing page `noCredit` carries does not survive the crossing, and
    /// that is the seam's own decision rather than an oversight — a
    /// `KeyValidationOutcome` carries no provider detail at all, so the
    /// billing link the design draws is Settings' to build from the provider
    /// it already knows.
    private static func outcome(for error: AIError) -> KeyValidationOutcome {
        switch error {
        case .invalidKey:
            .invalidKey
        case .noCredit:
            .noCredit
        // None of these is a verdict on the key. A lost connection, a
        // cancelled check, a reply Fuel could not read and the two cases a key
        // check cannot reach all leave the same thing true: nothing was
        // learned, so the honest answer is to offer another go.
        case .network, .providerRefused, .cancelled, .malformedResponse, .truncatedReply,
             .imageTooLarge, .missingKey:
            .retry
        }
    }
}
