import Foundation

// MARK: - Client

/// Talks to Mistral's chat-completions API, directly from the device.
///
/// Base `https://api.mistral.ai`, bearer token, no Levo Studio server in the
/// path and no version of this file that adds one.
nonisolated struct MistralClient: AIClient {

    // MARK: - Configuration

    let provider = AIProvider.mistral

    /// The model id sent as `model`, for the design's "Modell: Mistral Large".
    ///
    /// **This constant is the one thing in this file the owner may need to
    /// correct, and it is deliberately the only place the string appears.**
    /// Mistral's own documentation is not self-consistent at the time of
    /// writing: the model-overview page lists Mistral Large 3 as
    /// `mistral-large-3-25-12`, while the vision page's runnable example — the
    /// one that is actually a request body — uses `mistral-large-2512`. The
    /// second is what every previous Mistral Large has looked like
    /// (`mistral-large-2411`, `mistral-large-2407`), so it is what is written
    /// here, but it could not be confirmed against a live `GET /v1/models`
    /// without a key.
    ///
    /// Deliberately **not** `mistral-large-latest`. An alias can move under
    /// the app to a model with different pricing and a different answer shape,
    /// which for a bring-your-own-key product means the user's bill changes
    /// without anything in Fuel changing.
    ///
    /// If a scan fails with a model-not-found error, this line is the fix. A
    /// key that works elsewhere plus a failing scan points here and nowhere
    /// else.
    static let model = "mistral-large-2512"

    private static let baseURL = URL(string: "https://api.mistral.ai")!

    private static let maxTokens = 1024

    private let transport: any HTTPTransport
    private let keys: ProviderKeySource

    init(
        transport: any HTTPTransport = URLSession.fuel,
        keys: ProviderKeySource = ProviderKeySource(provider: .mistral)
    ) {
        self.transport = transport
        self.keys = keys
    }

    // MARK: - Key check

    /// Tests a key with `GET /v1/models`.
    ///
    /// **Why this and not a one-token completion.** Mistral bills nothing for
    /// listing models, and — unlike a bare authentication check — it still
    /// answers the question the design's key test is asking. An account whose
    /// balance is exhausted is answered `429` here, so the free call surfaces
    /// both failures the interface distinguishes: a rejected key and a rejected
    /// bill. When a provider hands you a free call that fails for the right
    /// reasons, spending the user's money to learn the same thing is not
    /// caution, it is waste.
    ///
    /// `AnthropicClient` chooses the other way for the mirror-image reason:
    /// Anthropic's free `/v1/models` passes for a key with no credit left, so
    /// there the cheapest *useful* call is a one-token message.
    func checkKey(_ key: APIKey) async -> KeyCheckResult {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("v1/models"))
        request.httpMethod = "GET"
        Self.authorise(&request, with: key)

        do {
            let response = try await transport.send(request)
            guard (200..<300).contains(response.statusCode) else {
                return .failed(
                    AIError.from(status: response.statusCode, body: response.body, provider: provider)
                )
            }
            return .passed
        } catch {
            return .failed(.network)
        }
    }

    // MARK: - Estimating

    func estimate(photo: MealPhoto) async throws -> MealEstimate {
        // Mistral takes an image as a data URL in an `image_url` part, not as
        // a base64 block with a separate media type. Same bytes, different
        // envelope — which is the whole reason `MealPhoto` hands out the
        // encoding rather than the request shape.
        let content: [[String: Any]] = [
            ["type": "text", "text": EstimateContract.photoInstruction],
            [
                "type": "image_url",
                "image_url": "data:\(MealPhoto.mediaType);base64,\(photo.base64)"
            ]
        ]

        return try await complete(userContent: content, mode: .photo)
    }

    func estimate(text: String) async throws -> MealEstimate {
        let content: [[String: Any]] = [
            ["type": "text", "text": EstimateContract.textInstruction(for: text)]
        ]

        return try await complete(userContent: content, mode: .text)
    }

    // MARK: - The one request path

    private func complete(userContent: [[String: Any]], mode: AILogMode) async throws -> MealEstimate {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": Self.maxTokens,
            // Asked for as well as prompted for. It is not a guarantee — the
            // parser assumes nothing — but it costs nothing and removes the
            // most common way a reply arrives unusable, which is a code fence.
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": EstimateContract.systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]

        // Read the key here, at the moment the request is built, and let it go
        // out of scope with this function.
        let key = try keys.key()

        guard
            let data = try? JSONSerialization.data(withJSONObject: body)
        else {
            throw AIError.malformedResponse
        }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = data
        Self.authorise(&request, with: key)

        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw AIError.network
        }

        guard (200..<300).contains(response.statusCode) else {
            throw AIError.from(status: response.statusCode, body: response.body, provider: provider)
        }

        return try EstimateContract.estimate(from: Self.replyText(in: response.body), mode: mode)
    }

    // MARK: - Request

    /// Puts the key in `Authorization` and nowhere else — **never in the
    /// URL**, never in a query item, never in the body.
    private static func authorise(_ request: inout URLRequest, with key: APIKey) {
        request.setValue("Bearer \(key.secret)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Response

    /// Pulls the assistant's text out of a chat-completions response.
    ///
    /// Empty on anything unexpected, which `EstimateContract` reports as a
    /// malformed response — same reasoning as the Anthropic client.
    private static func replyText(in body: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else {
            return ""
        }

        if let text = message["content"] as? String {
            return text
        }

        // Mistral also serves `content` as an array of parts. Joining the text
        // parts is the same answer, written differently.
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }

        return ""
    }
}
