import Foundation

// MARK: - Contract

/// The second JSON shape both providers are asked for: not "what is this
/// meal" but "what is this person saying about a meal that is already
/// recorded" — which is sometimes a correction to an amount, sometimes a
/// question about the food, and often both in one sentence.
///
/// **A sibling of `EstimateContract`, not a variant of it.** The two ask
/// different questions and neither answer fits the other's shape — an estimate
/// prices a meal from nothing, and this moves the amounts of a meal that is
/// already priced. What they share is everything underneath: the same clients,
/// the same transport, the same key source, the same status mapping, the same
/// lenient number reading and the same rule that the parser assumes nothing
/// the prompt asked for was honoured.
///
/// **A reply that arrived as plain prose is an answer and not a failure**, and
/// that is the one place this parser is more forgiving than its sibling. An
/// estimate written as a paragraph is unusable: there is no total in it to put
/// in a ring. A conversation written as a paragraph is the thing itself — the
/// user asked something and the model answered — so it is read as a sentence
/// with no changes under it rather than thrown away. See `intent(from:)` for
/// the exact rule and for what still fails.
///
/// **The model is never asked for a figure, and there is no field it could put
/// one in.** The reply carries names and weights. Every kilocalorie and every
/// gram of protein, carbohydrate and fat that reaches the screen after an
/// adjustment is worked out on the device, by `MealAdjuster`, from a CIQUAL
/// row and a weight. That is the whole architecture of this app said once
/// more: the model names food and says how much, and the table prices it. A
/// chat that answered `"kilocalories": 620` and was believed would quietly
/// undo it, so the shape below has no key for one and the decoder has no
/// property for one.
nonisolated enum MealChatContract {

    // MARK: - Instructions

    /// The system prompt both clients send.
    ///
    /// English only, like everything else here. The user's message may be in
    /// any language; the field names are not.
    ///
    /// The paragraphs after the shape are each answering something a model
    /// does by default and must not do here — see the individual notes on
    /// `MealAdjuster`, which is the half of the rule the device enforces
    /// whatever the model writes. **Nothing in this prompt is relied on.**
    ///
    /// **It opens by naming a conversation, and the first line is the part that
    /// was wrong.** It used to cast the model as something that adjusts
    /// recorded amounts, full stop. A person who asks what is in their food, or
    /// whether that is much, has said nothing that role has a shape for, so the
    /// model would step out of the shape to answer them — and the answer was
    /// then thrown away by a parse that wanted an object. Both halves of that
    /// are fixed, and this is the half that stops it happening: a question is
    /// named as one of the two things a message can be, and `reply` is where it
    /// is answered.
    ///
    /// **A proportion is named as an amount, because it is the commonest way
    /// one is given.** "A second portion that was smaller" implies a weight
    /// against the one already recorded, and the last paragraph used to tell
    /// the model to decline exactly that and ask what it should have worked
    /// out. Asking back is still right where a message points at nothing —
    /// which is why the paragraph is still there, narrowed to that case.
    ///
    /// **What the model may not write is a figure, and that has if anything
    /// grown teeth**: now that a reply which never opened an object is drawn as
    /// prose, a kilocalorie count written into a sentence would be a number on
    /// the screen beside the one the table produced. It is still worked out
    /// here from CIQUAL and a weight, still read from nowhere else, and the
    /// prompt now says why in the terms the user would see.
    ///
    /// **The field order is asked for, and the request that it be asked for is
    /// the screen's.** The reply is read as it arrives, and the two arrays are
    /// what say whether this turn is moving anything: an empty `changes` and an
    /// empty `additions` are a question being answered, and either one with an
    /// object in it is an adjustment. Written first, that answer is known
    /// within a few tokens and the analysis states can be shown for exactly the
    /// turns that earn them. Written last, it is known only once the whole
    /// reply is in, by which time there is nothing left to wait for.
    ///
    /// The order is not relied on either. `MealChatStreamReader` reads whatever
    /// order the object turns out to be in and simply learns the answer later
    /// if the arrays come last, and the completed object is parsed by the same
    /// decoder as before, which has never cared about order at all. What a
    /// model that ignores this paragraph costs is a question that briefly shows
    /// the analysis states — never a wrong weight.
    static let systemPrompt = """
        You are talking with someone about a meal they have already logged.

        You are given the meal as it now stands: its items, numbered, each \
        with the weight recorded for it. Their message is a question about \
        that meal, or something about how it differed from what is recorded, \
        or both in one sentence. Answer what they asked, and work out which \
        items their message changes and what each of them now weighs.

        Reply with one JSON object and nothing else. No prose before it, no \
        prose after it, no code fence.

        {
          "changes": [
            { "item": integer, the item's number, "grams": integer, what that \
        item now weighs }
          ],
          "additions": [
            { "name": string, an ordinary food name, "grams": integer }
          ],
          "reply": string, one or two short sentences — your answer to what \
        they said, and what you changed if you changed anything
        }

        Write the three fields in that order: the amounts first and the \
        sentence last, so the sentence describes amounts you have already \
        settled on.

        Both lists empty is an ordinary answer and not a failed one. A message \
        that only asks something — what a food is, how it is usually made, \
        whether something is much — moves no amount: answer it in "reply" and \
        leave both lists empty.

        Never write a figure for calories, energy, protein, carbohydrate or \
        fat, in any field or in any sentence. They are worked out here from a \
        food composition table and the weights you give, so a number you wrote \
        would sit on the screen beside a different one. Answer a question \
        about them in words instead.

        Leave every item the message is not about out of "changes" entirely. \
        An item you do not mention keeps the figures it already has.

        A second helping is one larger amount of the same item, not a second \
        item. Raise that item's weight; do not repeat the row.

        An amount given as a proportion is still an amount, and is the \
        commonest way one is given. "Half of it", "twice as much rice", "a \
        second portion that was smaller" — work the new weight out from the \
        weight recorded for that item, put it in "changes", and say in "reply" \
        what you took it to mean. An estimate you have stated is worth more \
        than a question back.

        Use "additions" for food the message names or implies that is not \
        already in the list — the oil something was fried in, a sauce, a \
        drink. Saying how a dish was made names the food it was made with: \
        "the carrots were done in olive oil" adds olive oil. Give it an \
        ordinary food name, with no amount in the name, and a weight in grams \
        estimated from the size of the dish, and say in "reply" what you \
        assumed.

        Never write a weight of zero or below. If the person says they did \
        not eat something at all, say so in "reply" and leave the list alone; \
        taking a row out is theirs to do.

        Ask back only when the message points at no amount you could put a \
        number on and asks nothing you could answer. Then leave both lists \
        empty and use "reply" to say what you would need to know.
        """

    /// The meal, and the user's message, as one user turn.
    ///
    /// **The current state of the meal rides with the current question, not
    /// with the first one.** A conversation changes the thing it is about —
    /// that is what it is for — so a meal block sent once at the top of the
    /// exchange would describe a plate that no longer exists by the third
    /// message. The turns before this one carry only what was said; this one
    /// carries what the meal is now.
    ///
    /// **The message is placed last and labelled, so a user who types
    /// something that reads like an instruction is described rather than
    /// obeyed** — the same precaution and the same ordering as
    /// `EstimateContract.textInstruction(for:)`. Everything Fuel has to say is
    /// said before the user's own words begin.
    ///
    /// The item names are model-written text or the user's own corrections,
    /// and go over as they are: they are what the rows say, and a model asked
    /// about the second item has to be able to read the second item.
    ///
    /// **The photograph does not go.** It has already been read, it is not
    /// what is being asked about, and re-sending it would charge the user
    /// image tokens on every message to answer a question about arithmetic.
    /// Neither does the kilocalorie figure beside each row: handing a model
    /// its own last answer invites it to agree with itself, which is the
    /// reason `MealResultDraft.itemSentence` withholds the same numbers.
    static func turn(for meal: AdjustableMeal, message: String) -> String {
        var lines = ["The meal as it now stands: \(meal.title)"]

        if meal.items.isEmpty {
            lines.append(noItemsLine)
        } else {
            for (index, item) in meal.items.enumerated() {
                lines.append("\(index + 1). \(item.name) — \(amountLine(for: item))")
            }
        }

        lines.append("")
        lines.append("Message: \(message)")
        return lines.joined(separator: "\n")
    }

    /// What a row says about its own weight, including when it has nothing to
    /// say.
    ///
    /// A row with no weight is common and is not an error: a meal typed as a
    /// sentence with no amounts in it, a meal repeated from the Recent list,
    /// a row logged before Fuel stored weights at all. Saying so plainly lets
    /// the model put a first number on it; inventing a weight to fill the line
    /// would be Fuel guessing at the thing it is asking about.
    private static func amountLine(for item: RecognisedItem) -> String {
        guard let grams = item.weightInGrams, grams > 0 else {
            return "amount not recorded"
        }
        return "\(grams) g"
    }

    private static let noItemsLine = "This meal has no itemised breakdown."

    // MARK: - Bounds

    /// The request ceiling, shared with `EstimateContract` rather than chosen
    /// again.
    ///
    /// The reasoning there applies unchanged and is worth reading before
    /// touching this: both providers bill generated tokens rather than the
    /// ceiling, so a ceiling a well-formed reply never reaches is free, and
    /// the one outcome that costs twice is a reply cut off mid-object. This
    /// contract's replies are much smaller than an estimate's — a sentence and
    /// a handful of two-field objects — so the shared number is generous here,
    /// which is the direction to be generous in.
    static let maxTokens = EstimateContract.maxTokens

    /// The longest a message the user can send.
    ///
    /// **Not a design value and not in the export**, which draws no chat at
    /// all. It is here because every character typed into this field is a
    /// token the user pays for on this request and on every later one in the
    /// same conversation, and a field with no bound is a paste of arbitrary
    /// size on a bring-your-own-key product. 500 characters is far past
    /// anything anyone says about a plate of food.
    ///
    /// The field refuses input past this rather than trimming what was typed:
    /// silently sending less than the user wrote, and then answering the part
    /// that fit, is the worse failure of the two.
    static let maximumMessageLength = 500

    /// The longest the model's own sentence may be by the time it leaves this
    /// file.
    ///
    /// **Dropped rather than truncated**, and for the same reason a sentence
    /// is different from a name: a name cut short is still a name, and a
    /// sentence cut short stops mid-word with nothing under it to make sense
    /// of it. A model that ignored "one or two short sentences" has not
    /// answered this field, and the honest drawing of an unanswered field is
    /// no line at all. Nothing else is lost — the changes are parsed
    /// independently of it.
    static let maximumReplyLength = 240

    /// The longest an answer that arrived as prose may be.
    ///
    /// **The same rule as `maximumReplyLength` and deliberately not the same
    /// number**, because the two strings are not carrying the same weight. A
    /// `reply` sits beside changes that were parsed independently of it, so
    /// dropping one overlong sentence costs the sentence and leaves the answer
    /// standing. Prose *is* the answer: there is no object behind it, and
    /// dropping it costs the user the request. Holding it to a bound written
    /// for a caption beside a row would put one of Fuel's own fixed sentences
    /// over a paragraph that answered the question perfectly well.
    ///
    /// A thousand characters is a long paragraph and nothing like a page. It is
    /// generous on purpose — the cap exists to have *a* bound on a string the
    /// provider fully controls, not to make the model brief — and it is cheap
    /// to be generous with: the transcript scrolls, holds this only for as long
    /// as the screen is open, and is written to no store and no log.
    ///
    /// **Dropped rather than truncated**, exactly as the sentence is, and for
    /// the reason given there: a paragraph cut short stops mid-word with
    /// nothing under it to make sense of it.
    static let maximumProseLength = 1000

    /// How many past exchanges travel with a request.
    ///
    /// **A conversation re-sends everything said so far on every turn**, so
    /// an uncapped history costs the user a bill that grows with the square of
    /// how much they have typed. Eight exchanges is more than any conversation
    /// about how much rice was on a plate needs, and a ninth that had to
    /// remember the first would be a conversation that has already gone wrong.
    ///
    /// The oldest turns are dropped rather than the newest: what was said last
    /// is what the current message is a follow-up to.
    static let maximumHistoryExchanges = 8

    /// Reads the model's sentence, or `nil` where there is nothing to draw.
    ///
    /// Whitespace is collapsed as well as trimmed, so a model that answered in
    /// two paragraphs cannot decide the height of a block on the screen.
    ///
    /// **It is model-authored text and nothing else ever reaches it.** It is
    /// read from the `reply` key of the adjustment object and from no other
    /// source: no status, no error body, no provider message. Every failure
    /// path in this file throws before an adjustment exists. The one other
    /// string that reaches the transcript is `boundedProse(_:)`'s, which is the
    /// model's own words as well and arrives under the same rule.
    static func boundedReply(_ raw: String?) -> String? {
        bounded(raw, to: maximumReplyLength)
    }

    /// Reads an answer that arrived as prose, or `nil` where there is nothing
    /// to draw.
    ///
    /// The same collapsing and the same drop as `boundedReply(_:)` — one run of
    /// words, and no answer at all past the bound rather than half of one — at
    /// `maximumProseLength`, which says why the two numbers differ.
    ///
    /// **It is model-authored text and it stays text.** Nothing is read out of
    /// it, matched in it, or converted from it: the one thing this function
    /// does is decide whether a string is fit to be drawn.
    static func boundedProse(_ raw: String?) -> String? {
        bounded(raw, to: maximumProseLength)
    }

    /// Trimmed to one run of words, and dropped rather than cut at `limit`.
    private static func bounded(_ raw: String?, to limit: Int) -> String? {
        guard let raw else {
            return nil
        }
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= limit else {
            return nil
        }
        return collapsed
    }

    // MARK: - Parsing

    /// Reads the model's reply into the changes it is asking for, or into the
    /// sentence it answered with.
    ///
    /// Defensive in the same two directions `EstimateContract.estimate(from:
    /// mode:)` is: prose or a code fence around the object is tolerated, and
    /// nothing inside it is repaired blindly.
    ///
    /// **Nothing here is fatal except a reply with no readable content in it
    /// at all.** An estimate throws on a missing total because a zeroed meal
    /// would look like a real one in the day's ring; this has no such field. A
    /// reply with no `reply` and no changes is a legitimate answer — the model
    /// could not map the message onto an amount — and it is `MealAdjuster`, not
    /// this, that decides an empty answer changes nothing.
    ///
    /// **A reply that never opened an object is read as what it plainly is: a
    /// sentence.** This sheet is a conversation, and a conversation's answer to
    /// "what is polenta" is prose. Throwing it away cost the user a request they
    /// had already paid for and put "unreadable response" on the screen over an
    /// answer that was sitting right there, which is how this parse spent most
    /// of its failures.
    ///
    /// Two things keep that from becoming a hole in the architecture, and both
    /// are structural rather than intended:
    ///
    /// - **Prose produces a `reply` and nothing else.** The value returned
    ///   below carries the default empty `changes` and `additions`; there is no
    ///   branch here that reads a number out of a sentence, and
    ///   `MealAdjustmentIntent` has no field a figure could reach even if one
    ///   were read. A model that writes "that is about 620 kcal" in prose has
    ///   written a string that is drawn and nothing more.
    /// - **A half-written object is not prose.** `readsAsProse(_:)` refuses
    ///   anything with a brace or a fence in it, so a reply cut off inside its
    ///   own JSON still fails here rather than being shown to the user as a
    ///   sentence of punctuation. That case is the one `AIError.truncatedReply`
    ///   exists for.
    ///
    /// Throws `AIError.malformedResponse`. Never crashes, including on a
    /// number too large to be an `Int`.
    static func intent(from reply: String) throws -> MealAdjustmentIntent {
        if
            let object = EstimateContract.firstJSONObject(in: reply),
            let payload = try? JSONDecoder().decode(AdjustmentPayload.self, from: Data(object.utf8))
        {
            return MealAdjustmentIntent(
                reply: boundedReply(payload.reply),
                // A row that cannot be read is dropped rather than taking the
                // whole answer with it — the same rule an estimate's breakdown
                // follows, and for the same reason: the other rows are still a
                // usable answer to what was asked.
                changes: payload.changes.compactMap(\.change),
                additions: payload.additions.compactMap(\.addition)
            )
        }

        guard readsAsProse(reply), let sentence = boundedProse(reply) else {
            throw AIError.malformedResponse
        }
        return MealAdjustmentIntent(reply: sentence)
    }

    /// Whether `reply` is prose rather than an object that has not finished
    /// arriving.
    ///
    /// **A brace or a backtick anywhere is enough to say it is not.** Both are
    /// a model answering in the shape it was asked for, however far it got: the
    /// object itself, or the fence it was about to wrap around one. Neither is
    /// a character that turns up in a sentence about food, so the test can be
    /// this blunt and still never mistake an answer for a fragment. The
    /// backtick is checked singly rather than as a whole fence because a stream
    /// stops wherever it stops, and one backtick already says what is coming.
    ///
    /// Deliberately not "does this parse": a *complete* object is found by
    /// `EstimateContract.firstJSONObject(in:)` and read as one long before this
    /// is asked. What this answers is what to do with everything else.
    static func readsAsProse(_ reply: String) -> Bool {
        !reply.contains("{") && !reply.contains("`")
    }

    /// Whether `reply` holds a finished object at all.
    ///
    /// Visible past this file because a streamed turn has to ask it about a
    /// reply nothing has parsed yet: a model stopped at the request's token
    /// ceiling either finished its object and was cut off after it, or was cut
    /// off inside its answer, and this is what tells those two apart. See
    /// `MealChatStreamAssembler.finish(over:)`.
    static func carriesAnObject(_ reply: String) -> Bool {
        EstimateContract.firstJSONObject(in: reply) != nil
    }
}

