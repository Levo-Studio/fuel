import SwiftUI

// MARK: - Meal chat

/// The conversation about one logged meal.
///
/// **Not in the export, at any level.** There is no chat in `design/` — no
/// sheet, no transcript, no field — so nothing here is a deviation from a
/// frame that exists, and everything here is a recomposition of values that
/// do. The owner asked for it and for the shape it comes up in.
///
/// **The presentation is the platform's own**, which is the honest way to
/// build something the export has no drawing for: a `.sheet` at the `.large`
/// detent, with the system's own grabber and its own swipe-to-dismiss. Nothing
/// about the rise, the corner radius, the dimming behind it or the drag is
/// Fuel's invention.
///
/// What is drawn inside it comes from the screens this sheet sits on top of:
///
/// - The title and the line under it are screen 07's camera-sheet pair —
///   `sheetTitle` over `hintWrapping` in `muted` — and the trailing `Done` is
///   the result header's own `eyebrow` in `muted`.
/// - A turn the user wrote is `MealQuoteLede`, unchanged: the app already has
///   exactly one drawing for the user's own words about a meal, screen 15's
///   accent rule, and this is the same sentence in the same role.
/// - A reply is `body` in `ink`, the type screen 12 gives prose that wraps.
/// - A changed row is the breakdown row from screens 14 and 15 — `itemTitle`
///   and `listValueSmall`, the same `s13` padding and the same `hairSoft`
///   rule.
/// - The field is `discardControl`'s pill recipe: `surface` inside a
///   `Radius.pill` hairline. The send mark is `deleteCorner`'s circle at
///   `Control.circleButton`, filled with the accent the footer's own primary
///   button uses.
///
/// The analysis states run in here rather than over the screen behind, because
/// this is the surface the user is looking at and `CANCEL` has to be on it.
struct MealChatSheet: View {

    let model: MealChatModel

    /// The meal's own name, for the header, so the sheet says which meal is
    /// being talked about without repeating the breakdown underneath it.
    let mealTitle: String

    let onClose: () -> Void

    @Environment(\.fuelPalette) private var palette

    @FocusState private var isWriting: Bool

    /// How far the field grows before it scrolls inside itself.
    ///
    /// **Not a drawn value** — the export has no chat — and not a metric
    /// either: it is a count of lines rather than a measurement, and what it
    /// becomes in points is `FuelTypography.body`'s to say. Four is what the
    /// field has always allowed; it is roughly what fits above a keyboard
    /// without the transcript disappearing behind the composer.
    private static let fieldLines = 4

