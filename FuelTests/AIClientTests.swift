import Foundation
import Testing
import UIKit

@testable import Fuel

// MARK: - Transport double

/// A transport that never reaches the network.
///
/// **No test in this file may touch a live endpoint.** A suite that spends the
/// runner's own API credit is not a suite anyone can run, and one that depends
/// on a provider being up is red for reasons that have nothing to do with
/// Fuel. Every test here hands a client a recorded response shape and asserts
/// on what the client did with it.
///
/// It records requests as well as answering them, because half of what is
/// worth asserting is on the way out: which header the key went into, and
/// which ones it did not.
private final class RecordingTransport: HTTPTransport, @unchecked Sendable {

    private let lock = NSLock()
    private var queued: [Result<HTTPResponse, any Error>]
    private var recorded: [URLRequest] = []

    init(_ responses: [Result<HTTPResponse, any Error>]) {
        queued = responses
    }

    /// Answers every request with the same recorded response.
    convenience init(status: Int, body: String) {
        self.init([.success(HTTPResponse(statusCode: status, body: Data(body.utf8)))])
    }

    /// Fails the way a lost connection does.
    static func offline() -> RecordingTransport {
        RecordingTransport([.failure(URLError(.notConnectedToInternet))])
    }

    /// Fails with a specific error, for the cancellation cases.
    static func failing(with error: any Error) -> RecordingTransport {
        RecordingTransport([.failure(error)])
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let outcome: Result<HTTPResponse, any Error> = lock.withLock {
            recorded.append(request)
            // A single queued response answers every call, so a test that only
            // cares about one round trip does not have to count them.
            return queued.count > 1 ? queued.removeFirst() : (queued.first ?? .failure(URLError(.badServerResponse)))
        }
        return try outcome.get()
    }
}

// MARK: - Fixtures

/// A Keychain-backed key source under a service name of its own.
///
/// The real Keychain rather than a double, for the same reason `KeychainTests`
/// uses it: the behaviour under test is that the client reads the key at the
/// moment of the call, and a double would assert this file's assumptions back
/// at itself. The UUID service keeps the suite off the production service —
/// where it would overwrite and then delete the real key of whoever ran it —
/// and out of the way of tests running in parallel.
private struct KeyFixture {

    let store: KeychainStore
    let source: ProviderKeySource

    init(provider: AIProvider, secret: String) throws {
        store = KeychainStore(service: "apps.levo-studio.Fuel.tests.\(UUID().uuidString)")
        source = ProviderKeySource(store: store, provider: provider)
        try store.store(APIKey(secret), for: provider)
    }

    func tearDown(provider: AIProvider) {
        try? store.deleteKey(for: provider)
    }
}

/// A well-formed reply, as either provider's envelope would carry it.
private enum Reply {

    static let goodEstimate = """
        {"title":"Porridge with berries","kilocalories":420,"protein_g":14,\
        "carbs_g":62,"fat_g":11,"items":[\
        {"name":"Porridge","kilocalories":300,"grams":250,"confidence":"confident",\
        "amount":"recognised"},\
        {"name":"Berries","kilocalories":120,"grams":90,"confidence":"unsure",\
        "amount":"estimated"}]}
        """

    /// The same meal with every number quoted — a shape models produce often
    /// enough that rejecting it would cost the user requests over punctuation.
    static let numbersAsStrings = """
        {"title":"Porridge","kilocalories":"420","protein_g":"14",\
        "carbs_g":"62","fat_g":"11","items":[\
        {"name":"Porridge","kilocalories":"300","grams":"250",\
        "confidence":"confident","amount":"recognised"}]}
        """

    static func anthropic(_ text: String) -> String {
        let escaped = String(
            data: try! JSONSerialization.data(withJSONObject: [text], options: .fragmentsAllowed),
            encoding: .utf8
        )!
        // `escaped` is `["…"]`; drop the brackets to get the quoted string.
        let quoted = String(escaped.dropFirst().dropLast())
        return #"{"content":[{"type":"text","text":\#(quoted)}],"stop_reason":"end_turn"}"#
    }

    /// The same envelope with the answer cut off at the request's own token
    /// ceiling, which is how a real `max_tokens` reply comes back: status 200,
    /// well-formed envelope, half a JSON object inside it.
    static func anthropicOutOfTokens(_ text: String) -> String {
        anthropic(text).replacingOccurrences(
            of: #""stop_reason":"end_turn""#,
            with: #""stop_reason":"max_tokens""#
        )
    }

    static func mistral(_ text: String) -> String {
        let escaped = String(
            data: try! JSONSerialization.data(withJSONObject: [text], options: .fragmentsAllowed),
            encoding: .utf8
        )!
        let quoted = String(escaped.dropFirst().dropLast())
        return #"{"choices":[{"message":{"role":"assistant","content":\#(quoted)},"finish_reason":"stop"}]}"#
    }

    /// Mistral's word for the same thing, on the choice rather than on the
    /// envelope.
    static func mistralOutOfTokens(_ text: String) -> String {
        mistral(text).replacingOccurrences(
            of: #""finish_reason":"stop""#,
            with: #""finish_reason":"length""#
        )
    }
}

/// Every `"text"` value anywhere in a request body.
///
/// Both providers wrap the instruction in a content part keyed `text`, at
/// different depths and under different neighbours. Walking for the key rather
/// than for a path means one helper covers both envelopes and neither client's
/// body shape is asserted twice.
private func textParts(in body: Data) -> [String] {
    func walk(_ value: Any) -> [String] {
        switch value {
        case let dictionary as [String: Any]:
            let own = (dictionary["text"] as? String).map { [$0] } ?? []
            return own + dictionary.values.flatMap(walk)
        case let array as [Any]:
            return array.flatMap(walk)
        default:
            return []
        }
    }

    guard let object = try? JSONSerialization.jsonObject(with: body) else {
        return []
    }
    return walk(object)
}

/// A flat image of a given size **in pixels**.
///
/// `scale` is passed explicitly rather than left to the renderer's default,
/// which follows the simulator's screen and would make every size in this file
/// mean something different on a different device.
private func solidImage(width: CGFloat, height: CGFloat, scale: CGFloat = 1) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = scale
    format.opaque = true

    let points = CGSize(width: width / scale, height: height / scale)
    return UIGraphicsImageRenderer(size: points, format: format).image { context in
        UIColor.gray.setFill()
        context.fill(CGRect(origin: .zero, size: points))
    }
}

