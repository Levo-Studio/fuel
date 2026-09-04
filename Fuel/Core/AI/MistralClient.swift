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


    private let transport: any StreamingHTTPTransport
    private let keys: ProviderKeySource

    init(
        transport: any StreamingHTTPTransport = URLSession.fuel,
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

    // MARK: - Adjusting

    /// The conversation, as a sequence rather than a value. The Anthropic
    /// client's own note explains why the body is serialised before the task
    /// starts and why the key is still read inside it.
    func adjust(
        _ meal: AdjustableMeal,
        history: [MealChatTurn],
        message: String
    ) -> AsyncThrowingStream<MealChatEvent, any Error> {
        // The turns so far, then the meal as it now stands with the new
        // message attached to it. See `MealChatContract.turn(for:message:)`
        // for why the meal rides with the current question rather than with
        // the first one.
        var messages: [[String: Any]] = [
            ["role": "system", "content": MealChatContract.systemPrompt]
        ]
        messages += history
            .suffix(MealChatContract.maximumHistoryExchanges * 2)
            .map { ["role": $0.speaker == .user ? "user" : "assistant", "content": $0.text] }
        messages.append(["role": "user", "content": MealChatContract.turn(for: meal, message: message)])

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": MealChatContract.maxTokens,
            "response_format": ["type": "json_object"],
            "messages": messages,
            "stream": true
        ]
        let serialised = try? JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            let run = Task {
                do {
                    guard let serialised else {
                        throw AIError.malformedResponse
                    }
                    try await converse(body: serialised, over: meal) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in run.cancel() }
        }
    }

    /// One streamed conversation: sign, open, read, assemble. The shape is the
    /// Anthropic client's, and everything that differs between the two is in
    /// `step(in:)` and in how the request is signed.
    private func converse(
        body: Data,
        over meal: AdjustableMeal,
        yield: (MealChatEvent) -> Void
    ) async throws {
        // Read the key here, at the moment the request is built, and let it go
        // out of scope with this function.
        let key = try keys.key()
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        Self.authorise(&request, with: key)

        let response: HTTPStreamResponse
        do {
            response = try await transport.streamRetryingALostConnection(request)
        } catch {
            throw AIError.transportFailure(error)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw AIError.from(
                status: response.statusCode,
                body: await response.refusalBody(),
                provider: provider
            )
        }

        var events = ServerSentEventDecoder()
        var assembler = MealChatStreamAssembler()

        do {
            for try await line in response.lines {
                guard let payload = events.decode(line) else {
                    continue
                }
                let step = Self.step(in: payload)
                if let refusal = step.refusal {
                    throw refusal
                }
                if step.ranOutOfTokens {
                    assembler.noteRanOutOfTokens()
                }
                if let text = step.text {
                    for event in assembler.append(text) {
                        yield(event)
                    }
                }
            }
        } catch let error as AIError {
            throw error
        } catch {
            // A body that died part-way. The turn fails rather than landing on
            // half a sentence — see `MealChatModel.fail(with:as:)`.
            throw AIError.transportFailure(error)
        }

        // The Anthropic client's own note says why a stream that delivered
        // nothing is asked again without streaming, and what the second request
        // costs.
        guard !assembler.receivedNothing else {
            yield(try await unstreamed(body: body, over: meal))
            return
        }

        yield(try assembler.finish(over: meal))
    }

    /// The same question, asked once more as a single document. The Anthropic
    /// client's `unstreamed(body:over:)` carries the reasoning for both.
    private func unstreamed(body: Data, over meal: AdjustableMeal) async throws -> MealChatEvent {
        guard var object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw AIError.malformedResponse
        }
        object.removeValue(forKey: "stream")

        let reply = try await send(body: object)
        return try MealChatStreamAssembler.turn(
            from: reply.text,
            over: meal,
            ranOutOfTokens: Self.ranOutOfTokens(reply.body)
        )
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

        let reply = try await send(body: body)

        do {
            return try EstimateContract.estimate(from: reply.text, mode: mode)
        } catch {
            // Same reasoning as the Anthropic client: asked only once the reply
            // has already failed to parse.
            throw Self.ranOutOfTokens(reply.body) ? AIError.truncatedReply : error
        }
    }

    /// The assistant's text, and the envelope it came in.
    ///
    /// **One place a request is signed and sent**, shared by the estimate path
    /// and the adjustment path for the reason the Anthropic client's own
    /// `send` is: the key handling, the transport failure and the status
    /// mapping belong to talking to Mistral and not to what was asked.
    private func send(body: [String: Any]) async throws -> (text: String, body: Data) {
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

        return (Self.replyText(in: response.body), response.body)
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

        return text(in: message["content"])
    }

    /// A `content` field, which Mistral serves either as a string or as an
    /// array of parts. Joining the text parts is the same answer, written
    /// differently.
    private static func text(in content: Any?) -> String {
        if let text = content as? String {
            return text
        }
        if let parts = content as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    // MARK: - Streamed response

    /// What one server-sent event from a chat-completions stream says.
    ///
    /// Mistral streams the OpenAI shape: the same envelope as a collected
    /// answer, with `delta` where `message` would be, and a literal `[DONE]`
    /// closing the stream. `[DONE]` is not JSON and carries nothing, which is
    /// why it is refused before the parse rather than by it.
    ///
    /// **A payload with an `error` in it and no choices** is how a refusal
    /// raised after the head arrives, and it goes through the same mapping a
    /// refused status does — so nothing the provider wrote travels further than
    /// that function.
    private static func step(
        in payload: String
    ) -> (text: String?, ranOutOfTokens: Bool, refusal: AIError?) {
        guard payload != "[DONE]" else {
            return (nil, false, nil)
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        else {
            return (nil, false, nil)
        }

        guard let choice = (object["choices"] as? [[String: Any]])?.first else {
            guard object.keys.contains("error") else {
                return (nil, false, nil)
            }
            return (nil, false, AIError.from(status: 200, body: Data(payload.utf8), provider: .mistral))
        }

        let delta = choice["delta"] as? [String: Any]
        return (
            text(in: delta?["content"]),
            choice["finish_reason"] as? String == "length",
            nil
        )
    }
}