    var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: .zero) {
                header
                transcript
                composer
            }

            switch model.stage {
            case .analysing(let step):
                // `.text` rather than `.photo`: this asks about amounts, and
                // there is no frame to freeze behind a question about
                // arithmetic — the same reading the text log mode gives it.
                AnalysisView(step: step, backdrop: .text, onCancel: model.cancel)
            case .failed(let failure):
                AnalysisFailureView(
                    failure: failure,
                    backdrop: .text,
                    onRetry: model.retry,
                    onDismiss: model.dismissFailure
                )
            case .conversation:
                EmptyView()
            }
        }
        .fuelAnimation(FuelMotion.emphasised, value: model.stage)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: FuelMetrics.Space.s8) {
            HStack(alignment: .firstTextBaseline, spacing: FuelMetrics.Space.s14) {
                Text(MealChatCopy.title)
                    .fuelStyle(FuelTypography.sheetTitle)
                    .foregroundStyle(palette.ink)

                Spacer(minLength: FuelMetrics.Space.s14)

                Button(action: onClose) {
                    Text(MealChatCopy.close)
                        .fuelStyle(FuelTypography.eyebrow)
                        .foregroundStyle(palette.muted)
                        .frame(minHeight: FuelMetrics.Control.minimumHitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            // The meal's own name, drawn as the day list draws it, so the
            // sheet says what it is about without a second copy of the
            // breakdown. Model-written text, rendered verbatim.
            Text(verbatim: mealTitle)
                .fuelStyle(FuelTypography.entryTitle)
                .foregroundStyle(palette.ink)

            Text(MealChatCopy.hint)
                .fuelStyle(FuelTypography.hintWrapping)
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FuelMetrics.Space.s22)
        .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
        .padding(.bottom, FuelMetrics.Space.s18)
    }

    // MARK: - Transcript

    /// The exchange so far, oldest first, scrolled to the newest.
    ///
    /// `defaultScrollAnchor(.bottom)` rather than a `ScrollViewReader` and a
    /// scroll on every append: the interesting end of a conversation is always
    /// the bottom, and the platform already knows how to keep a scroll view
    /// there while its content grows.
    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FuelMetrics.Space.s24) {
                if model.messages.isEmpty {
                    Text(MealChatCopy.empty)
                        .fuelStyle(FuelTypography.body)
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(model.messages) { message in
                    turn(message)
                }

                if let arriving = model.arrivingReply {
                    ArrivingTurn(sentence: arriving)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
            .padding(.bottom, FuelMetrics.Space.s24)
        }
        .fuelScrolling()
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: .infinity)
        .fuelAnimation(FuelMotion.standard, value: model.messages)
        // Not animated on `arrivingReply`: a curve on every word would be a
        // hundred overlapping animations on one paragraph, and the reveal is
        // the text arriving rather than anything moving. What is animated is
        // the row appearing and going away, which `messages` and the row's own
        // insertion already cover.
    }

    @ViewBuilder
    private func turn(_ message: MealChatMessage) -> some View {
        switch message.author {
        case .you:
            // The app's one drawing for the user's own words about a meal,
            // reused rather than redrawn — screen 15's accent rule.
            MealQuoteLede(text: message.text)

        case .fuel:
            VStack(alignment: .leading, spacing: .zero) {
                // Model-written text, already bounded at the parse boundary,
                // or one of two fixed sentences of Fuel's own. Plain `Text`,
                // so there is no markup path into the interface for anything a
                // provider wrote.
                Text(verbatim: message.text)
                    .fuelStyle(FuelTypography.body)
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if message.movedNothing {
                    Text(MealChatCopy.nothingChanged)
                        .fuelStyle(FuelTypography.footnote)
                        .foregroundStyle(palette.muted)
                        .padding(.top, FuelMetrics.Space.s8)
                } else {
                    ForEach(message.changes) { change in
                        changeRow(change)
                    }
                    .padding(.top, FuelMetrics.Space.s8)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// One row the turn moved, in the breakdown row's own drawing.
    private func changeRow(_ change: MealChatMessage.Change) -> some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s14) {
            Text(verbatim: change.name)
                .fuelStyle(FuelTypography.itemTitle)
                .foregroundStyle(palette.ink)

            Spacer(minLength: FuelMetrics.Space.s14)

            Text(change.grams.map(MealChatCopy.grams) ?? MealChatCopy.noAmount)
                .fuelStyle(FuelTypography.listValueSmall)
                .foregroundStyle(palette.ink)
        }
        .padding(.vertical, FuelMetrics.Space.s13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            palette.hairSoft
                .frame(height: FuelMetrics.Line.hairline)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: FuelMetrics.Space.s10) {
            field
            sendControl
        }
        .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
        .padding(.top, FuelMetrics.Space.s14)
        .padding(.bottom, FuelMetrics.Space.s20)
        .overlay(alignment: .top) {
            palette.hair
                .frame(height: FuelMetrics.Line.hairline)
        }
    }

    /// `axis: .vertical` so a long sentence wraps inside the pill rather than
    /// scrolling sideways under the send mark. The height cap keeps it from
    /// growing over the transcript; the bound on what can be typed at all is
    /// `MealChatModel.message`'s own, and it is a bound on the user's own
    /// bill rather than on the layout.
    ///
    /// **A height in points rather than `lineLimit(1...4)`, because that
    /// bounded the box and not the text.** SwiftUI sizes a line-limited field
    /// by the font's line height alone, and `body` carries a 1.5 line-height
    /// multiple that the layout then adds back between the lines — so the field
    /// asked for four lines, was given a box the size of four line *boxes*, and
    /// drew a fourth line eleven points past the bottom of it. Measured at
    /// 390×844: 75.7 points where four lines of `body` need 86.3, and the last
    /// line cut through the middle of its letters. One line, two and three were
    /// all correct, which is why it only showed on a full field.
    ///
    /// `FuelTypography.Style.height(ofLines:)` answers with both numbers, so
    /// this stays right at every Dynamic Type size. Past the cap the field
    /// scrolls inside itself exactly as it did before.
    ///
    /// **`fixedSize` is load-bearing and not decoration.** A bare
    /// `frame(maxHeight:)` makes the field flexible up to that height, and the
    /// stack above it duly offers the whole of it — an empty field drew a pill
    /// four lines tall. Fixing the vertical size asks the field for its own
    /// height first and lets the frame clamp it, which is the "grows with what
    /// is typed, stops here" behaviour the cap is for.
    ///
    /// An empty label with a `prompt`, which is the shape screen 12's field
    /// already uses, so the placeholder is a prompt and the accessible name is
    /// stated rather than inferred from grey text.
    ///
    /// **Nothing is remembered anywhere.** The message lives on the model for
    /// as long as the screen is open and is gone with it — the same posture
    /// the text log mode's field takes, and the reason neither offers a
    /// content type.
    ///
    /// No `minimumHitTarget` floor: `body` inside `s13` above and below is
    /// already past a fingertip on one line, and a floor on top of the padding
    /// would make the pill taller than the export's own.
    private var field: some View {
        TextField("", text: Bindable(model).message, prompt: Text(MealChatCopy.placeholder), axis: .vertical)
        .focused($isWriting)
        .submitLabel(.send)
        .onSubmit(send)
        .textInputAutocapitalization(.sentences)
        .accessibilityLabel(Text(MealChatCopy.title))
        .fuelStyle(FuelTypography.body)
        .foregroundStyle(palette.ink)
        .tint(palette.accentColor)
        .frame(maxHeight: FuelTypography.body.height(ofLines: Self.fieldLines))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, FuelMetrics.Space.s13)
        .padding(.horizontal, FuelMetrics.Space.s16)
        .background {
            RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                .fill(palette.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
        }
    }

    /// The send mark: the footer button's accent fill in the corner control's
    /// circle.
    ///
    /// **Dimmed rather than hidden with an empty field**, and this is the one
    /// place this app draws a control that is present and inert. A send mark
    /// that disappeared as the field emptied would be a control moving under
    /// the thumb that is about to press it — worse than one that is visibly
    /// not ready, which is what an empty field already says. The opacity is
    /// `soft`'s own role, applied to the accent rather than invented as a
    /// number.
    ///
    /// **It becomes a stop mark while a reply is arriving**, in the same
    /// circle rather than beside it, for the same reason it is dimmed rather
    /// than hidden: a second control appearing next to the first would move
    /// under the thumb about to press it. A stop has to be somewhere now that a
    /// question is answered without the analysis states, which is where
    /// `CANCEL` used to be the only way out of a wait.
    private var sendControl: some View {
        Button {
            if model.isAnswering {
                stop()
            } else {
                send()
            }
        } label: {
            sendMark
        }
        .buttonStyle(FuelPressButtonStyle())
        .disabled(!isReady)
        .accessibilityLabel(Text(model.isAnswering ? MealChatCopy.stop : MealChatCopy.send))
        .fuelAnimation(FuelMotion.standard, value: appearance)
    }

    /// The circle, in a box exactly as tall as one line of the field.
    ///
    /// **That box is the alignment.** The two sit in an `HStack` aligned on
    /// `.bottom`, so what a bare 34-point circle lines up with is the bottom of
    /// the pill — and the pill's bottom is the field's own 13 points of padding
    /// below its last line. A circle taller than a line, hung from that edge,
    /// comes to rest with its centre four and a half points under the text it
    /// belongs to: at one line it reads as sagging inside the pill, and at two
    /// it is sixteen points below the pill's middle with nothing to explain
    /// why.
    ///
    /// Giving the circle the field's own line box and the field's own vertical
    /// padding puts its centre exactly on the last line's centre, at one line
    /// and at four. The height is measured off a hidden line of the same style
    /// rather than written down, so it stays right when the user has asked for
    /// larger text — a number here would be right at one Dynamic Type size and
    /// wrong at the rest.
    ///
    /// The hit region needs no vertical overhang any more: a line of `body`
    /// inside `s13` above and below is already past `minimumHitTarget` on its
    /// own. The horizontal overhang stays, so the region is a fingertip wide
    /// while the layout is only the circle wide and the field keeps the space.
    private var sendMark: some View {
        Text(verbatim: " ")
            .fuelStyle(FuelTypography.body)
            .frame(width: FuelMetrics.Control.circleButton)
            .padding(.vertical, FuelMetrics.Space.s13)
            .hidden()
            .overlay {
                Image(systemName: model.isAnswering ? "stop.fill" : "arrow.up")
                    .fuelStyle(FuelTypography.iconGlyph)
                    .foregroundStyle(palette.onAccent)
                    .frame(width: FuelMetrics.Control.circleButton, height: FuelMetrics.Control.circleButton)
                    .background {
                        Circle().fill(isReady ? AnyShapeStyle(palette.accentColor) : AnyShapeStyle(palette.soft))
                    }
            }
            .frame(width: FuelMetrics.Control.minimumHitTarget)
            .contentShape(.rect)
            .padding(.horizontal, -FuelMetrics.Control.hitTargetOverhang(around: FuelMetrics.Control.circleButton))
    }

    /// Whether the control has anything to do — send what has been typed, or
    /// stop what is on its way back.
    private var isReady: Bool {
        model.isAnswering || model.canSend
    }

    /// The two things about the control that change under one curve: the fill
    /// waking up as the field is typed into, and the mark swapping when a reply
    /// starts arriving.
    private var appearance: SendAppearance {
        SendAppearance(isReady: isReady, isAnswering: model.isAnswering)
    }

    private struct SendAppearance: Equatable {

        let isReady: Bool
        let isAnswering: Bool
    }

    private func send() {
        guard model.canSend else { return }
        FuelHaptics.play(.selectionChanged)
        model.send()
    }

    private func stop() {
        FuelHaptics.play(.selectionChanged)
        model.cancel()
    }
}

// MARK: - A reply on its way

/// The row a reply occupies while it is being written.
///
/// **A view of its own rather than a branch inside the transcript**, because
/// the Reduce Motion decision belongs to `FuelArrival` and a `@ViewBuilder`
/// method cannot hold one. It is the reply turn's own drawing — `body` in
/// `ink`, screen 12's type for prose that wraps — so the sentence does not
/// change weight or colour when the turn lands and the row becomes an ordinary
/// one.
///
/// The waiting line is drawn in `muted` and is Fuel's own words, not the
/// model's. It stands alone before the first token arrives, and stands for the
/// whole reply where the user has asked for less motion — see
/// `FuelMotion.resolveProgressiveReveal`.
private struct ArrivingTurn: View {

    /// As much of the model's sentence as has been written. Empty until the
    /// first word.
    let sentence: String

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        Group {
            if sentence.isEmpty {
                writing
            } else {
                FuelArrival {
                    // Model-written text, bounded at the parse boundary before
                    // it ever reaches here. Plain `Text`, so there is no markup
                    // path into the interface for anything a provider wrote.
                    Text(verbatim: sentence)
                        .fuelStyle(FuelTypography.body)
                        .foregroundStyle(palette.ink)
                } waiting: {
                    writing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var writing: some View {
        Text(MealChatCopy.writing)
            .fuelStyle(FuelTypography.body)
            .foregroundStyle(palette.muted)
    }
}

// MARK: - Previews

#Preview("Conversation") {
    MealChatSheet(model: MealChatPreviewData.model(), mealTitle: "Salmon with polenta", onClose: {})
        .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
}

#Preview("Conversation, light") {
    MealChatSheet(model: MealChatPreviewData.model(), mealTitle: "Salmon with polenta", onClose: {})
        .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .green))
}

#Preview("Nothing said yet") {
    MealChatSheet(model: MealChatPreviewData.empty(), mealTitle: "Salmon with polenta", onClose: {})
        .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
}