// MARK: - Payload

/// The wire shape, decoded leniently.
///
/// Every field is optional and every number goes through `LenientInt`, so a
/// reply missing a key still decodes far enough to be read. A strict
/// `Decodable` would throw inside the decoder, where there is no room to
/// decide what is fatal.
private nonisolated struct AdjustmentPayload: Decodable {

    var reply: String?
    var changes: [ChangePayload]
    var additions: [AdditionPayload]

    private enum CodingKeys: String, CodingKey {
        case reply
        case changes
        case additions
    }

    /// Written out rather than synthesised because the synthesised
    /// `decodeIfPresent(String.self, …)` throws on a type mismatch, and an
    /// answer whose `reply` came back as a number would cost the user the
    /// changes underneath it.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try? container.decode(String.self, forKey: .reply)
        changes = (try? container.decode([ChangePayload].self, forKey: .changes)) ?? []
        additions = (try? container.decode([AdditionPayload].self, forKey: .additions)) ?? []
    }

    // MARK: - A changed row

    nonisolated struct ChangePayload: Decodable {

        var item: LenientInt?
        var grams: LenientInt?

        /// The change this row asks for, or `nil` where it asks for nothing
        /// usable.
        ///
        /// Both fields are required, and the number is required to be a real
        /// amount. Zero and below is refused here as well as in the prompt:
        /// it is not a smaller portion, it is the absence of one, and a meal
        /// with a row silently emptied to nothing is a meal the user did not
        /// edit.
        ///
        /// The index is left exactly as the model wrote it, one-based. It is
        /// checked against the actual list by `MealAdjuster`, which is the
        /// only thing that knows how long that list is.
        var change: MealAdjustmentIntent.Change? {
            guard let item = item?.value, let grams = grams?.value, grams > 0 else {
                return nil
            }
            return MealAdjustmentIntent.Change(itemNumber: item, grams: grams)
        }
    }

    // MARK: - An added row

    nonisolated struct AdditionPayload: Decodable {

        var name: String?
        var grams: LenientInt?

        private enum CodingKeys: String, CodingKey {
            case name
            case grams
        }

        /// Written out for the reason `AdjustmentPayload`'s is: a name that
        /// arrived as something other than a string must cost this row and not
        /// the whole list.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try? container.decode(String.self, forKey: .name)
            grams = try? container.decode(LenientInt.self, forKey: .grams)
        }

        /// The row this asks to add, or `nil` where there is not enough of one.
        ///
        /// The name goes through `EstimateContract.boundedName` rather than a
        /// second bound of its own: it becomes a `RecognisedItem.name` like
        /// any other, is written to SwiftData like any other, and is drawn in
        /// the same row as the ones a scan produced. One rule for one string.
        var addition: MealAdjustmentIntent.Addition? {
            guard
                let name = EstimateContract.boundedName(name),
                let grams = grams?.value,
                grams > 0
            else {
                return nil
            }
            return MealAdjustmentIntent.Addition(name: name, grams: grams)
        }
    }
}
