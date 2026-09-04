import Foundation
import Testing

@testable import Fuel

// MARK: - Framing

/// The line format both providers stream in, held to the spec rather than to
/// the shape either of them happens to send today.
///
/// **Nothing here touches a network.** The decoder is fed lines, which is
/// exactly what a transport hands it.
@Suite("Server-sent events")
struct ServerSentEventTests {

    /// Feeds a whole transcript and collects the events it dispatched.
    private func events(from lines: [String]) -> [String] {
        var decoder = ServerSentEventDecoder()
        return lines.compactMap { decoder.decode($0) }
    }

    // MARK: - The ordinary shape

    @Test("a data line followed by a blank line is one event")
    func oneEvent() {
        #expect(events(from: [#"data: {"a":1}"#, ""]) == [#"{"a":1}"#])
    }

    @Test("the event name is read and discarded, and only the payload comes out")
    func namedEvent() {
        let lines = [
            "event: content_block_delta",
            #"data: {"delta":{"text":"Hi"}}"#,
            "",
        ]
        #expect(events(from: lines) == [#"{"delta":{"text":"Hi"}}"#])
    }

    @Test("several events arrive in the order they were sent")
    func severalEvents() {
        let lines = ["data: one", "", "data: two", "", "data: three", ""]
        #expect(events(from: lines) == ["one", "two", "three"])
    }

    // MARK: - What the spec says and a prefix check would not

    /// The case a `hasPrefix("data: ")` check gets wrong: one payload written
    /// across two fields.
    @Test("a payload split across two data lines is joined with a newline")
    func splitPayload() {
        #expect(events(from: ["data: {\"a\":", "data: 1}", ""]) == ["{\"a\":\n1}"])
    }

    @Test("exactly one space after the colon is framing, and a second is payload")
    func leadingSpace() {
        #expect(events(from: ["data:  padded", ""]) == [" padded"])
        #expect(events(from: ["data:tight", ""]) == ["tight"])
    }

    @Test("a comment is a keep-alive and dispatches nothing")
    func comment() {
        #expect(events(from: [": ping", "", "data: real", ""]) == ["real"])
    }

    @Test("an event with no data field costs the caller no iteration")
    func nothingToDeliver() {
        #expect(events(from: ["event: ping", "", "id: 7", ""]).isEmpty)
    }

    // MARK: - A stream that stopped mid-event

    /// Half an event is half a JSON object, and a parser that read one as
    /// whole is the failure the rest of this layer refuses everywhere else.
    @Test("a payload whose blank line never arrived is not dispatched")
    func undispatched() {
        #expect(events(from: [#"data: {"partial":"#]).isEmpty)
        #expect(events(from: [#"data: {"whole":1}"#, "", #"data: {"partial":"#]) == [#"{"whole":1}"#])
    }
}

// MARK: - Reading a refusal

/// What a stream that was refused is allowed to cost.
@Suite("Streamed refusals")
struct StreamedRefusalTests {

    private func response(_ lines: [String], status: Int = 429) -> HTTPStreamResponse {
        HTTPStreamResponse(
            statusCode: status,
            lines: AsyncThrowingStream { continuation in
                for line in lines {
                    continuation.yield(line)
                }
                continuation.finish()
            }
        )
    }