#Preview("A reply arriving") {
    MealChatSheet(model: MealChatPreviewData.arriving(), mealTitle: "Salmon with polenta", onClose: {})
        .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
}

// MARK: - Preview data

/// An exchange that has already happened, so the canvas shows the three things
/// a turn can be: the user's own words, a reply that moved something, and a
/// reply that moved nothing.
private enum MealChatPreviewData {

    static func model() -> MealChatModel {
        MealChatModel(
            subject: PreviewSubject(),
            client: PreviewAdjuster(),
            keys: PreviewKeys(),
            messages: [
                MealChatMessage(author: .you, text: "It was quite oily"),
                MealChatMessage(author: .fuel, text: "Roughly how much oil?"),
                MealChatMessage(author: .you, text: "About a tablespoon, and I had a second, smaller portion"),
                MealChatMessage(
                    author: .fuel,
                    text: "Added a tablespoon of olive oil and raised the rice by half a portion.",
                    changes: [
                        MealChatMessage.Change(name: "Rice", grams: 225),
                        MealChatMessage.Change(name: "Olive oil", grams: 14),
                    ]
                ),
                MealChatMessage(author: .you, text: "It was a bit spicy too"),
                MealChatMessage(author: .fuel, text: "Spice does not change the amounts on its own."),
            ]
        )
    }

