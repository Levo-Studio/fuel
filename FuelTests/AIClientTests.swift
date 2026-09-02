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
        return #"{"content":[{"type":"text","text":\#(quoted)}]}"#
    }

    static func mistral(_ text: String) -> String {
        let escaped = String(
            data: try! JSONSerialization.data(withJSONObject: [text], options: .fragmentsAllowed),
            encoding: .utf8
        )!
        let quoted = String(escaped.dropFirst().dropLast())
        return #"{"choices":[{"message":{"role":"assistant","content":\#(quoted)}}]}"#
    }
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
        #expect(estimate.kilocalories == 420)
        #expect(estimate.macros == MacroTotals(protein: 14, carbs: 62, fat: 11))
        #expect(estimate.items.count == 2)
        #expect(estimate.items[0].name == "Porridge")
        #expect(estimate.items[0].kilocalories == 300)
        // A photo carries a confidence and an approximate weight; the note is
        // the second line of the row on screen 14.
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

        #expect(estimate.kilocalories == 420)
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

        await #expect(throws: AIError.network) {
            _ = try await client.estimate(text: "an apple")
        }
    }

    @Test("a bare 429 is a retry at Mistral too")
    func rateLimitedMistral() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        let transport = RecordingTransport(status: 429, body: "{}")
        let client = MistralClient(transport: transport, keys: keys.source)

        await #expect(throws: AIError.network) {
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

    @Test("a 500 is a plain retry rather than a fourth state")
    func serverError() async throws {
        let keys = try KeyFixture(provider: .mistral, secret: "0123456789abcdefghij")
        defer { keys.tearDown(provider: .mistral) }

        let client = MistralClient(
            transport: RecordingTransport(status: 500, body: "{}"),
            keys: keys.source
        )

        await #expect(throws: AIError.network) {
            _ = try await client.estimate(text: "an apple")
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

        #expect(await client.checkKey(APIKey("0123456789abcdefghij")) == .failed(.network))
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