    @Test("a refusal body is collected far enough for the credit signal to be found")
    func collectsEnough() async {
        let body = await response([#"{"error":{"message":"Your credit balance is too low"}}"#]).refusalBody()

        #expect(
            AIError.from(status: 400, body: body, provider: .claude)
                == .noCredit(for: .claude)
        )
    }

    /// The bound is the one the mapping itself will not read past, so nothing
    /// is collected that could never be used.
    @Test("a body far past the readable bound is not collected whole")
    func stopsAtTheBound() async {
        let filler = String(repeating: "x", count: 1024)
        let body = await response(Array(repeating: filler, count: 64)).refusalBody()

        #expect(body.count >= AIError.readableErrorBody)
        #expect(body.count < AIError.readableErrorBody + filler.utf8.count)
    }

    /// A refusal whose body did not finish arriving is still a refusal, and the
    /// status has already said which one.
    @Test("a refusal body that dies part-way still maps on what was read")
    func survivesAnInterruption() async {
        let stream = HTTPStreamResponse(
            statusCode: 400,
            lines: AsyncThrowingStream { continuation in
                continuation.yield(#"{"error":{"message":"insufficient_quota"}"#)
                continuation.finish(throwing: URLError(.networkConnectionLost))
            }
        )

        let body = await stream.refusalBody()
        #expect(AIError.from(status: 400, body: body, provider: .mistral) == .noCredit(for: .mistral))
    }
}

// MARK: - Framing the bytes

/// How a body's bytes become the lines the decoder reads.
///
/// **This is the seam the chat was broken in, and it was broken for every
/// message on both providers.** `URLSession.stream` handed the body to
/// Foundation's `AsyncLineSequence`, which documents itself as not wanting to
/// return an empty line and therefore drops every blank one. In this format the
/// blank line is the dispatch: it is the only thing that says "the fields
/// gathered so far are an event, deliver them". Without it
/// `ServerSentEventDecoder` gathers `data` fields forever and returns `nil` for
/// every line, `MealChatStreamAssembler` is never fed a character, and the turn
/// ends at `MealChatContract.intent(from: "")` — `AIError.malformedResponse`,
/// drawn as "The answer did not come back in a form Fuel could read."
///
/// Nothing above this level could see it. The transport double is handed a list
/// of lines the test wrote, blank ones included, so the decoder was fed exactly
/// what it wanted and every client test passed against a wire nobody framed.
///
/// **Nothing here touches a network.** The rule is a pure function of bytes and
/// is tested as one.
@Suite("Server-sent events · framing")
struct ServerSentEventFramingTests {

    /// A whole body, framed the way `URLSession.stream` frames one.
    private func lines(of body: String) throws -> [String] {
        var splitter = ServerSentEventLineSplitter()
        var framed: [String] = []
        for byte in Array(body.utf8) {
            if let line = try splitter.append(byte) {
                framed.append(line)
            }
        }
        if let last = splitter.flush() {
            framed.append(last)
        }
        return framed
    }

    // MARK: - The line that means something

    @Test("the blank line between two events is delivered, because it is the dispatch")
    func blankLineSurvives() throws {
        #expect(try lines(of: "data: one\n\ndata: two\n\n") == ["data: one", "", "data: two", ""])
    }

    /// The counter-check, and the reason this type exists rather than a call to
    /// `bytes.lines`. The same bytes, read the way Foundation reads prose: the
    /// dispatch is gone, and with it the whole answer.
    @Test("Foundation's own line reader drops that line, and the events with it")
    func foundationDropsTheDispatch() async throws {
        var read: [String] = []
        for try await line in Bytes(of: "data: one\n\ndata: two\n\n").lines {
            read.append(line)
        }

        #expect(read == ["data: one", "data: two"])

        var decoder = ServerSentEventDecoder()
        #expect(read.compactMap { decoder.decode($0) }.isEmpty)
    }

    // MARK: - The three terminators

    @Test("a carriage return ends a line on its own")
    func carriageReturn() throws {
        #expect(try lines(of: "data: one\r\rdata: two\r\r") == ["data: one", "", "data: two", ""])
    }

    @Test("a carriage return and a line feed together end one line and not two")
    func carriageReturnLineFeed() throws {
        #expect(try lines(of: "data: one\r\n\r\n") == ["data: one", ""])
    }

    @Test("a line feed after ordinary bytes is not swallowed as half a pair")
    func lineFeedAfterText() throws {
        #expect(try lines(of: "a\rb\nc\n") == ["a", "b", "c"])
    }

    // MARK: - The ends of the body

    @Test("a body that ends without a terminator still delivers its last line")
    func unterminatedTail() throws {
        #expect(try lines(of: "data: one\n\ndata: two") == ["data: one", "", "data: two"])
    }

    /// A body that ended on its terminator has nothing left, and must not gain
    /// a blank line it never sent — a spurious dispatch would deliver whatever
    /// was gathered as though the provider had said to.
    @Test("a body that ends on a terminator gains no line of its own")
    func terminatedTail() throws {
        #expect(try lines(of: "data: one\n") == ["data: one"])
        #expect(try lines(of: "") == [])
    }

    // MARK: - A line that is not a line

    /// The bound is there to catch a body with no terminator in it, not to
    /// refuse a long answer, so a line that reaches it exactly still frames.
    @Test("a line as long as the bound allows is still a line")
    func lineAtTheBound() throws {
        let line = String(repeating: "x", count: ServerSentEventLineSplitter.maximumLineLength)
        #expect(try lines(of: line + "\n") == [line])
    }

    /// **The buffer used to be the whole body.** A `200` `text/event-stream`
    /// that never sends a terminator accumulated every byte of it in memory,
    /// bounded only by the request timeout — a setting about waiting, not about
    /// what a response may cost. The count is asserted as well as the throw:
    /// stopping at the bound is the whole claim, and a splitter that read the
    /// body and then complained would satisfy `#expect(throws:)` on its own.
    @Test("a body that runs past the bound fails the stream, at the bound")
    func pastTheBound() {
        var splitter = ServerSentEventLineSplitter()
        var read = 0

        #expect(throws: AIError.malformedResponse) {
            for byte in Array(repeating: UInt8(ascii: "x"), count: 4 * ServerSentEventLineSplitter.maximumLineLength) {
                _ = try splitter.append(byte)
                read += 1
            }
        }

        #expect(read == ServerSentEventLineSplitter.maximumLineLength)
    }

    // MARK: - A whole turn

    /// The claim that matters: a provider's own transcript, framed from its
    /// bytes, dispatches every event in it.
    @Test("an Anthropic transcript framed from its bytes dispatches every event")
    func anthropicTranscript() throws {
        let body = """
            event: message_start
            data: {"type":"message_start","message":{"id":"msg_1","role":"assistant"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

            event: message_delta
            data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

            event: message_stop
            data: {"type":"message_stop"}


            """

        var decoder = ServerSentEventDecoder()
        let payloads = try lines(of: body).compactMap { decoder.decode($0) }

        #expect(payloads.count == 4)
        #expect(payloads.contains(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#))
    }

    /// Mistral's, including the sentinel that is not JSON.
    @Test("a Mistral transcript framed from its bytes dispatches every event")
    func mistralTranscript() throws {
        let body = """
            data: {"id":"c1","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}

            data: {"id":"c1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

            data: [DONE]


            """

        var decoder = ServerSentEventDecoder()
        let payloads = try lines(of: body).compactMap { decoder.decode($0) }

        #expect(payloads.count == 3)
        #expect(payloads.last == "[DONE]")
    }
}

// MARK: - Bytes

/// A body as a byte sequence, so the counter-check above can put the same bytes
/// through Foundation's reader that `URLSession.stream` used to.
private struct Bytes: AsyncSequence, Sendable {

    typealias Element = UInt8

    let bytes: [UInt8]

    init(of body: String) {
        bytes = Array(body.utf8)
    }

    struct Iterator: AsyncIteratorProtocol {

        var rest: ArraySlice<UInt8>

        mutating func next() async -> UInt8? {
            guard let first = rest.first else { return nil }
            rest = rest.dropFirst()
            return first
        }
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(rest: bytes[...])
    }
}
