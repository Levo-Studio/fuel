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


    private let transport: any StreamingHTTPTransport
    private let keys: ProviderKeySource

    init(
        transport: any StreamingHTTPTransport = URLSession.fuel,
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
        // The image block comes before the text block. Anthropic's own
        // guidance is that images placed ahead of the question perform better,
        // and the ordering is load-bearing enough to be worth a comment: a
        // future edit that appends the image after the prompt would look
        // harmless and would quietly cost accuracy.
        //
        // The user's note rides inside that same text block rather than
        // arriving as a third one, so a scan carries two parts whether or not
        // anything was typed, and the note cannot be mistaken for a turn of
        // its own.
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": MealPhoto.mediaType,
                    "data": photo.base64
                ]
            ],
            ["type": "text", "text": EstimateContract.photoInstruction(with: context)]
        ]

        let estimate = try await complete(content: content, mode: .photo)
        return FoodTableGrounding.groundAgainstBundledTable(estimate, mode: .photo, originalText: nil)
    }

    func estimate(text: String) async throws -> MealEstimate {
        let content: [[String: Any]] = [
            ["type": "text", "text": EstimateContract.textInstruction(for: text)]
        ]

        let estimate = try await complete(content: content, mode: .text)
        return FoodTableGrounding.groundAgainstBundledTable(estimate, mode: .text, originalText: text)
    }

    // MARK: - Adjusting

    /// The conversation, as a sequence rather than a value.
    ///
    /// The body is serialised here, before the task starts, so what crosses
    /// into it is `Data` and a `Sendable` meal rather than a dictionary of
    /// `Any`. **The key is still read inside**, at the moment the request is
    /// built, which is the rule `ProviderKeySource` exists to keep.
    func adjust(
        _ meal: AdjustableMeal,
        history: [MealChatTurn],
        message: String
    ) -> AsyncThrowingStream<MealChatEvent, any Error> {
        // The turns so far, then the meal as it now stands with the new
        // message attached to it. See `MealChatContract.turn(for:message:)`
        // for why the meal rides with the current question rather than with
        // the first one.
        var messages: [[String: Any]] = history
            .suffix(MealChatContract.maximumHistoryExchanges * 2)
            .map { ["role": $0.speaker == .user ? "user" : "assistant", "content": $0.text] }
        messages.append(["role": "user", "content": MealChatContract.turn(for: meal, message: message)])

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": MealChatContract.maxTokens,
            "system": MealChatContract.systemPrompt,
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
            // A message the user called off has to take the connection with
            // it, not just stop being listened to.
            continuation.onTermination = { _ in run.cancel() }
        }
    }

    /// One streamed conversation: sign, open, read, assemble.
    private func converse(
        body: Data,
        over meal: AdjustableMeal,
        yield: (MealChatEvent) -> Void
    ) async throws {
        // Read the key here, at the moment the request is built, and let it go
        // out of scope with this function.
        let key = try keys.key()
        let request = Self.request(body: body, key: key)

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

        // **A turn the user called off stops here, before it can buy
        // anything.** Cancelling the task that iterates an
        // `AsyncThrowingStream` terminates the stream and hands the iterator
        // `nil`: the loop above exits *normally*, with nothing thrown and
        // nothing to catch. A message cancelled before its first token
        // therefore arrives at the guard below indistinguishable from a stream
        // that framed perfectly and delivered no answer — which is the one case
        // that spends a second request, and it is spent on a run
        // `MealChatModel` has already retired, so the user pays for an answer
        // nothing will ever show them. Cancelling is also not only `CANCEL`:
        // sending a second message while the first is still thinking, and
        // dismissing the sheet mid-turn, both cancel the conversation.
        //
        // Same check and same reason as `sendRetryingALostConnection`, one
        // level down: a request the user has already backed out of must not buy
        // a second one.
        try Task.checkCancellation()

        // **A stream that delivered nothing is asked again without streaming.**
        // See `MealChatStreamAssembler.receivedNothing` for why this is a
        // different case from a reply Fuel could not read, and
        // `unstreamed(body:over:)` for what the second request costs.
        guard !assembler.receivedNothing else {
            yield(try await unstreamed(body: body, over: meal))
            return
        }

        yield(try assembler.finish(over: meal))
    }

    /// The same question, asked once more as a single document.
    ///
    /// **The safety net under the streaming path, and the reason the chat no
    /// longer depends on the wire format being read perfectly.** Streaming buys
    /// the sentence its word-by-word arrival and nothing else; the answer
    /// itself is the same object either way, read by the same
    /// `MealChatStreamAssembler.turn(from:over:ranOutOfTokens:)`. Losing the
    /// arrival is a far smaller thing than losing the answer, which is what a
    /// stream Fuel cannot frame costs the user today.
    ///
    /// **It costs a second request, and that is the honest price.** The
    /// alternative is the retry state, where the user taps `Try again` and pays
    /// for a second request anyway — the same reasoning
    /// `sendRetryingALostConnection` gives for its one extra attempt, and it is
    /// bounded the same way: this path does not stream, so it cannot reach
    /// itself. It is only entered when the stream produced no character at all,
    /// which no answered request does — and only when the turn is still wanted,
    /// which is what the cancellation check above the guard is for.
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

    private func complete(content: [[String: Any]], mode: AILogMode) async throws -> MealEstimate {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": EstimateContract.maxTokens,
            "system": EstimateContract.systemPrompt,
            "messages": [["role": "user", "content": content]]
        ]

        let reply = try await send(body: body)

        do {
            return try EstimateContract.estimate(from: reply.text, mode: mode)
        } catch {
            // Asked only once the reply has already failed to parse. A model
            // that finished its object and was cut off writing the newline
            // after it has still answered, and the user has paid for it.
            throw Self.ranOutOfTokens(reply.body) ? AIError.truncatedReply : error
        }
    }

    /// The assistant's text, and the envelope it came in.
    ///
    /// **One place a request is signed and sent**, shared by the estimate path
    /// and the adjustment path rather than written twice: the key handling,
    /// the transport failure and the status mapping are properties of talking
    /// to Anthropic and not of what was asked. A second copy would be a second
    /// place the key could end up somewhere other than `x-api-key`.
    ///
    /// The body travels back with the text because `ranOutOfTokens` reads
    /// `stop_reason` off the envelope, and only the caller knows whether its
    /// own parse failing is the kind of failure that question answers.
    private func send(body: [String: Any]) async throws -> (text: String, body: Data) {
        // Read the key here, at the moment the request is built, and let it go
        // out of scope with this function.
        let key = try keys.key()

        guard let request = Self.request(body: body, key: key) else {
            throw AIError.malformedResponse
        }

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
        return request(body: data, key: key)
    }

    /// The same request from a body that is already serialised, which is what
    /// the streaming path has: it serialises before starting its task so that
    /// nothing but `Data` crosses into it.
    private static func request(body: Data, key: APIKey) -> URLRequest {
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue(key.secret, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
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

    // MARK: - Streamed response

    /// What one server-sent event from a `messages` stream says.
    ///
    /// Anthropic's stream is a sequence of typed events. Three of them carry
    /// anything Fuel reads; the rest — `message_start`, `content_block_start`,
    /// `content_block_stop`, `message_stop`, `ping` — say only where in the
    /// answer the stream is, which the assembler does not need to be told.
    ///
    /// **The refusal goes through the same mapping a refused status does**, so
    /// an exhausted balance announced part-way through a `200` is still
    /// recognised by its own words, and no fragment of what the provider wrote
    /// travels out of that function.
    private static func step(
        in payload: String
    ) -> (text: String?, ranOutOfTokens: Bool, refusal: AIError?) {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        else {
            return (nil, false, nil)
        }

        switch object["type"] as? String {
        case "content_block_delta":
            // `text` and not `partial_json`: Fuel asks for no tools, so a
            // block that is not text is a block it did not ask for.
            return ((object["delta"] as? [String: Any])?["text"] as? String, false, nil)

        case "message_delta":
            let stop = (object["delta"] as? [String: Any])?["stop_reason"] as? String
            return (nil, stop == "max_tokens", nil)

        case "error":
            return (nil, false, AIError.from(status: 200, body: Data(payload.utf8), provider: .claude))

        default:
            return (nil, false, nil)
        }
    }
}