/// The pixel dimensions of encoded JPEG bytes.
private func pixelSize(of data: Data) -> CGSize? {
    guard let image = UIImage(data: data) else { return nil }
    return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
}

/// A tiny photo. Small enough that compression is never the thing under test
/// when a request is.
private func tinyPhoto() -> MealPhoto {
    try! MealPhotoCompressor.compress(solidImage(width: 8, height: 8))
}

// MARK: - Photo estimates

@Suite("Photo estimates")
struct PhotoEstimateTests {

    @Test("a good Anthropic reply becomes an estimate the store can log")
    func anthropicPhoto() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        let estimate = try await client.estimate(photo: tinyPhoto())

        #expect(estimate.title == "Porridge with berries")
        // 420 is what the reply says; 508 is what the client actually
        // returns, because grounding now sits between the parse and the
        // return. "Porridge" alone matches no CIQUAL row, so item 0 is
        // untouched, but "Berries" at 90 g fully covers CIQUAL's one row
        // containing that word — "Red berries tart" — and prices from it:
        // 231 kcal/100g x 0.9 = 208, replacing the reply's 120 and carrying
        // an 88 kcal delta onto the meal total. A tart is not the same food
        // as the berries in it; this is the known cost of a single generic
        // word matching the one compound dish CIQUAL happens to name with it,
        // not a result this test is claiming is a good match.
        #expect(estimate.kilocalories == 508)
        // Two items, so the meal's macro aggregate is left exactly as the
        // model estimated it — only a meal of exactly one item has an honest
        // "before" to replace; see FoodTableGrounding's own doc comment.
        #expect(estimate.macros == MacroTotals(protein: 14, carbs: 62, fat: 11))
        #expect(estimate.items.count == 2)
        #expect(estimate.items[0].name == "Porridge")
        #expect(estimate.items[0].kilocalories == 300)
        #expect(estimate.items[0].macros == nil)
        #expect(estimate.items[1].kilocalories == 208)
        #expect(estimate.items[1].macros == MacroTotals(protein: 3, carbs: 33, fat: 6))
        // A photo carries a confidence and an approximate weight; the note is
        // the second line of the row on screen 14. Grounding never touches
        // the note, whichever item it resolved.
        #expect(estimate.items[0].note == .photo(confidence: .confident, approximateGrams: 250))
        #expect(estimate.items[1].note == .photo(confidence: .unsure, approximateGrams: 90))
    }

    @Test("the photo travels as a base64 image block ahead of the instruction")
    func anthropicPhotoBody() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)
        _ = try await client.estimate(photo: tinyPhoto())

        let body = try #require(transport.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "image")
        let source = try #require(content[0]["source"] as? [String: Any])
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "image/jpeg")
        #expect((source["data"] as? String)?.isEmpty == false)
        // Image before text: Anthropic's own guidance, and easy to reverse by
        // accident in a later edit.
        #expect(content[1]["type"] as? String == "text")
    }

    /// Beside the image, in the request the scan was already making. The counts
    /// are the assertion: still two content parts, still one round trip.
    @Test("the typed note travels beside the image, in the same one request")
    func contextTravelsWithThePhoto() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)
        _ = try await client.estimate(photo: tinyPhoto(), context: "The sauce has cream")

        #expect(transport.requests.count == 1)

        let body = try #require(transport.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "image")

        let text = try #require(content[1]["text"] as? String)
        #expect(text.contains("Note: The sauce has cream"))
        #expect(text.contains(EstimateContract.photoContextPreamble))
    }

    @Test("Mistral carries the note in the same part as the instruction")
    func mistralCarriesTheContext() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.mistral(Reply.goodEstimate)
        )
        let client = MistralClient(transport: transport, keys: keys.source)
        _ = try await client.estimate(photo: tinyPhoto(), context: "Half of what you see")

        #expect(transport.requests.count == 1)

        let body = try #require(transport.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.last?["content"] as? [[String: Any]])

        #expect(content.count == 2)
        let textParts = content.filter { $0["type"] as? String == "text" }
        #expect(textParts.count == 1)
        let text = try #require(textParts.first?["text"] as? String)
        #expect(text.contains("Note: Half of what you see"))
        #expect(text.contains(EstimateContract.photoContextPreamble))
    }

    @Test("a scan with nothing typed under it mentions no note at all")
    func noContextIsNoMentionOfOne() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)
        _ = try await client.estimate(photo: tinyPhoto())

        let body = try #require(transport.requests.first?.httpBody)
        let parts = textParts(in: body)

        #expect(parts == [EstimateContract.photoInstruction])
    }

    /// The bound runs before the body is built, so the failure this pins is not
    /// "the note was cut short on the wire" but "the note was never on it".
    @Test("an overlong note never reaches the provider")
    func anOverlongContextNeverReachesTheProvider() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        let note = "Zzznotafood " + String(repeating: "a", count: EstimateContract.maximumContextLength)
        _ = try await client.estimate(photo: tinyPhoto(), context: note)

        let body = try #require(transport.requests.first?.httpBody)
        let wire = try #require(String(data: body, encoding: .utf8))

        // Not a fragment of it either: a truncated note would still carry its
        // opening words, and its opening words are what would mislead.
        //
        // Reduced to a `Bool` before the expectation rather than asserted on
        // `wire` directly, so a failure here reports the answer instead of
        // printing a base64 photograph into the test log.
        let carriesTheNote = wire.contains("Zzznotafood")
        #expect(!carriesTheNote)
        #expect(textParts(in: body) == [EstimateContract.photoInstruction])
    }

    @Test("a good Mistral reply becomes an estimate")
    func mistralPhoto() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.mistral(Reply.goodEstimate)
        )
        let client = MistralClient(transport: transport, keys: keys.source)

        let estimate = try await client.estimate(photo: tinyPhoto())

        // See anthropicPhoto for why 420 (the reply) is not 508 (the client's
        // answer, once "Berries" grounds against CIQUAL's "Red berries tart").
        #expect(estimate.kilocalories == 508)
        #expect(estimate.items.count == 2)

        let body = try #require(transport.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.last?["content"] as? [[String: Any]])
        let imagePart = try #require(content.first { $0["type"] as? String == "image_url" })
        let dataURL = try #require(imagePart["image_url"] as? String)
        #expect(dataURL.hasPrefix("data:image/jpeg;base64,"))
    }
}

