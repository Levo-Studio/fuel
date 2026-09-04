import Foundation

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

    /// Whether the stream ended in the middle of an event.
    ///
    /// The spec discards an undispatched event at the end of a stream, and so
    /// does Fuel: a payload whose blank line never arrived is a payload whose
    /// last line may also be missing, and half a JSON object read as if it were
    /// whole is exactly the failure the parser refuses everywhere else.
    var hasUndispatchedEvent: Bool {
        !pending.isEmpty
    }
}
