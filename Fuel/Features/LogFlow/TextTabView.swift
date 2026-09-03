import SwiftUI

// MARK: - Text tab

/// Screen 12: a heading, a line of help, the field the meal is described in,
/// and `Analyse` held at the foot.
///
/// Presentation only — it is handed a binding and hands back a tap, so it
/// renders without a store, a client or a Keychain. The chrome around it (the
/// cancel control and the three tabs) belongs to `LogFlowScaffold`; this is the
/// body between them.
struct TextTabView: View {

    @Binding var typedText: String

    /// `false` when no key is stored. The estimate is the only thing a key
    /// buys, so the field goes with it and the tab says why.
    let isEstimateAvailable: Bool

    let onAnalyse: () -> Void

    /// Which example the empty field is showing. View state, and it never
    /// reaches the model: an example is something to read, not something the
    /// user has said, so `Analyse` on a field showing one is still an empty
    /// sentence and is still refused.
    @State private var placeholder = TextEntryPlaceholder(examples: TextLogCopy.placeholderExamples)

    var body: some View {
        if isEstimateAvailable {
            VStack(alignment: .leading, spacing: .zero) {
                Text(TextLogCopy.title)
                    .fuelStyle(FuelTypography.sheetTitle)
                    .foregroundStyle(FuelPalette.Camera.ink)

                Text(TextLogCopy.hint)
                    .fuelStyle(FuelTypography.hintWrapping)
                    .foregroundStyle(FuelPalette.Camera.muted)
                    .padding(.top, FuelMetrics.Space.s8)

                field
                    .padding(.top, FuelMetrics.Space.s24)

                // `margin-top:auto` in the export: the button is held at the
                // foot of the body whatever the field's height is.
                Spacer(minLength: .zero)

                analyseButton
                    .padding(.bottom, FuelMetrics.Space.s18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, FuelMetrics.Space.s34)
            .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
        } else {
            keylessNotice
        }
    }

    // MARK: - Field

    /// The meal, in the user's own words — and, while there are none, an
    /// example of the kind of words that work.
    ///
    /// **The export draws no placeholder here.** What it draws is a filled
    /// field: a sentence at `#fafafa`, which is typed text. The rotating
    /// example below was asked for by the owner and is therefore composed out
    /// of the export's own vocabulary rather than invented — see `prompt` for
    /// which drawn element each part of it comes from. The heading above the
    /// field remains what names it, for VoiceOver as well.
    ///
    /// It grows downward as the sentence wraps, which is the only reading of a
    /// screen that draws prose at `19px/1.5` and gives it no box. **The example
    /// does not**: a prompt is one line and truncates, so an example that
    /// outran the line would lose the export's trailing ellipsis to a system
    /// one. Their widths are held to the design layer's own scaling cap in
    /// `TextPlaceholderTests`.
    ///
    /// Nothing is remembered anywhere: the text lives in the model for as long
    /// as the flow is open, and no autofill, no correction dictionary and no
    /// state restoration is offered a copy.
    private var field: some View {
        TextField("", text: $typedText, prompt: prompt, axis: .vertical)
            .fuelStyle(FuelTypography.textEntry)
            .foregroundStyle(FuelPalette.Camera.ink)
            // The caret, not a drawn value: the export renders no cursor. The
            // camera surface stays dark in both themes, so the theme's accent
            // is not guaranteed to be legible on it and the surface's own ink
            // is.
            .tint(FuelPalette.Camera.ink)
            .textInputAutocapitalization(.sentences)
            .accessibilityLabel(Text(TextLogCopy.title))
            // A floor on the tap target of an empty field, not a box around
            // it. The text stays on the line the export draws it on — the
            // spacer below absorbs the rest — so nothing drawn moves, and a
            // one-line field is no longer a 28pt target.
            //
            // `minimumHitTarget` rather than the identically valued `Space.s44`
            // on purpose: the ladder is what the export draws, and this is a
            // rule applied to something drawn. Sharing the name would let a
            // future change to an onboarding padding move a touch target.
            .frame(minHeight: FuelMetrics.Control.minimumHitTarget, alignment: .top)
            // The rotation stops the moment the field has something in it: the
            // example is gone, and a timer waking up to advance what nobody can
            // see is work done for nothing. Reduce Motion is the modifier's
            // business, not this call site's — under it the field shows the
            // first example and stands still.
            .fuelPacing(FuelMotion.placeholderExampleHold, isActive: typedText.isEmpty) {
                placeholder.advance()
            }
    }

    /// The example, or nothing once the user has typed.
    ///
    /// `prompt:` rather than a `Text` laid over the field, so the example sits
    /// exactly where the platform puts a placeholder and exactly where the
    /// user's own first line will land — the same way the onboarding key field
    /// draws its `sk-ant-…`. It also means the disappearance is not a rule this
    /// view has to keep: a prompt is drawn only while the field is empty.
    ///
    /// Two things keep it from reading as typed text, and neither is invented.
    /// The ink is `FuelPalette.Camera.inactive`, which the export draws on the
    /// tab labels that are not the selected one — the lowest step of the four
    /// on this surface, and the one that already means "a label, but not the
    /// one in play". Against `#fafafa` typed text at the same size, the
    /// difference is not subtle. And the line trails off in the ellipsis the
    /// export draws after each analysis step, so it reads as unfinished rather
    /// than as a sentence someone left in the field.
    private var prompt: Text? {
        guard let example = placeholder.example(whileTyped: typedText) else { return nil }
        return Text(TextLogCopy.placeholderLine(example))
            .foregroundStyle(FuelPalette.Camera.inactive)
    }

    // MARK: - Analyse

    /// Drawn the same whether or not the field has anything in it: the export
    /// gives it one state, and a dimmed second one would be a value the design
    /// does not carry. An empty sentence is refused by the model, the way the
    /// onboarding screen refuses an empty key.
    private var analyseButton: some View {
        Button(action: onAnalyse) {
            Text(TextLogCopy.analyse)
                .fuelStyle(FuelTypography.buttonLabel)
                .foregroundStyle(FuelPalette.Camera.onInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, FuelMetrics.Space.s17)
                .background(FuelPalette.Camera.ink, in: .rect(cornerRadius: FuelMetrics.Radius.pill))
                .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
        }
        .buttonStyle(.plain)
    }

    // MARK: - No key

    /// What the tab draws with no key stored.
    ///
    /// Not in the export, which draws no disabled state — so it is built the
    /// way screen 07's is, a title over a hint at the flow's own inset, and it
    /// says which log mode still works rather than only what does not.
    private var keylessNotice: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(TextLogCopy.noKeyTitle)
                .fuelStyle(FuelTypography.sheetTitle)
                .foregroundStyle(FuelPalette.Camera.ink)

            Text(TextLogCopy.noKeyHint)
                .fuelStyle(FuelTypography.hintWrapping)
                .foregroundStyle(FuelPalette.Camera.muted)
                .padding(.top, FuelMetrics.Space.s8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FuelMetrics.Space.s34)
        .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
    }
}

// MARK: - Previews

#Preview("Text entry") {
    @Previewable @State var typedText = ""

    ZStack {
        FuelPalette(theme: .dark, accent: .mono).camera
            .ignoresSafeArea()

        TextTabView(typedText: $typedText, isEstimateAvailable: true, onAnalyse: {})
    }
}

#Preview("Text entry, written in") {
    @Previewable @State var typedText = "2 eggs with 200g cottage cheese and polenta"

    ZStack {
        FuelPalette(theme: .dark, accent: .mono).camera
            .ignoresSafeArea()

        TextTabView(typedText: $typedText, isEstimateAvailable: true, onAnalyse: {})
    }
}

#Preview("Text entry without a key") {
    @Previewable @State var typedText = ""

    ZStack {
        FuelPalette(theme: .light, accent: .mono).camera
            .ignoresSafeArea()

        TextTabView(typedText: $typedText, isEstimateAvailable: false, onAnalyse: {})
    }
}