// MARK: - Text estimates

@Suite("Text estimates")
struct TextEstimateTests {

    @Test("a good reply becomes an estimate with text-shaped notes")
    func anthropicText() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        let estimate = try await client.estimate(text: "porridge with berries")

        #expect(estimate.kilocalories == 420)
        // Typed text gives no confidence and no weight — only whether an
        // amount was written down. The same reply must not produce a photo
        // note here.
        #expect(estimate.items[0].note == .text(amount: .recognised))
        #expect(estimate.items[1].note == .text(amount: .estimated))
    }

    @Test("the typed sentence reaches the request")
    func textReachesBody() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.mistral(Reply.goodEstimate)
        )
        let client = MistralClient(transport: transport, keys: keys.source)
        _ = try await client.estimate(text: "two eggs and toast")

        let body = try #require(transport.requests.first?.httpBody)
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(text.contains("two eggs and toast"))
    }

    /// The convention has to reach both providers identically, because a rule
    /// the user's estimate follows on one provider and not the other is worse
    /// than no rule: the same sentence would come back with two answers three
    /// times apart, with nothing on screen to explain which was which.
    @Test("both providers are taught the raw-weight convention in the same words")
    func conventionReachesBothProviders() async throws {
        let claudeKeys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { claudeKeys.tearDown(provider: .claude) }

        let mistralKeys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { mistralKeys.tearDown(provider: .mistral) }

        let anthropicTransport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let mistralTransport = RecordingTransport(
            status: 200,
            body: Reply.mistral(Reply.goodEstimate)
        )

        _ = try await AnthropicClient(transport: anthropicTransport, keys: claudeKeys.source)
            .estimate(text: "r300g rice")
        _ = try await MistralClient(transport: mistralTransport, keys: mistralKeys.source)
            .estimate(text: "r300g rice")

        // The two envelopes differ, so the text parts are lifted out of each
        // and compared to the instruction the contract built. Comparing raw
        // bodies would compare the envelopes as well.
        let instruction = EstimateContract.textInstruction(for: "r300g rice")
        #expect(instruction.contains(EstimateContract.rawWeightConvention))

        for transport in [anthropicTransport, mistralTransport] {
            let body = try #require(transport.requests.first?.httpBody)
            #expect(textParts(in: body).contains(instruction))
        }
    }

    @Test("a sentence with no raw marker is sent without the convention")
    func plainSentenceCarriesNoConvention() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)
        _ = try await client.estimate(text: "300g rice and chicken")

        let body = try #require(transport.requests.first?.httpBody)
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(!text.contains("weighed raw or dry"))
    }
}

// MARK: - Error states

@Suite("Error states")
struct AIErrorMappingTests {

    @Test("401 is an invalid key")
    func unauthorised() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 401,
            body: #"{"error":{"type":"authentication_error"}}"#
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        await #expect(throws: AIError.invalidKey) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("403 is a key not accepted, the same as 401")
    func forbiddenAnthropic() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        // Rejected and not-permitted are the same thing to a user, with the
        // same remedy.
        let transport = RecordingTransport(
            status: 403,
            body: #"{"error":{"type":"permission_error"}}"#
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        await #expect(throws: AIError.invalidKey) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("Mistral's 403 for an unpermitted key is a key not accepted")
    func forbiddenMistral() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        // Mistral maps entitlement problems to 403. Landing that on the retry
        // state would leave the user tapping a button that can never work.
        let transport = RecordingTransport(status: 403, body: "{}")
        let client = MistralClient(transport: transport, keys: keys.source)

        await #expect(throws: AIError.invalidKey) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("a bare 429 is a retry, not a billing page")
    func rateLimitedAnthropic() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        // Both providers document 429 as rate limiting. Telling a merely
        // throttled user to go top up is wrong; waiting is the right advice.
        let transport = RecordingTransport(
            status: 429,
            body: #"{"error":{"type":"rate_limit_error"}}"#
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        // `providerRefused` rather than `network`: the answer did come back,
        // and it said to wait. The user still sees the retry state.
        await #expect(throws: AIError.providerRefused) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("a bare 429 is a retry at Mistral too")
    func rateLimitedMistral() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        let transport = RecordingTransport(status: 429, body: "{}")
        let client = MistralClient(transport: transport, keys: keys.source)

        await #expect(throws: AIError.providerRefused) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("a credit signal wins over the status it arrives with")
    func creditSignalBeatsStatus() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        // 401 would otherwise be a rejected key. When the provider has said in
        // words what is wrong, the words win — otherwise a user with an empty
        // balance is told to re-enter a key that is perfectly valid.
        let transport = RecordingTransport(
            status: 401,
            body: #"{"error":{"message":"Your credit balance is too low"}}"#
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        await #expect(throws: AIError.noCredit(for: .claude)) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("insufficient_quota is no credit whatever the status")
    func insufficientQuota() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        // Credit is matched on an explicit signal in the body, at any
        // status. There is no status that means "no credit" on its own.
        let transport = RecordingTransport(
            status: 400,
            body: #"{"error":{"code":"insufficient_quota","message":"You exceeded your quota"}}"#
        )
        let client = MistralClient(transport: transport, keys: keys.source)

        let expected = AIError.noCredit(
            provider: .mistral,
            billingPage: URL(string: "https://console.mistral.ai/billing/")!
        )
        await #expect(throws: expected) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("Anthropic's credit-balance message carries the canonical billing host")
    func creditBalanceTooLow() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 400,
            body: #"{"error":{"type":"invalid_request_error","message":"Your credit balance is too low"}}"#
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        let expected = AIError.noCredit(
            provider: .claude,
            billingPage: URL(string: "https://platform.claude.com/settings/billing")!
        )
        await #expect(throws: expected) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("a transport failure is a plain retry")
    func offline() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let client = AnthropicClient(transport: RecordingTransport.offline(), keys: keys.source)

        await #expect(throws: AIError.network) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    /// The strongest candidate for an intermittent failure on a real device:
    /// `URLSession` pools its connections, and a pooled connection the far end
    /// closed while it sat idle still looks usable, so the next request is
    /// written into a socket that is already gone. It comes back as `-1005`
    /// without ever having been delivered.
    @Test("a connection the system had already dropped is tried once more")
    func lostConnectionIsRetriedOnce() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport([
            .failure(URLError(.networkConnectionLost)),
            .success(HTTPResponse(statusCode: 200, body: Data(Reply.anthropic(Reply.goodEstimate).utf8))),
        ])
        let client = AnthropicClient(transport: transport, keys: keys.source)

        let estimate = try await client.estimate(text: "porridge with berries")

        #expect(estimate.kilocalories == 420)
        #expect(transport.requests.count == 2)
    }

    /// The bound on the paragraph above. Everything else is answered once and
    /// reported, because a second attempt would spend the user's credit on a
    /// failure that is not going to change its mind.
    @Test("no other transport failure buys a second request")
    func otherFailuresAreNotRetried() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        let transport = RecordingTransport.offline()
        let client = MistralClient(transport: transport, keys: keys.source)

        await #expect(throws: AIError.network) {
            _ = try await client.estimate(text: "an apple")
        }

        #expect(transport.requests.count == 1)
    }