    static func empty() -> MealChatModel {
        MealChatModel(subject: PreviewSubject(), client: PreviewAdjuster(), keys: PreviewKeys())
    }

    /// A question caught half-answered, which is the state that used to be four
    /// analysis steps over the whole sheet.
    static func arriving() -> MealChatModel {
        MealChatModel(
            subject: PreviewSubject(),
            client: PreviewAdjuster(),
            keys: PreviewKeys(),
            messages: [MealChatMessage(author: .you, text: "Is that a lot of protein?")],
            arriving: "Around a third of a typical day's protein, and most of it is"
        )
    }
}

/// A meal that answers without a store, which a canvas has none of.
@MainActor
private final class PreviewSubject: MealChatSubject {

    var adjustableMeal: AdjustableMeal {
        AdjustableMeal(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
            items: [
                RecognisedItem(
                    name: "Rice",
                    kilocalories: 232,
                    grams: 150,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                )
            ]
        )
    }

    func apply(_ adjusted: AdjustedMeal) -> Bool { true }
}

/// Answers the key question without a Keychain, which a preview process has no
/// access group for.
private struct PreviewKeys: MealKeyPresence {

    func hasKey(for provider: AIProvider) -> Bool { true }
}

/// A client that makes no request. A preview that reached a provider would
/// spend the developer's credit every time the canvas refreshed.
private struct PreviewAdjuster: AIClient {

    let provider: AIProvider = .claude

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .passed }

    func estimate(photo: MealPhoto, context: String?) async throws -> MealEstimate { throw AIError.cancelled }

    func estimate(text: String) async throws -> MealEstimate { throw AIError.cancelled }

    func adjust(
        _ meal: AdjustableMeal,
        history: [MealChatTurn],
        message: String
    ) -> AsyncThrowingStream<MealChatEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: AIError.cancelled) }
    }
}
