import SwiftUI

// MARK: - Meal field

/// The field a meal is written into, with the example that stands in it while
/// it is empty.
///
/// Everything below was screen 12's and is unchanged by being moved: the drawn
/// type, the caret's colour, the floor under an empty field's tap target, and
/// the rotation that advances the example. What it does *not* own is the words
/// — the examples, the way one of them is drawn, and what VoiceOver calls the
/// field are handed in, because copy belongs to the screen that prints it and
/// this is a control two screens draw.
///
/// Nothing is remembered anywhere: the text lives in the model for as long as
/// the flow is open, and no autofill, no correction dictionary and no state
/// restoration is offered a copy.
struct MealTextField: View {

    @Binding var text: String

    /// The examples the empty field rotates through, in the order they are
    /// shown.
    let examples: [String]

    /// How one of them is drawn — the trailing ellipsis, and whatever else the
    /// screen's own copy puts around it.
    let line: (String) -> String

    /// What VoiceOver calls the field. Screen 12 hands it the heading standing
    /// over it, because that heading is what names the field on screen.
    let accessibilityLabel: String

    /// Whether the field is holding the keyboard.
    ///
    /// Bound rather than held here: the field outlives its own screen — the
    /// scaffold stays in the hierarchy under the analysis and result overlays
    /// — so whoever knows the stage has to be able to let it go. See
    /// `LogFlowChrome.canHoldTextFocus`.
    @FocusState.Binding var isWriting: Bool

    /// Which example the empty field is showing. View state, and it never
    /// reaches the model: an example is something to read, not something the
    /// user has said, so a field showing one is still an empty field and is
    /// still treated as one.
    @State private var placeholder: TextEntryPlaceholder

    init(
        text: Binding<String>,
        examples: [String],
        line: @escaping (String) -> String,
        accessibilityLabel: String,
        isWriting: FocusState<Bool>.Binding
    ) {
        self._text = text
        self.examples = examples
        self.line = line
        self.accessibilityLabel = accessibilityLabel
        self._isWriting = isWriting
        self._placeholder = State(initialValue: TextEntryPlaceholder(examples: examples))
    }

    var body: some View {
        TextField("", text: $text, prompt: prompt, axis: .vertical)
            .fuelStyle(FuelTypography.textEntry)
            .foregroundStyle(FuelPalette.Camera.ink)
            .focused($isWriting)
            // The caret, not a drawn value: the export renders no cursor. The
            // camera surface stays dark in both themes, so the theme's accent
            // is not guaranteed to be legible on it and the surface's own ink
            // is.
            .tint(FuelPalette.Camera.ink)
            .textInputAutocapitalization(.sentences)
            .accessibilityLabel(Text(accessibilityLabel))
            // A floor on the tap target of an empty field, not a box around
            // it. The text stays on the line the export draws it on — what is
            // below absorbs the rest — so nothing drawn moves, and a one-line
            // field is no longer a 28pt target.
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
            .fuelPacing(FuelMotion.placeholderExampleHold, isActive: text.isEmpty) {
                placeholder.advance()
            }
    }

    // MARK: - The example

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
        guard let example = placeholder.example(whileTyped: text) else { return nil }
        return Text(line(example))
            .foregroundStyle(FuelPalette.Camera.inactive)
    }
}