    @Test("a cancelled scan is cancelled, not a retry")
    func cancelledScan() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        // Someone who has just tapped Cancel should be shown nothing, not
        // offered a second go at a scan they abandoned.
        let client = AnthropicClient(
            transport: RecordingTransport.failing(with: CancellationError()),
            keys: keys.source
        )

        await #expect(throws: AIError.cancelled) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("URLSession's own cancellation is cancelled too")
    func cancelledByURLSession() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        // Which of the two shapes arrives depends on where the cancellation
        // lands, and a client should not have to care.
        let client = MistralClient(
            transport: RecordingTransport.failing(with: URLError(.cancelled)),
            keys: keys.source
        )

        await #expect(throws: AIError.cancelled) {
            _ = try await client.estimate(photo: tinyPhoto())
        }
    }

    @Test("a cancelled key check is cancelled, not a verdict")
    func cancelledKeyCheck() async {
        let client = AnthropicClient(
            transport: RecordingTransport.failing(with: CancellationError()),
            keys: ProviderKeySource(
                store: KeychainStore(service: "unused.\(UUID().uuidString)"),
                provider: .claude
            )
        )

        #expect(await client.checkKey(APIKey("sk-ant-abcdefghijklmnop")) == .failed(.cancelled))
    }

    @Test("an ordinary transport failure is still a retry, not a cancellation")
    func offlineIsNotCancelled() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let client = AnthropicClient(transport: RecordingTransport.offline(), keys: keys.source)

        await #expect(throws: AIError.network) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("a 500 is a plain retry rather than a fourth state")
    func serverError() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        let client = MistralClient(
            transport: RecordingTransport(status: 500, body: "{}"),
            keys: keys.source
        )

        await #expect(throws: AIError.providerRefused) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    /// The distinction the retry state used to hide. Both of these are a
    /// retry to the user and the design draws one screen for them, but Fuel
    /// now knows which it is looking at — and the sentence under that screen
    /// claims the answer never came back, which is only true of one of them.
    @Test("a provider that refused is told apart from an answer that never came")
    func refusalIsNotSilence() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        // Anthropic's own "we are busy" status. The round trip completed.
        let refused = AnthropicClient(
            transport: RecordingTransport(status: 529, body: #"{"error":{"type":"overloaded_error"}}"#),
            keys: keys.source
        )
        await #expect(throws: AIError.providerRefused) {
            _ = try await refused.estimate(text: "an apple")
        }

        // A train tunnel. Nothing came back at all.
        let silent = AnthropicClient(transport: RecordingTransport.offline(), keys: keys.source)
        await #expect(throws: AIError.network) {
            _ = try await silent.estimate(text: "an apple")
        }
    }

    @Test("no stored key is reported rather than crashed on")
    func missingKey() async throws {
        let store = KeychainStore(service: "apps.levo-studio.Fuel.tests.\(UUID().uuidString)")
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: "{}"),
            keys: ProviderKeySource(store: store, provider: .claude)
        )

        await #expect(throws: AIError.missingKey) {
            _ = try await client.estimate(text: "an apple")
        }
    }
}

// MARK: - Parsing

@Suite("Reply parsing")
struct ReplyParsingTests {

    @Test("prose instead of JSON is a typed parse error, not a crash")
    func prose() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let client = AnthropicClient(
            transport: RecordingTransport(
                status: 200,
                body: Reply.anthropic("I'm sorry, I can't tell what this meal is.")
            ),
            keys: keys.source
        )

