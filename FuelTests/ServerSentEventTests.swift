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
        var decoder = ServerSentEventDecoder()
        #expect(decoder.decode(#"data: {"partial":"#) == nil)
        #expect(decoder.hasUndispatchedEvent)
    }

    @Test("a stream that ended cleanly has nothing left over")
    func nothingLeftOver() {
        var decoder = ServerSentEventDecoder()
        _ = decoder.decode("data: done")
        _ = decoder.decode("")
        #expect(!decoder.hasUndispatchedEvent)
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
