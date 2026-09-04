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
    /// **Deliberately the only place the string appears.** The
    /// model-overview page prints no API id for Mistral Large 3 at all — the
    /// `mistral-large-3-25-12` that appears around it is a documentation URL
    /// slug, not something to send as `model` — so the id was taken from the
    /// two places that do publish one: the Large 3 model page's API-names
    /// badge, and the vision page's runnable example, which is an actual
    /// request body. Both say `mistral-large-2512`, and that matches the shape
    /// of every previous Mistral Large (`mistral-large-2411`,
    /// `mistral-large-2407`).
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
    /// **Why this and not a one-token completion.** It is free, and it
    /// authenticates: a key Mistral rejects, and a key Mistral will not permit,
    /// both fail here, and those are the same screen.
    ///
    /// What it cannot tell us is whether the balance is spent. **Mistral
    /// publishes no distinct out-of-credit signal at all** — the OpenAPI spec
    /// declares only `200` and `422` for this path, `429` is documented as
    /// rate limiting with a `Retry-After` header, and entitlement problems map
    /// to `403`. So an exhausted Mistral balance may reach the user as the
    /// retry state rather than as the billing link. That is the honest
    /// outcome, and it is why a paid completion here would buy nothing:
    /// spending the user's money to learn something Fuel cannot reliably learn
    /// anyway is waste, not caution.
    ///
    /// `AnthropicClient` chooses the other way because Anthropic *does* say it
    /// in words — `credit balance is too low` — so there a one-token message
    /// buys an answer this call cannot give.
    func checkKey(_ key: APIKey) async -> KeyCheckResult {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("v1/models"))
        request.httpMethod = "GET"
        Self.authorise(&request, with: key)

        do {
            let response = try await transport.sendRetryingALostConnection(request)
            guard (200..<300).contains(response.statusCode) else {
                return .failed(
                    AIError.from(status: response.statusCode, body: response.body, provider: provider)
                )
            }
            return .passed
        } catch {
            return .failed(AIError.transportFailure(error))
        }
    }

    // MARK: - Estimating

    func estimate(photo: MealPhoto, context: String? = nil) async throws -> MealEstimate {
        // Mistral takes an image as a data URL in an `image_url` part, not as
        // a base64 block with a separate media type. Same bytes, different
        // envelope — which is the whole reason `MealPhoto` hands out the
        // encoding rather than the request shape.
        //
        // The user's note rides inside the text part, so the note sits ahead
        // of the image here and behind it at Anthropic. That is the envelope
        // difference above and not a second rule about precedence: what keeps
        // the photograph primary is `photoContextPreamble` saying so in words,
        // and both providers get those words identically.
        let content: [[String: Any]] = [
            ["type": "text", "text": EstimateContract.photoInstruction(with: context)],
            [
                "type": "image_url",
                "image_url": "data:\(MealPhoto.mediaType);base64,\(photo.base64)"
            ]
        ]

        let estimate = try await complete(userContent: content, mode: .photo)
        return FoodTableGrounding.groundAgainstBundledTable(estimate, mode: .photo, originalText: nil)
    }

    func estimate(text: String) async throws -> MealEstimate {
        let content: [[String: Any]] = [
            ["type": "text", "text": EstimateContract.textInstruction(for: text)]
        ]

        let estimate = try await complete(userContent: content, mode: .text)
        return FoodTableGrounding.groundAgainstBundledTable(estimate, mode: .text, originalText: text)
    }

    // MARK: - The one request path

    private func complete(userContent: [[String: Any]], mode: AILogMode) async throws -> MealEstimate {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": EstimateContract.maxTokens,
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
            response = try await transport.sendRetryingALostConnection(request)
        } catch {
            throw AIError.transportFailure(error)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw AIError.from(status: response.statusCode, body: response.body, provider: provider)
        }

        do {
            return try EstimateContract.estimate(from: Self.replyText(in: response.body), mode: mode)
        } catch {
            // Same reasoning as the Anthropic client: asked only once the reply
            // has already failed to parse.
            throw Self.ranOutOfTokens(response.body) ? AIError.truncatedReply : error
        }
    }

    // MARK: - Request

    /// Puts the key in `Authorization` and nowhere else — **never in the
    /// URL**, never in a query item, never in the body.
    private static func authorise(_ request: inout URLRequest, with key: APIKey) {
        request.setValue("Bearer \(key.secret)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Response

    /// Whether the model stopped because it hit `max_tokens` rather than
    /// because it had finished. Mistral's word for it is `length`, on the
    /// choice rather than on the envelope.
    private static func ranOutOfTokens(_ body: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]]
        else {
            return false
        }
        return choices.first?["finish_reason"] as? String == "length"
    }

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
