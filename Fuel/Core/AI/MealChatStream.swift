import Foundation

// MARK: - What a half-written reply says

/// The two things worth knowing about an adjustment object that has not
/// finished arriving.
nonisolated struct MealChatStreamProgress: Sendable, Equatable {

    /// The model's sentence as far as it has been written, already bounded —
    /// `nil` where it has not begun, or has run past the bound.
    var sentence: String?

    /// Whether the model has committed to moving something.
    ///
    /// **Read off its own data, not off a claim it made about itself.** A
    /// declared intent would be a field a model can get wrong in either
    /// direction; an open `changes` array with an object in it is the model
    /// already writing the change.
    var movesSomething: Bool

    init(sentence: String? = nil, movesSomething: Bool = false) {
        self.sentence = sentence
        self.movesSomething = movesSomething
    }
}

// MARK: - Reading a partial object

/// Reads an answer that is still being written — an adjustment object, or the
/// sentences of a reply that never opened one.
///
/// **Why a reader of its own rather than "try `JSONDecoder` and shrug".** A
/// half-written object is not malformed JSON that might parse next time — it is
/// JSON that is *guaranteed* not to parse until the last byte, so a decoder
/// answers nothing at all until there is nothing left to wait for. What the
/// screen needs is the opposite: the sentence while it is being written, and
/// the fact that a change is coming before it has arrived.
///
/// **Nothing here decides anything about the meal.** The complete reply is
/// still handed to `MealChatContract.intent(from:)` at the end and parsed by
/// the same decoder as before, and every weight that reaches the store comes
/// from that parse. This type only decides what the user is looking at while
/// they wait, so a reply it misreads costs a waiting screen and never a figure.
///
/// It re-scans the whole buffer on each delta rather than keeping a resumable
/// position. A reply is a sentence and a handful of two-field objects — the
/// token ceiling bounds it — and a tokeniser that can be suspended mid-escape
/// is a great deal more code to get wrong than a scan of a kilobyte.
nonisolated enum MealChatStreamReader {

    // MARK: - Entry point

    static func progress(in raw: String) -> MealChatStreamProgress {
        // The same tolerance `EstimateContract.firstJSONObject` has: a model
        // that wrote a code fence or a word of prose first has still answered.
        guard let opening = raw.firstIndex(of: "{") else {
            // **Nothing but words so far, so the words are the sentence.** A
            // prose answer has no `reply` key to read one out of, and waiting
            // for a key that is never coming would leave the sheet saying it
            // was writing until the last token and then produce a finished
            // paragraph in one jump — the one shape of reply that streams for
            // nothing. Read as prose it arrives a word at a time like every
            // other answer.
            //
            // A model that is about to open an object has usually already
            // opened it, and where it wrote a preamble first that preamble is
            // drawn for as long as it takes the brace to arrive and is then
            // replaced by the object's own sentence. That costs a redraw on a
            // reply that ignored "no prose before it"; it never costs a weight,
            // because nothing here decides one.
            return MealChatStreamProgress(sentence: Self.prose(in: raw))
        }

        var progress = MealChatStreamProgress()
        var depth = 1
        var index = raw.index(after: opening)

        while index < raw.endIndex, depth > 0 {
            switch raw[index] {
            case "\"":
                let literal = Self.literal(in: raw, from: index)
                guard let end = literal.end else {
                    // An unterminated string is the end of what has arrived,
                    // and anything after it has not been written yet.
                    return progress
                }
                index = end

                let colon = Self.skippingWhitespace(in: raw, from: index)
                guard colon < raw.endIndex, raw[colon] == ":" else {
                    // A value rather than a key. The loop reads it again on the
                    // next turn and finds nothing after it either.
                    continue
                }

                let value = Self.skippingWhitespace(in: raw, from: raw.index(after: colon))
                // Only the outermost keys are read: `item`, `grams` and `name`
                // live inside the arrays and mean nothing to this scan.
                guard depth == 1, let key = Self.decoded(literal.body) else {
                    continue
                }

                switch key {
                case Self.replyKey:
                    progress.sentence = Self.sentence(at: value, in: raw)
                case Self.changesKey, Self.additionsKey:
                    progress.movesSomething = progress.movesSomething || Self.hasAnElement(at: value, in: raw)
                default:
                    break
                }
                continue

            case "{", "[":
                depth += 1
            case "}", "]":
                depth -= 1
            default:
                break
            }

            index = raw.index(after: index)
        }

        return progress
    }

    // MARK: - Keys

    private static let replyKey = "reply"
    private static let changesKey = "changes"
    private static let additionsKey = "additions"

    // MARK: - The sentence

    /// The buffer read as an answer written in sentences, or `nil` where it is
    /// not one.
    ///
    /// `MealChatContract.readsAsProse(_:)` is what says which, and it is the
    /// same question the finished parse asks, so a reply cannot stream as prose
    /// and then land as a fragment: a fence that has begun to arrive is not a
    /// sentence here either. The bound is `boundedProse`'s, for the reason it
    /// is not the sentence's — and past it this answers `nil` and the last
    /// thing drawn stays, exactly as an overlong `reply` does.
    private static func prose(in raw: String) -> String? {
        guard MealChatContract.readsAsProse(raw) else {
            return nil
        }
        return MealChatContract.boundedProse(raw)
    }

    /// The `reply` value, however much of it there is.
    ///
    /// It goes through `MealChatContract.boundedReply` rather than a bound of
    /// its own, so a sentence being written is held to exactly the rule the
    /// finished one is held to. That includes the drop: past the bound this
    /// answers `nil`, the last thing drawn stays on screen, and the completed
    /// turn replaces it with one of Fuel's own fixed sentences. A model that
    /// ignored "one or two short sentences" does not get to write a wall of
    /// text into the transcript one word at a time either.
    private static func sentence(at start: String.Index, in raw: String) -> String? {
        guard start < raw.endIndex, raw[start] == "\"" else {
            return nil
        }
        return MealChatContract.boundedReply(Self.decoded(Self.literal(in: raw, from: start).body))
    }

    // MARK: - The arrays

    /// Whether the array beginning at `start` has an element in it.
    ///
    /// `[` then `{` and nothing between them but space. An empty array is the
    /// model saying it is moving nothing, and it is the shape a question comes
    /// back as.
    ///
    /// **An object that turns out to be unusable still counts here**, and that
    /// is the honest direction: the model has begun writing a change, which is
    /// what the waiting screen is about. If the change is then dropped —
    /// `MealAdjuster` refuses a row it cannot price — the turn lands saying
    /// nothing moved, which the transcript states in words underneath.
    private static func hasAnElement(at start: String.Index, in raw: String) -> Bool {
        guard start < raw.endIndex, raw[start] == "[" else {
            return false
        }
        let element = Self.skippingWhitespace(in: raw, from: raw.index(after: start))
        return element < raw.endIndex && raw[element] == "{"
    }

    // MARK: - Scanning

    /// The body of the string literal beginning at `start`, and where it ends.
    ///
    /// `end` is `nil` for a literal whose closing quote has not arrived, and
    /// the body is then everything written so far — which is the case this
    /// whole file exists for.
    private static func literal(
        in raw: String,
        from start: String.Index
    ) -> (body: Substring, end: String.Index?) {
        let bodyStart = raw.index(after: start)
        var index = bodyStart
        var escaped = false

        while index < raw.endIndex {
            let character = raw[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return (raw[bodyStart..<index], raw.index(after: index))
            }
            index = raw.index(after: index)
        }

        return (raw[bodyStart...], nil)
    }

    private static func skippingWhitespace(in raw: String, from start: String.Index) -> String.Index {
        var index = start
        while index < raw.endIndex, raw[index].isWhitespace {
            index = raw.index(after: index)
        }
        return index
    }

    /// A JSON string literal's body, with its escapes resolved.
    ///
    /// **Closed and handed to the real parser rather than unescaped by hand.**
    /// `\n`, `\uXXXX` and a surrogate pair spelled as two of them are all
    /// things `JSONSerialization` already gets right, and a second
    /// implementation of them here would be a second implementation to get
    /// wrong. Wrapped in an array so the input is an ordinary JSON document
    /// rather than a bare fragment.
    ///
    /// A body that stops in the middle of an escape cannot be closed, so the
    /// partial escape is dropped first. If it still will not parse the answer
    /// is `nil` and the next delta tries again — a sentence one word behind for
    /// one turn of the loop, never a wrong one.
    private static func decoded(_ body: Substring) -> String? {
        let closable = Self.droppingPartialEscape(body)
        guard
            let data = "[\"\(closable)\"]".data(using: .utf8),
            let decoded = try? JSONSerialization.jsonObject(with: data) as? [String],
            let value = decoded.first
        else {
            return nil
        }
        return value
    }

    /// `body` without a trailing escape sequence that has not finished
    /// arriving.
    private static func droppingPartialEscape(_ body: Substring) -> Substring {
        var text = body

        // `\u` needs four hex digits behind it, and a stream can stop after
        // any of them.
        if let escape = text.range(of: "\\u", options: .backwards) {
            let digits = text[escape.upperBound...]
            if digits.count < 4, digits.allSatisfy(\.isHexDigit) {
                text = text[..<escape.lowerBound]
            }
        }

        // An odd number of trailing backslashes means the last one is opening
        // an escape whose character has not arrived.
        var trailing = 0
        for character in text.reversed() {
            guard character == "\\" else { break }
            trailing += 1
        }
        if trailing.isMultiple(of: 2) == false {
            text = text.dropLast()
        }

        return text
    }
}