        await #expect(throws: AIError.malformedResponse) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("truncated JSON is a typed parse error")
    func truncated() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let client = AnthropicClient(
            transport: RecordingTransport(
                status: 200,
                body: Reply.anthropic(#"{"title":"Porridge","kilocalories":420,"#)
            ),
            keys: keys.source
        )

        await #expect(throws: AIError.malformedResponse) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    /// The finding behind this: a reply cut off at `max_tokens` is a 200 with
    /// a well-formed envelope and half an object in it, so brace counting sees
    /// no object and reports prose. The user is then told the answer did not
    /// come back — when it did, and when the reason it is unusable is a number
    /// in this repository rather than anything the model got wrong.
    @Test("a reply cut off at the token ceiling says so, rather than reading as prose")
    func truncationIsNamed() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let client = AnthropicClient(
            transport: RecordingTransport(
                status: 200,
                body: Reply.anthropicOutOfTokens(#"{"title":"Porridge","kilocalories":420,"#)
            ),
            keys: keys.source
        )

        await #expect(throws: AIError.truncatedReply) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("Mistral's own word for the token ceiling is read the same way")
    func mistralTruncationIsNamed() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        let client = MistralClient(
            transport: RecordingTransport(
                status: 200,
                body: Reply.mistralOutOfTokens(#"{"title":"Porridge","kilocalories":420,"#)
            ),
            keys: keys.source
        )

        await #expect(throws: AIError.truncatedReply) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    /// The other half of the rule: a model that finished its object and was
    /// cut off writing the newline after it has still answered, and the user
    /// has already paid for it. The signal never overrides a reply that parses.
    @Test("a complete answer that reports the ceiling is still an estimate")
    func truncationSignalDoesNotDiscardAGoodAnswer() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let client = AnthropicClient(
            transport: RecordingTransport(
                status: 200,
                body: Reply.anthropicOutOfTokens(Reply.goodEstimate)
            ),
            keys: keys.source
        )

        let estimate = try await client.estimate(text: "porridge with berries")

        #expect(estimate.kilocalories == 420)
    }

    @Test("missing macros are reported rather than silently zeroed")
    func missingMacros() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        // An entry with zeroed macros looks like a real meal in the day's
        // ring, which is worse than a visible failure.
        let client = AnthropicClient(
            transport: RecordingTransport(
                status: 200,
                body: Reply.anthropic(#"{"title":"Porridge","kilocalories":420,"items":[]}"#)
            ),
            keys: keys.source
        )

        await #expect(throws: AIError.malformedResponse) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("numbers arriving as strings are read as numbers")
    func quotedNumbers() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let client = AnthropicClient(
            transport: RecordingTransport(
                status: 200,
                body: Reply.anthropic(Reply.numbersAsStrings)
            ),
            keys: keys.source
        )

        let estimate = try await client.estimate(photo: tinyPhoto())

        #expect(estimate.kilocalories == 420)
        #expect(estimate.macros == MacroTotals(protein: 14, carbs: 62, fat: 11))
        #expect(estimate.items[0].kilocalories == 300)
        #expect(estimate.items[0].note == .photo(confidence: .confident, approximateGrams: 250))
    }

    @Test("a number far outside Int's range is a parse error, not a trap")
    func absurdNumber() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        // 1e300 is a perfectly finite Double and converts to no Int at all.
        // This is the one path where a third party fully controls the input,
        // so it has to end in a typed error rather than in a trap.
        let reply = """
            {"title":"Porridge","kilocalories":1e300,"protein_g":14,\
            "carbs_g":62,"fat_g":11,"items":[]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )

        await #expect(throws: AIError.malformedResponse) {
            _ = try await client.estimate(text: "porridge")
        }
    }

    @Test("an absurd number quoted as a string is a parse error, not a trap")
    func absurdQuotedNumber() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        // The string path has the same hole: Double("1e300") is finite too.
        let reply = """
            {"title":"Porridge","kilocalories":"1e300","protein_g":"14",\
            "carbs_g":"62","fat_g":"11","items":[]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )

        await #expect(throws: AIError.malformedResponse) {
            _ = try await client.estimate(text: "porridge")
        }
    }

    @Test("an absurd number in a line item drops the row, not the app")
    func absurdNumberInItem() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let reply = """
            {"title":"Porridge","kilocalories":420,"protein_g":14,"carbs_g":62,\
            "fat_g":11,"items":[{"name":"Porridge","kilocalories":300,\
            "grams":250,"confidence":"confident"},\
            {"name":"Berries","kilocalories":1e300,"grams":-1e300}]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )

        let estimate = try await client.estimate(photo: tinyPhoto())
        #expect(estimate.kilocalories == 420)
        #expect(estimate.items.count == 1)
    }

    @Test("an overlong title is truncated, not thrown away")
    func longTitleTruncated() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let long = String(repeating: "a", count: 500)
        let reply = """
            {"title":"\(long)","kilocalories":420,"protein_g":14,\
            "carbs_g":62,"fat_g":11,"items":[]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )

        let estimate = try await client.estimate(text: "porridge")

