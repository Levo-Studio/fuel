import Foundation

// MARK: - Provider clients

/// Which client talks to which provider — the one place the app decides.
///
/// It sits in the shell rather than in `Core/AI` because it is composition.
/// `AnthropicClient` and `MistralClient` know nothing of each other, and a
/// factory beside them would give `Core/AI` an opinion about how the app is
/// assembled. Both callers are here: the key test onboarding and Settings run
/// through `ProviderKeyValidator`, and the camera half of a log flow, built by
/// `RootShellModel` when the flow is opened. A second copy of the switch would
/// be drift no compiler catches — it keeps working until a provider is added,
/// and then one of the two mappings is silently the older one.
///
/// A client is built per call and thrown away with it. Both are values around
/// a transport, so there is nothing to cache — and nothing built here holds a
/// credential: the key is read at the moment a request is built and released
/// with the request.
nonisolated enum ProviderClients {

    /// The transport is injectable for the reason the clients take one:
    /// **no test in Fuel touches a live endpoint.**
    ///
    /// `StreamingHTTPTransport` because both clients hold a conversation as
    /// well as answering a question, and a conversation is read as it arrives.
    /// The key check and the estimate on either client still go through plain
    /// `send`, unchanged.
    static func client(
        for provider: AIProvider,
        transport: any StreamingHTTPTransport = URLSession.fuel
    ) -> any AIClient {
        switch provider {
        case .claude: AnthropicClient(transport: transport)
        case .mistral: MistralClient(transport: transport)
        }
    }
}