// MARK: - Assembling a turn

/// Gathers a streamed reply and says what each delta changed.
///
/// **The half both provider clients share.** What differs between Anthropic and
/// Mistral is the envelope a delta arrives in; what a delta *means* — a longer
/// sentence, a change the model has committed to, an answer that is finished —
/// is the same question on both, and asking it twice would be two places for
/// the rule to drift.
///
/// Nothing here is logged, written to disk, or kept after the turn: the
/// accumulated text lives for as long as the stream and goes out of scope with
/// it.
nonisolated struct MealChatStreamAssembler {

    private var raw = ""
    private var sentence: String?
    private var announcedAChange = false
    private var ranOutOfTokens = false

    init() {}

    // MARK: - Feeding it

    /// Adds a delta and returns the events it produced, which is usually none.
    ///
    /// **`adjusting` comes before `sentence`**: it is the event that decides
    /// which screen the user is looking at, and a delta that carries both
    /// should not draw a word into a transcript that is about to be covered.
    mutating func append(_ delta: String) -> [MealChatEvent] {
        guard !delta.isEmpty else {
            return []
        }
        raw += delta

        let progress = MealChatStreamReader.progress(in: raw)
        var events: [MealChatEvent] = []

        if progress.movesSomething, !announcedAChange {
            announcedAChange = true
            events.append(.adjusting)
        }

        if let written = progress.sentence, written != sentence {
            sentence = written
            events.append(.sentence(written))
        }

        return events
    }

    /// Records that the model stopped because it hit the request's own token
    /// ceiling. Each client says so in its provider's word for it.
    mutating func noteRanOutOfTokens() {
        ranOutOfTokens = true
    }

    // MARK: - Finishing it

    /// The turn, complete.
    ///
    /// **The structured half is parsed exactly as it was before any of this
    /// streamed**: the complete reply through `MealChatContract.intent(from:)`
    /// and one pass through `MealAdjuster`. Nothing the partial reader said is
    /// carried into it — including the prose it drew, which is read again from
    /// the whole buffer here. Streaming buys the sentence its progressive
    /// arrival and buys the screen its early warning; it buys the weights
    /// nothing, and the weights are the part that must not be guessed at.
    ///
    /// Throws `AIError.truncatedReply` where the provider said it ran into the
    /// ceiling before an object was finished — and not where it said so after
    /// one was, because a model that completed its answer and was cut off
    /// writing the newline behind it has still answered.
    ///
    /// **The question is asked before the parse rather than after it, and that
    /// is what changed when prose became readable.** It used to be enough to
    /// wait for the parse to fail: a cut-off reply was unreadable by
    /// definition. A cut-off *sentence* is now perfectly readable, and left to
    /// itself would land in the transcript looking like a finished answer that
    /// simply stops mid-word. Both halves of the ceiling — an object that never
    /// closed and a sentence that never ended — are the same thing to the user,
    /// and both are the retry state.
    func finish(over meal: AdjustableMeal) throws -> MealChatEvent {
        guard !ranOutOfTokens || MealChatContract.carriesAnObject(raw) else {
            throw AIError.truncatedReply
        }

        let intent = try MealChatContract.intent(from: raw)

        return .finished(
            MealAdjustmentOutcome(
                reply: intent.reply,
                meal: MealAdjuster.applyAgainstBundledTable(intent, to: meal)
            )
        )
    }
}