        #expect(estimate.title.count == EstimateContract.maximumNameLength)
        // Truncated, not rejected: the user already paid for this estimate,
        // and the calories are the part they asked for.
        #expect(estimate.kilocalories == 420)
    }

    @Test("an overlong item name is truncated and the row survives")
    func longItemNameTruncated() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let long = String(repeating: "b", count: 400)
        let reply = """
            {"title":"Porridge","kilocalories":420,"protein_g":14,"carbs_g":62,\
            "fat_g":11,"items":[{"name":"\(long)","kilocalories":300,\
            "grams":250,"confidence":"confident"}]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )

        let estimate = try await client.estimate(photo: tinyPhoto())

        #expect(estimate.items.count == 1)
        #expect(estimate.items[0].name.count == EstimateContract.maximumNameLength)
    }

    @Test("a name at or under the cap is untouched")
    func shortNameUntouched() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let client = AnthropicClient(
            transport: RecordingTransport(
                status: 200,
                body: Reply.anthropic(Reply.goodEstimate)
            ),
            keys: keys.source
        )

        let estimate = try await client.estimate(text: "porridge")
        #expect(estimate.title == "Porridge with berries")
    }

    @Test("truncation cuts between glyphs, never through one")
    func truncationIsGraphemeSafe() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        // Each of these is one Character and four UTF-8 bytes. Cutting by byte
        // offset would split one and leave a replacement character — a
        // corruption Fuel would have introduced itself.
        let long = String(repeating: "🍜", count: 300)
        let reply = """
            {"title":"\(long)","kilocalories":420,"protein_g":14,\
            "carbs_g":62,"fat_g":11,"items":[]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )

        let estimate = try await client.estimate(text: "ramen")

        #expect(estimate.title.count == EstimateContract.maximumNameLength)
        #expect(!estimate.title.unicodeScalars.contains("\u{FFFD}"))
        #expect(estimate.title.allSatisfy { $0 == "🍜" })
    }

    // MARK: - The advisor line

    /// A helper for the five cases below, which differ only in what the
    /// `advice` key holds — including holding nothing at all.
    private func estimate(advice: String?) async throws -> MealEstimate {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let field = advice.map { #""advice":\#($0),"# } ?? ""
        let reply = """
            {"title":"Porridge","kilocalories":420,"protein_g":14,"carbs_g":62,\
            "fat_g":11,\(field)"items":[]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )
        return try await client.estimate(text: "porridge")
    }

    @Test("an advisor line is read, with its whitespace collapsed")
    func adviceIsRead() async throws {
        // Two paragraphs, which a model writes without being asked, and which
        // would decide the height of a block on the result screen if they
        // survived.
        let estimate = try await estimate(advice: #""Good protein.\n\n  Light on fibre.""#)

        #expect(estimate.advice == "Good protein. Light on fibre.")
    }

    @Test("a missing advisor line is simply absent")
    func adviceMayBeOmitted() async throws {
        let estimate = try await estimate(advice: nil)

        #expect(estimate.advice == nil)
        // And the estimate is exactly as usable as it was before the field
        // existed, which is the whole claim of an optional field.
        #expect(estimate.kilocalories == 420)
    }

    @Test("an advisor line of nothing but whitespace is absent")
    func emptyAdviceIsAbsent() async throws {
        #expect(try await estimate(advice: #""   \n ""#).advice == nil)
    }

    /// **Dropped, not truncated** — the opposite of what an overlong title
    /// gets, because a sentence cut mid-word is not a shorter sentence.
    @Test("an overlong advisor line is dropped and the estimate survives")
    func overlongAdviceIsDropped() async throws {
        let long = String(repeating: "a", count: EstimateContract.maximumAdviceLength + 1)
        let estimate = try await estimate(advice: "\"\(long)\"")

        #expect(estimate.advice == nil)
        #expect(estimate.kilocalories == 420)
    }

    @Test("an advisor line at the cap is kept")
    func adviceAtTheCapIsKept() async throws {
        let long = String(repeating: "a", count: EstimateContract.maximumAdviceLength)
        let estimate = try await estimate(advice: "\"\(long)\"")

        #expect(estimate.advice?.count == EstimateContract.maximumAdviceLength)
    }

    /// A throw inside the decoder would take the whole object with it, and the
    /// user has already paid for the calories in it.
    @Test("an advisor line that is not a string costs nothing but itself")
    func nonStringAdviceIsAbsent() async throws {
        #expect(try await estimate(advice: "42").advice == nil)
        #expect(try await estimate(advice: #"{"text":"Good protein."}"#).advice == nil)
        #expect(try await estimate(advice: "42").kilocalories == 420)
    }

    @Test("a code fence around the object is tolerated")
    func codeFence() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        // The user already paid for this request. Failing it over a fence the
        // model added would charge them for punctuation.
        let fenced = "Here is the estimate:\n```json\n\(Reply.goodEstimate)\n```"
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(fenced)),
            keys: keys.source
        )

        let estimate = try await client.estimate(text: "porridge")
        #expect(estimate.kilocalories == 420)
    }

    @Test("a brace inside a meal name does not end the object early")
    func braceInsideString() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let reply = """
            {"title":"Rice } bowl","kilocalories":500,"protein_g":20,\
            "carbs_g":70,"fat_g":15,"items":[]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )

        let estimate = try await client.estimate(text: "rice bowl")
        #expect(estimate.title == "Rice } bowl")
        #expect(estimate.kilocalories == 500)
    }

    @Test("a photo row without a weight is dropped rather than shown as 0 g")
    func photoRowWithoutGrams() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let reply = """
            {"title":"Porridge","kilocalories":420,"protein_g":14,"carbs_g":62,\
            "fat_g":11,"items":[{"name":"Porridge","kilocalories":300,\
            "grams":250,"confidence":"confident"},\
            {"name":"Berries","kilocalories":120,"confidence":"unsure"}]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )

        let estimate = try await client.estimate(photo: tinyPhoto())

        // "approx. 0 g" would be a number the model never gave, drawn in the
        // same type as the ones it did.
        #expect(estimate.items.count == 1)
        #expect(estimate.items[0].name == "Porridge")
        // Nothing is lost but the row: the day is built from the top-level
        // totals, not from summing these.
        #expect(estimate.kilocalories == 420)
        #expect(estimate.macros == MacroTotals(protein: 14, carbs: 62, fat: 11))
    }

    @Test("a text row needs no weight, because its note carries none")
    func textRowWithoutGrams() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let reply = """
            {"title":"Porridge","kilocalories":420,"protein_g":14,"carbs_g":62,\
            "fat_g":11,"items":[{"name":"Berries","kilocalories":120,\
            "amount":"estimated"}]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )

        let estimate = try await client.estimate(text: "porridge with berries")
        #expect(estimate.items.count == 1)
        #expect(estimate.items[0].note == .text(amount: .estimated))
    }

    @Test("an unreadable row is dropped without taking the estimate with it")
    func unreadableRow() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let reply = """
            {"title":"Porridge","kilocalories":420,"protein_g":14,"carbs_g":62,\
            "fat_g":11,"items":[{"name":"Porridge","kilocalories":420,\
            "grams":250,"confidence":"confident"},{"kilocalories":"about 90"}]}
            """
        let client = AnthropicClient(
            transport: RecordingTransport(status: 200, body: Reply.anthropic(reply)),
            keys: keys.source
        )

        let estimate = try await client.estimate(photo: tinyPhoto())
        #expect(estimate.kilocalories == 420)
        #expect(estimate.items.count == 1)
    }
}

// MARK: - Requests

@Suite("Request shape")
struct RequestShapeTests {

    private static let anthropicSecret = "sk-ant-thiskeymustnotleak"
    private static let mistralSecret = "mistralkeymustnotleak00"

