import Foundation

// MARK: - Client

/// Talks to Anthropic's Messages API, directly from the device.
///
/// One endpoint, `https://api.anthropic.com/v1/messages`, reached with the
/// user's own key. There is no Levo Studio server in this path and there is no
/// version of this file that adds one.
nonisolated struct AnthropicClient: AIClient {

    // MARK: - Configuration

    let provider = AIProvider.claude

    /// The model the design's own label names: "Modell: Claude Sonnet 5".
    static let model = "claude-sonnet-5"

    /// Anthropic pins its request and response shapes to a dated version
    /// rather than to the newest thing they have shipped. Naming it means a
    /// change on their side arrives as a deliberate edit here instead of as a
    /// scan that stopped working one morning.
    private static let apiVersion = "2023-06-01"

    private static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Enough for one meal's JSON with a generous breakdown, and short enough
    /// that a model which starts writing prose instead runs out rather than
    /// billing the user for an essay.
    private static let maxTokens = 1024

    private let transport: any HTTPTransport
    private let keys: ProviderKeySource

    init(
        transport: any HTTPTransport = URLSession.fuel,
        keys: ProviderKeySource = ProviderKeySource(provider: .claude)
    ) {
        self.transport = transport
        self.keys = keys
    }

    // MARK: - Key check

    /// Tests a key with a one-token `messages` request.
    ///
    /// **Why not `/v1/models`, which would be free.** `GET /v1/models`
    /// authenticates the key and answers nothing else: an account with a valid
    /// key and an empty balance passes it. The design's key test is not "is
    /// this string well-formed" — `APIKeyFormat` already answered that offline
    /// and for free — it is the promise that the next thing the user does, a
    /// photo scan, will work. A key that passes a free check and then fails at
    /// the first meal has made the test a lie, and moved the error from a
    /// screen built for it to one that is not.
    ///
    /// So: the cheapest call that can actually fail for the right reason. One
    /// token of prompt, `max_tokens: 1`, no image, no system prompt. That is
    /// a fraction of a cent, once, when a key is entered or re-checked — and
    /// it is the only call in this file that is made without the user having
    /// asked for an estimate.
    ///
    /// Mistral is the other way round precisely because it has a free call
    /// that *does* answer the credit question; see `MistralClient`.
    func checkKey(_ key: APIKey) async -> KeyCheckResult {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "Hi"]]
        ]

        guard let request = Self.request(body: body, key: key) else {
            return .failed(.network)
        }

        do {
            let response = try await transport.send(request)
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

    func estimate(photo: MealPhoto) async throws -> MealEstimate {
        // The image block comes before the text block. Anthropic's own
        // guidance is that images placed ahead of the question perform better,
        // and the ordering is load-bearing enough to be worth a comment: a
        // future edit that appends the image after the prompt would look
        // harmless and would quietly cost accuracy.
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": MealPhoto.mediaType,
                    "data": photo.base64
                ]
            ],
            ["type": "text", "text": EstimateContract.photoInstruction]
        ]

        return try await complete(content: content, mode: .photo)
    }

    func estimate(text: String) async throws -> MealEstimate {
        let content: [[String: Any]] = [
            ["type": "text", "text": EstimateContract.textInstruction(for: text)]
        ]

        return try await complete(content: content, mode: .text)
    }

    // MARK: - The one request path

    private func complete(content: [[String: Any]], mode: AILogMode) async throws -> MealEstimate {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": Self.maxTokens,
            "system": EstimateContract.systemPrompt,
            "messages": [["role": "user", "content": content]]
        ]

        // Read the key here, at the moment the request is built, and let it go
        // out of scope with this function.
        let key = try keys.key()

        guard let request = Self.request(body: body, key: key) else {
            throw AIError.malformedResponse
        }

        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw AIError.transportFailure(error)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw AIError.from(status: response.statusCode, body: response.body, provider: provider)
        }

        do {
            return try EstimateContract.estimate(from: Self.replyText(in: response.body), mode: mode)
        } catch {
            // Asked only once the reply has already failed to parse. A model
            // that finished its object and was cut off writing the newline
            // after it has still answered, and the user has paid for it.
            throw Self.ranOutOfTokens(response.body) ? AIError.truncatedReply : error
        }
    }

    // MARK: - Request

    /// Builds a signed request. The key goes in `x-api-key` and nowhere else —
    /// **never in the URL**, never in a query item, never in the body.
    ///
    /// Returns `nil` only when the body cannot be serialised, which means a
    /// programming error in the dictionaries above rather than anything the
    /// user did.
    private static func request(body: [String: Any], key: APIKey) -> URLRequest? {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }

        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue(key.secret, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = data
        return request
    }

    // MARK: - Response

    /// Whether the model stopped because it hit `max_tokens` rather than
    /// because it had finished.
    ///
    /// A truncated reply is unbalanced JSON, so `EstimateContract` reports it
    /// as prose or a wrong shape — the two things it cannot be. `stop_reason`
    /// is the one field that says which, and it was being thrown away with the
    /// rest of the envelope.
    private static func ranOutOfTokens(_ body: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        return object["stop_reason"] as? String == "max_tokens"
    }

    /// Pulls the assistant's text out of a Messages response.
    ///
    /// Returns an empty string on anything unexpected, which
    /// `EstimateContract` then reports as a malformed response. The alternative
    /// — a second error case for "the envelope was wrong" — would be a
    /// distinction the interface cannot draw and the user cannot act on.
    private static func replyText(in body: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let blocks = object["content"] as? [[String: Any]]
        else {
            return ""
        }

        // Concatenated rather than "first block wins": a reply split across
        // two text blocks is still one JSON object once they are joined, and
        // taking only the first would throw half the answer away.
        return blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
    }
}
