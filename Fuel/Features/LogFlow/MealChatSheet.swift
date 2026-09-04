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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
            .padding(.bottom, FuelMetrics.Space.s24)
        }
        .fuelScrolling()
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: .infinity)
        .fuelAnimation(FuelMotion.standard, value: model.messages)
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
    /// scrolling sideways under the send mark. `lineLimit` keeps it from
    /// growing over the transcript; the bound on what can be typed at all is
    /// `MealChatModel.message`'s own, and it is a bound on the user's own
    /// bill rather than on the layout.
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
        .lineLimit(1...4)
        .focused($isWriting)
        .submitLabel(.send)
        .onSubmit(send)
        .textInputAutocapitalization(.sentences)
        .accessibilityLabel(Text(MealChatCopy.title))
        .fuelStyle(FuelTypography.body)
        .foregroundStyle(palette.ink)
        .tint(palette.accentColor)
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
    private var sendControl: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .fuelStyle(FuelTypography.iconGlyph)
                .foregroundStyle(palette.onAccent)
                .frame(width: FuelMetrics.Control.circleButton, height: FuelMetrics.Control.circleButton)
                .background {
                    Circle().fill(model.canSend ? AnyShapeStyle(palette.accentColor) : AnyShapeStyle(palette.soft))
                }
                .frame(width: FuelMetrics.Control.minimumHitTarget, height: FuelMetrics.Control.minimumHitTarget)
                .contentShape(Rectangle())
                .padding(-FuelMetrics.Control.hitTargetOverhang(around: FuelMetrics.Control.circleButton))
        }
        .buttonStyle(FuelPressButtonStyle())
        .disabled(!model.canSend)
        .accessibilityLabel(Text(MealChatCopy.send))
        .fuelAnimation(FuelMotion.standard, value: model.canSend)
    }

    private func send() {
        guard model.canSend else { return }
        FuelHaptics.play(.selectionChanged)
        model.send()
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
    ) async throws -> MealAdjustmentOutcome {
        throw AIError.cancelled
    }
}