    @Test("Anthropic gets its three headers and the model the design names")
    func anthropicHeaders() async throws {
        let keys = try KeyFixture(provider: .claude, secret: Self.anthropicSecret)
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        _ = try await AnthropicClient(transport: transport, keys: keys.source)
            .estimate(text: "an apple")

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == Self.anthropicSecret)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "claude-sonnet-5")
        #expect(json["max_tokens"] as? Int == EstimateContract.maxTokens)
    }

    @Test("Mistral gets a bearer token and no x-api-key")
    func mistralHeaders() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: Self.mistralSecret)
        defer { keys.tearDown(provider: .mistral) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.mistral(Reply.goodEstimate)
        )
        _ = try await MistralClient(transport: transport, keys: keys.source)
            .estimate(text: "an apple")

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.mistralSecret)")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["max_tokens"] as? Int == EstimateContract.maxTokens)
    }

    /// The regression this whole suite is most worth having.
    ///
    /// A key in a URL is a key in a proxy log, in a crash report's breadcrumb
    /// trail, and in every analytics tool that has ever been handed a request
    /// URL. It is one careless `appendingPathComponent` away at any time, and
    /// nothing else in the codebase would notice.
    @Test("the key never appears in a request URL, in a query, or in a body")
    func keyStaysInItsHeader() async throws {
        let anthropicKeys = try KeyFixture(provider: .claude, secret: Self.anthropicSecret)
        defer { anthropicKeys.tearDown(provider: .claude) }
        let mistralKeys = try KeyFixture(provider: .mistral, secret: Self.mistralSecret)
        defer { mistralKeys.tearDown(provider: .mistral) }

        let anthropicTransport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let anthropic = AnthropicClient(transport: anthropicTransport, keys: anthropicKeys.source)
        _ = try await anthropic.estimate(text: "an apple")
        _ = try await anthropic.estimate(photo: tinyPhoto())
        _ = await anthropic.checkKey(APIKey(Self.anthropicSecret))

        let mistralTransport = RecordingTransport(
            status: 200,
            body: Reply.mistral(Reply.goodEstimate)
        )
        let mistral = MistralClient(transport: mistralTransport, keys: mistralKeys.source)
        _ = try await mistral.estimate(text: "an apple")
        _ = try await mistral.estimate(photo: tinyPhoto())
        _ = await mistral.checkKey(APIKey(Self.mistralSecret))

        let anthropicRequests = anthropicTransport.requests
        let mistralRequests = mistralTransport.requests
        let all = anthropicRequests + mistralRequests
        #expect(all.count == 6)

        // The absence assertions below are only half the guarantee: a client
        // that forgot to authorise at all would pass every one of them. The
        // estimate paths are covered by the header suite, so the two key
        // checks — which build their requests on their own paths — are
        // asserted positively here.
        let anthropicCheck = try #require(anthropicRequests.last)
        #expect(anthropicCheck.value(forHTTPHeaderField: "x-api-key") == Self.anthropicSecret)

        let mistralCheck = try #require(mistralRequests.last)
        #expect(
            mistralCheck.value(forHTTPHeaderField: "Authorization")
                == "Bearer \(Self.mistralSecret)"
        )

        for request in all {
            let url = try #require(request.url?.absoluteString)
            #expect(!url.contains(Self.anthropicSecret))
            #expect(!url.contains(Self.mistralSecret))
            #expect(request.url?.query == nil)

            if let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
                #expect(!text.contains(Self.anthropicSecret))
                #expect(!text.contains(Self.mistralSecret))
            }
        }
    }
}

// MARK: - Key checks

@Suite("Key checks")
struct KeyCheckTests {

    @Test("Anthropic spends one token, because a free check cannot see credit")
    func anthropicUsesMinimalMessage() async throws {
        let transport = RecordingTransport(
            status: 200,
            body: #"{"content":[{"type":"text","text":"Hi"}]}"#
        )
        let client = AnthropicClient(
            transport: transport,
            keys: ProviderKeySource(
                store: KeychainStore(service: "unused.\(UUID().uuidString)"),
                provider: .claude
            )
        )

        #expect(await client.checkKey(APIKey("sk-ant-abcdefghijklmnop")) == .passed)

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.lastPathComponent == "messages")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        // The whole point of this call is that it is the smallest one that can
        // still fail for an empty balance. A drift upwards here is the user's
        // money.
        #expect(json["max_tokens"] as? Int == 1)
        #expect(json["system"] == nil)
    }

    @Test("Mistral lists models, because that call is free and authenticates")
    func mistralUsesModelList() async throws {
        let transport = RecordingTransport(status: 200, body: #"{"data":[]}"#)
        let client = MistralClient(
            transport: transport,
            keys: ProviderKeySource(
                store: KeychainStore(service: "unused.\(UUID().uuidString)"),
                provider: .mistral
            )
        )

        #expect(await client.checkKey(APIKey("0123456789abcdefghij")) == .passed)

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/models")
        #expect(request.httpBody == nil)
    }

    @Test("a rejected key fails the check rather than throwing")
    func rejectedKey() async {
        let client = AnthropicClient(
            transport: RecordingTransport(status: 401, body: "{}"),
            keys: ProviderKeySource(
                store: KeychainStore(service: "unused.\(UUID().uuidString)"),
                provider: .claude
            )
        )

        #expect(await client.checkKey(APIKey("sk-ant-abcdefghijklmnop")) == .failed(.invalidKey))
    }

    @Test("an unpermitted key fails the check as a key not accepted")
    func forbiddenKeyCheck() async {
        let client = MistralClient(
            transport: RecordingTransport(status: 403, body: "{}"),
            keys: ProviderKeySource(
                store: KeychainStore(service: "unused.\(UUID().uuidString)"),
                provider: .mistral
            )
        )

        // Mistral's entitlement failure. The design has one screen for "this
        // key will not work", and this is it.
        #expect(await client.checkKey(APIKey("0123456789abcdefghij")) == .failed(.invalidKey))
    }

    @Test("an empty Anthropic balance fails the check with the billing link")
    func exhaustedBalance() async {
        let client = AnthropicClient(
            transport: RecordingTransport(
                status: 400,
                body: #"{"error":{"message":"Your credit balance is too low"}}"#
            ),
            keys: ProviderKeySource(
                store: KeychainStore(service: "unused.\(UUID().uuidString)"),
                provider: .claude
            )
        )

        // This is the reason Anthropic's key test spends a token: the free
        // /v1/models would have passed here.
        let expected = KeyCheckResult.failed(
            .noCredit(
                provider: .claude,
                billingPage: URL(string: "https://platform.claude.com/settings/billing")!
            )
        )
        #expect(await client.checkKey(APIKey("sk-ant-abcdefghijklmnop")) == expected)
    }

    @Test("a throttled key check is a retry, not a verdict on the key")
    func throttledKeyCheck() async {
        let client = MistralClient(
            transport: RecordingTransport(status: 429, body: "{}"),
            keys: ProviderKeySource(
                store: KeychainStore(service: "unused.\(UUID().uuidString)"),
                provider: .mistral
            )
        )

        #expect(await client.checkKey(APIKey("0123456789abcdefghij")) == .failed(.providerRefused))
    }

    @Test("a lost connection fails the check as a retry, not as a verdict")
    func offlineCheck() async {
        let client = AnthropicClient(
            transport: RecordingTransport.offline(),
            keys: ProviderKeySource(
                store: KeychainStore(service: "unused.\(UUID().uuidString)"),
                provider: .claude
            )
        )

        // Blaming the key for a train tunnel would have the user delete a key
        // that is fine.
        #expect(await client.checkKey(APIKey("sk-ant-abcdefghijklmnop")) == .failed(.network))
    }
}

// MARK: - Compression

@Suite("Photo compression")
struct MealPhotoCompressorTests {

