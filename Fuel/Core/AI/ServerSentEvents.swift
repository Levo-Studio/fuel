import Foundation

// MARK: - Framing

/// Splits a `text/event-stream` body into its lines, **empty ones included**.
///
/// **Written out rather than taken from Foundation's `AsyncLineSequence`, and
/// that is the entire reason this type exists.** That sequence is built for
/// reading prose and documents itself as not wanting to hand back an empty
/// line, so it silently swallows every blank one. In every other format a blank
/// line is nothing. In this one it is the only byte sequence that *means*
/// something: it is the dispatch, and the `data` fields before it are delivered
/// by it and by nothing else.
///
/// Read with `.lines`, a perfectly ordinary provider stream therefore arrives
/// as a run of `data:` fields that are gathered and never delivered.
/// `ServerSentEventDecoder` returns `nil` for every line, not one byte of the
/// model's answer reaches `MealChatStreamAssembler`, and the turn ends at
/// `MealChatContract.intent(from: "")` — which is `AIError.malformedResponse`,
/// and on screen "The answer did not come back in a form Fuel could read."
/// Every message, on both providers, with nothing wrong at either end.
///
/// It was invisible to the suite because the test transport hands the decoder a
/// list of lines the test itself wrote, blank ones and all. Splitting the bytes
/// was the one part of reading a stream that nothing exercised, on the grounds
/// that `URLSession` already did it. It does — by a different rule than this
/// format has.
///
/// The rule here is the format's own: `\n`, `\r` and `\r\n` each end one line,
/// and whatever follows the last terminator is a line as well.
nonisolated struct ServerSentEventLineSplitter {

    private var buffer: [UInt8] = []

    /// Whether the previous byte was a `\r`, so an `\n` behind it is the other
    /// half of one terminator rather than a second, empty line.
    private var afterCarriageReturn = false

    init() {}

    /// Feeds one byte and returns the line it ended, if it ended one. A blank
    /// line comes back as the empty string, which is the whole point.
    ///
    /// Throws `AIError.malformedResponse` where a line runs past
    /// `maximumLineLength`, which is not a line this format carries — that
    /// constant says why the stream fails rather than skipping it.
    mutating func append(_ byte: UInt8) throws -> String? {
        if afterCarriageReturn {
            afterCarriageReturn = false
            if byte == Self.lineFeed {
                return nil
            }
        }

        switch byte {
        case Self.carriageReturn:
            afterCarriageReturn = true
            return take()
        case Self.lineFeed:
            return take()
        default:
            guard buffer.count < Self.maximumLineLength else {
                throw AIError.malformedResponse
            }
            buffer.append(byte)
            return nil
        }
    }

    /// Whatever the body ended on with no terminator behind it.
    ///
    /// `nil` rather than an empty string for a body that ended on one, so a
    /// well-formed stream does not gain a blank line it never sent.
    mutating func flush() -> String? {
        buffer.isEmpty ? nil : take()
    }

    private mutating func take() -> String {
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(decoding: buffer, as: UTF8.self)
    }

    // MARK: - Bounds

    /// The longest line this format is allowed to carry, past which the stream
    /// fails.
    ///
    /// **Without a bound the buffer is the whole body.** A `200`
    /// `text/event-stream` that never sends a terminator — a proxy dumping an
    /// HTML page under the wrong content type, an endpoint answering in
    /// something that is not this format at all — accumulates every byte it
    /// sends in memory. The only thing stopping it today is
    /// `URLSession.fuel`'s sixty-second request timeout, which is an incidental
    /// consequence of a setting about waiting, not a limit on what a body may
    /// cost. The refusal path is already bounded at `AIError.readableErrorBody`
    /// and the accepted path had nothing.
    ///
    /// **The stream fails rather than dropping the overlong line and carrying
    /// on**, and that is the half of this worth arguing. Dropping a line leaves
    /// `MealChatStreamAssembler` a reply with a hole in it, and a hole is not
    /// reliably fatal: lose the delta carrying `"changes":[{"item":1,"grams":300}],`
    /// and what is left is `{"additions":[],"reply":"Raised the rice to 300 g."}`,
    /// which parses cleanly as a turn that asked for nothing — so the sentence
    /// saying the rice was raised is drawn with nothing under it to say the meal
    /// never moved. A quietly wrong answer is the one outcome this layer refuses
    /// everywhere else — `ServerSentEventDecoder` will not dispatch half an
    /// event for the same reason. Failing costs the user the retry state, which
    /// is a screen the design draws, and `AIError.malformedResponse` is the
    /// honest reading of it: the answer did not come back in a form Fuel could
    /// read.
    ///
    /// **64 KiB, and deliberately not `AIError.readableErrorBody`.** That bound
    /// is 8 KiB and answers a different question — how far into a *refused*
    /// body it is worth searching for two substrings. On the accepted path a
    /// single `data:` field may legitimately carry a whole answer, and
    /// `MealChatContract.maxTokens` allows 2048 of them, which is already
    /// somewhere near 8 KiB of text before JSON escaping and the envelope
    /// around it. Reusing that number would refuse a valid stream. 64 KiB
    /// clears any line either provider can send by a wide margin, and still
    /// catches a body with no terminator in it in the first fraction of a
    /// second instead of at the timeout.
    static let maximumLineLength = 64 * 1024

    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
}

