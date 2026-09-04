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

    /// Whether the field is holding the keyboard.
    ///
    /// Bound rather than held here: the field outlives its own screen — the
    /// scaffold stays in the hierarchy under the analysis and result overlays
    /// — so whoever knows the stage has to be able to let it go. See
    /// `LogFlowChrome.canHoldTextFocus`.
    @FocusState.Binding var isWriting: Bool

    let onAnalyse: () -> Void

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
    /// example was asked for by the owner and is therefore composed out of the
    /// export's own vocabulary rather than invented — see `MealTextField.prompt`
    /// for which drawn element each part of it comes from. The heading above the
    /// field remains what names it, which is why VoiceOver is handed that same
    /// key rather than a second wording invented for it.
    ///
    /// It grows downward as the sentence wraps, which is the only reading of a
    /// screen that draws prose at `19px/1.5` and gives it no box. **The example
    /// does not**: a prompt is one line and truncates, so an example that
    /// outran the line would lose the export's trailing ellipsis to a system
    /// one. Their widths are held to the design layer's own scaling cap in
    /// `TextPlaceholderTests`.
    private var field: some View {
        MealTextField(
            text: $typedText,
            examples: TextLogCopy.placeholderExamples,
            line: TextLogCopy.placeholderLine,
            accessibilityLabel: TextLogCopy.title,
            isWriting: $isWriting
        )
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
    @Previewable @FocusState var isWriting: Bool

    ZStack {
        FuelPalette(theme: .dark, accent: .mono).camera
            .ignoresSafeArea()

        TextTabView(
            typedText: $typedText,
            isEstimateAvailable: true,
            isWriting: $isWriting,
            onAnalyse: {}
        )
    }
}

#Preview("Text entry, written in") {
    @Previewable @State var typedText = "2 eggs with 200g cottage cheese and polenta"
    @Previewable @FocusState var isWriting: Bool

    ZStack {
        FuelPalette(theme: .dark, accent: .mono).camera
            .ignoresSafeArea()

        TextTabView(
            typedText: $typedText,
            isEstimateAvailable: true,
            isWriting: $isWriting,
            onAnalyse: {}
        )
    }
}

#Preview("Text entry without a key") {
    @Previewable @State var typedText = ""
    @Previewable @FocusState var isWriting: Bool

    ZStack {
        FuelPalette(theme: .light, accent: .mono).camera
            .ignoresSafeArea()

        TextTabView(
            typedText: $typedText,
            isEstimateAvailable: false,
            isWriting: $isWriting,
            onAnalyse: {}
        )
    }
}