    @Test("a photo is scaled to the long edge the providers stop paying for")
    func scalesDown() throws {
        let photo = try MealPhotoCompressor.compress(solidImage(width: 4000, height: 2000))
        let size = try #require(pixelSize(of: photo.jpegData))

        #expect(max(size.width, size.height) <= MealPhotoCompressor.longEdge)
        // The aspect ratio has to survive, or the model is looking at a
        // squashed plate.
        #expect(abs(size.width / size.height - 2) < 0.05)
        #expect(photo.jpegData.count <= MealPhotoCompressor.maximumBytes)
    }

    @Test("a photo already inside the limit is left alone")
    func leavesSmallImages() throws {
        let photo = try MealPhotoCompressor.compress(solidImage(width: 300, height: 200))
        #expect(pixelSize(of: photo.jpegData) == CGSize(width: 300, height: 200))
    }

    @Test("the long edge is measured in pixels, not points")
    func measuresPixels() throws {
        // 1000 points at scale 3 is 3000 pixels: inside the limit by the wrong
        // unit and well outside it by the right one. Reading `UIImage.size`
        // without its `scale` waved images like this through at three times
        // the resolution the providers charge for.
        let photo = try MealPhotoCompressor.compress(
            solidImage(width: 3000, height: 3000, scale: 3)
        )
        let size = try #require(pixelSize(of: photo.jpegData))
        #expect(max(size.width, size.height) <= MealPhotoCompressor.longEdge)
    }

    @Test("a photo still too large after compression fails before any request")
    func refusesOversized() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1200, height: 1200),
            format: format
        ).image { context in
            // Noise, so the encoder has something incompressible to work with.
            for x in stride(from: 0, to: 1200, by: 3) {
                for y in stride(from: 0, to: 1200, by: 3) {
                    UIColor(
                        red: .random(in: 0...1),
                        green: .random(in: 0...1),
                        blue: .random(in: 0...1),
                        alpha: 1
                    ).setFill()
                    context.fill(CGRect(x: x, y: y, width: 3, height: 3))
                }
            }
        }

        var thrown: AIError?
        do {
            let photo = try MealPhotoCompressor.compress(image, ceiling: 512)
            _ = try await client.estimate(photo: photo)
        } catch let error as AIError {
            thrown = error
        }

        #expect(thrown == .imageTooLarge)
        // The point of failing in the compressor: the user is not billed for
        // an upload the provider would have rejected.
        #expect(transport.requests.isEmpty)
    }
}

// MARK: - Food table grounding, wired

/// `FoodTableGrounding.groundAgainstBundledTable` is called from both
/// clients' `estimate(photo:)`/`estimate(text:)`, immediately after
/// `EstimateContract.estimate(from:mode:)` parses the reply — these are the
/// only tests in this file that exercise that call site rather than the
/// parsing it sits after. `FoodTableGroundingTests` already covers the
/// grounding logic itself against dozens of constructed cases; this is only
/// proof that a client's return value is the grounded one, not the model's
/// raw one.
@Suite("Food table grounding, wired")
struct FoodTableGroundingWiredTests {

    /// The bug this whole table exists to close, run end to end: a canned
    /// reply answers `r45g` of polenta the same wrong way the real model once
    /// did — 72 kcal, the cooked row's price for a raw weight — and the
    /// client is expected to hand back the raw row's price instead, because
    /// grounding now sits between the parse and the return.
    @Test("A raw-marked polenta reply is corrected before it leaves the client")
    func anthropicTextIsGrounded() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.wrongPolenta)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        let estimate = try await client.estimate(text: "r45g polenta")

        #expect(estimate.kilocalories == 158)
        #expect(estimate.macros == MacroTotals(protein: 4, carbs: 33, fat: 1))
        #expect(estimate.items[0].kilocalories == 158)
    }

    /// The same reply, the other provider — grounding does not care which
    /// client called it.
    @Test("Mistral's reply is corrected the same way")
    func mistralTextIsGrounded() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.mistral(Reply.wrongPolenta)
        )
        let client = MistralClient(transport: transport, keys: keys.source)

        let estimate = try await client.estimate(text: "r45g polenta")

        #expect(estimate.kilocalories == 158)
    }

    /// A sentence with no marker grounds against the prepared row instead —
    /// proof the client is not just always substituting the raw price.
    @Test("The same food without the marker is corrected to the prepared row")
    func unmarkedTextIsGroundedToPreparedRow() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.wrongPolenta)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        let estimate = try await client.estimate(text: "45g polenta")

        #expect(estimate.kilocalories == 34)
    }

    /// Photo mode benefits from the same table, priced from the model's own
    /// approximate weight rather than a typed one.
    @Test("A photo reply is corrected using the model's own approximate weight")
    func photoIsGrounded() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.wrongRicePhoto)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        let estimate = try await client.estimate(photo: tinyPhoto())

        #expect(estimate.kilocalories != 999)
    }

    /// A food the table cannot confidently resolve leaves the client's answer
    /// exactly as the model wrote it — grounding is additive, never a reason
    /// an estimate the user paid for comes back different for the worse.
    @Test("An unresolvable food passes through the client untouched")
    func unresolvableFoodPassesThrough() async throws {
        let keys = try KeyFixture(provider: .claude, secret: "sk-ant-abcdefghijklmnop")
        defer { keys.tearDown(provider: .claude) }

        let transport = RecordingTransport(
            status: 200,
            body: Reply.anthropic(Reply.goodEstimate)
        )
        let client = AnthropicClient(transport: transport, keys: keys.source)

        let estimate = try await client.estimate(text: "porridge with berries")

        #expect(estimate.kilocalories == 420)
    }
}

extension Reply {

    /// What the model once actually answered for `r45g` of polenta: 72 kcal,
    /// the cooked row's price applied to a raw weight. The raw-weight
    /// instruction was sent and read; the arithmetic afterwards was still
    /// wrong, which is the reason this table exists rather than a better
    /// paragraph of prompt.
    fileprivate static let wrongPolenta = """
        {"title":"Polenta","kilocalories":72,"protein_g":2,"carbs_g":15,"fat_g":0,\
        "items":[{"name":"Polenta","kilocalories":72,"grams":45,\
        "confidence":"confident","amount":"recognised"}]}
        """

    fileprivate static let wrongRicePhoto = """
        {"title":"Rice","kilocalories":999,"protein_g":0,"carbs_g":0,"fat_g":0,\
        "items":[{"name":"Rice","kilocalories":999,"grams":150,\
        "confidence":"unsure","amount":"estimated"}]}
        """
}