// MARK: - Server-sent events

/// The framing both providers stream in, decoded once rather than in each
/// client.
///
/// `text/event-stream` is a line format: fields of the form `field: value`,
/// with a blank line ending an event and dispatching whatever `data` fields it
/// gathered. Anthropic and Mistral send one `data` line per event and would be
/// served by a `hasPrefix("data: ")` check, but the format allows an event's
/// payload to be split across several `data` lines and the spec's own answer —
/// join them with a newline — costs four lines here and removes the class of
/// bug where a long reply happens to be framed the other way one morning.
///
/// **It knows nothing about either provider.** What a payload *means* is the
/// client's business: this type answers only "has an event finished, and what
/// was in it".
nonisolated struct ServerSentEventDecoder {

    /// The `data` fields gathered since the last dispatch.
    private var pending: [String] = []

    init() {}

    /// Feeds one line and returns the event it completed, if it completed one.
    ///
    /// **A blank line is the dispatch**, which is why this cannot be a pure
    /// function over a line: the lines before it carry the payload and the
    /// blank one carries nothing but the instruction to deliver it.
    ///
    /// An event with no `data` field — a bare `event: ping`, a comment —
    /// dispatches nothing, so a keep-alive costs the caller no iteration.
    /// An event whose blank line never arrives is never returned, which is the
    /// spec's own rule and the right one here: a payload missing its last line
    /// is half a JSON object, and half an object read as whole is the failure
    /// the parser refuses everywhere else.
    mutating func decode(_ line: String) -> String? {
        // A line starting with a colon is a comment. Both providers use one as
        // a keep-alive, and the spec says to ignore it.
        guard !line.hasPrefix(":") else {
            return nil
        }

        guard !line.isEmpty else {
            guard !pending.isEmpty else {
                return nil
            }
            let event = pending.joined(separator: "\n")
            pending.removeAll(keepingCapacity: true)
            return event
        }

        guard let colon = line.firstIndex(of: ":") else {
            // A field with no value. Nothing Fuel reads takes that shape.
            return nil
        }

        guard line[..<colon] == "data" else {
            // `event:` and `id:` are the other two either provider sends.
            // Neither says anything the payload does not, and reading the event
            // name would tie this type to one provider's vocabulary.
            return nil
        }

        // Exactly one leading space is part of the framing rather than of the
        // value, and only one: `data:  {` carries a payload that begins with a
        // space.
        var value = line[line.index(after: colon)...]
        if value.first == " " {
            value = value.dropFirst()
        }
        pending.append(String(value))
        return nil
    }
}
