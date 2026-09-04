import SwiftUI

// MARK: - What a dialog says

/// The words on a dialog: the question, the line under it where there is one,
/// and the two answers.
///
/// A value rather than four parameters, because the same three or four strings
/// travel together to more than one caller and one of them — the discard
/// question — is deliberately shared word for word between two screens. A type
/// keeps that one value one value.
nonisolated struct FuelDialogCopy {

    /// The question itself.
    let title: String

    /// The line under it, where the question needs one. Screen 12 draws exactly
    /// this pair — a title with a hint under it — and every dialog that has
    /// nothing to add leaves it out rather than filling it.
    let hint: String?

    /// The answer that goes ahead: the destructive verb where the dialog stands
    /// in front of something destructive.
    let confirm: String

    /// The way out, which changes nothing.
    let cancel: String

    init(title: String, hint: String? = nil, confirm: String, cancel: String) {
        self.title = title
        self.hint = hint
        self.confirm = confirm
        self.cancel = cancel
    }
}

// MARK: - What a dialog collects

/// The field on a dialog that asks for a line of text rather than for a yes or
/// a no.
///
/// Optional at the call site rather than a second dialog type: a dialog with a
/// field is the same panel with one more thing in it, and two views would be
/// two places the title's drop and the button row could drift apart.
struct FuelDialogEntry {

    @Binding var text: String

    /// What stands in the empty field. `prompt:` rather than a `Text` laid over
    /// it, the way screen 12's field and the onboarding key field both draw
    /// theirs.
    let prompt: String

    /// What VoiceOver calls the field, since the question above it is a
    /// sentence rather than a label.
    let accessibilityLabel: String
}

// MARK: - The dialog

/// Fuel's own question, drawn in Fuel's own language.
///
/// **The export draws no dialog** — no modal, no card over content, no scrim,
/// no destructive colour. Anything here is therefore undrawn, and the whole of
/// this view is a recomposition of things the export does draw, on the
/// owner's instruction that a question the app asks should look like the app
/// asking it rather than like iOS asking on its behalf.
///
/// **The presentation is the platform's own, and that is the point of using a
/// sheet rather than inventing a panel.** A `.sheet` is the one surface this
/// app already comes up on with the owner's ruling behind it — `MealChatSheet`
/// — and it is the honest answer to everything the export does not draw: the
/// dimming behind it, the corner it rises with, the rise itself, the swipe
/// that puts it away, its behaviour under Reduce Motion and its behaviour with
/// a keyboard up are all the system's, and none of them is a value invented
/// here. What a system *alert* draws is its own panel, its own typeface and
/// its own verbs; what a sheet draws is a corner and a dim, and everything
/// inside is this file's.
///
/// What is inside comes from the screens the dialog stands over:
///
/// - The question and the line under it are screen 12's pair — `sheetTitle`
///   over `hintWrapping` in `muted`, at the `s8` the export draws between
///   them.
/// - The gap from the question to whatever answers it is screen 12's `s24`,
///   which is the distance that screen puts between its prompt and its field.
/// - The two answers are the footer pair screens 14 and 15 draw: an outlined
///   pill that hugs its label on the leading side, an accent-filled pill that
///   takes the rest on the trailing side, `s10` between them.
/// - The field is screen 12's own — `textEntry`, the type that screen sets a
///   written sentence in — over the hairline rule the onboarding key field
///   draws under itself, which is the export's only chrome on a field on a
///   themed surface.
///
/// **Every way out of this sheet except the confirm button is the safe
/// answer.** The swipe down, the tap outside, and the leading pill all cancel;
/// only the trailing pill goes ahead. That is what lets the platform's own
/// dismissal be left switched on for a question about deleting a meal — a
/// gesture made by accident, an app sent to the background, a device rotated,
/// all end with the meal still there.
///
/// **The destructive verb sits in the trailing pill, which is the corner no
/// control that raises this dialog occupies.** Both controls that can reach a
/// destructive question — the trash circle on a logged meal and the trash pill
/// on a scan result — are drawn in the *leading* corner of a footer, so a
/// second tap that arrives before the sheet is up lands on the answer that
/// changes nothing.
struct FuelDialog: View {

    let copy: FuelDialogCopy

    /// The field, where the dialog collects a line rather than a decision.
    let entry: FuelDialogEntry?

    let onConfirm: () -> Void

    let onCancel: () -> Void

    @Environment(\.fuelPalette) private var palette

    @FocusState private var isWriting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(copy.title)
                .fuelStyle(FuelTypography.sheetTitle)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let hint = copy.hint {
                Text(hint)
                    .fuelStyle(FuelTypography.hintWrapping)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, FuelMetrics.Space.s8)
            }

            if let entry {
                field(entry)
                    .padding(.top, FuelMetrics.Space.s24)
            }

            answers
                .padding(.top, FuelMetrics.Space.s24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FuelMetrics.Space.s22)
        .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
        .padding(.bottom, FuelMetrics.Space.s18)
        .background(palette.background)
    }

    // MARK: - The field

    /// Screen 12's field on a themed surface.
    ///
    /// The type, the caret and the single line it starts on are that screen's;
    /// what is new is where the ink comes from, because screen 12 draws its
    /// field on the camera surface and this one stands on the page. `ink` and
    /// `muted` are the theme's answers to the two colours that field uses, and
    /// the caret follows the accent the way the chat composer's does rather
    /// than the camera ink, which is a camera value.
    ///
    /// **The rule underneath is the onboarding key field's**, which is the only
    /// field the export draws on a themed screen and the only chrome it gives
    /// one: a `hair` hairline under the text, with the export's own `14` above
    /// it and `12` below.
    ///
    /// `axis: .vertical` so a long item wraps instead of scrolling sideways,
    /// and `submitLabel` is deliberately not set: the keyboard's return key on
    /// a vertical field arrives as an inserted line break rather than as a
    /// submit, which the chat composer had to work around at length. Here there
    /// is a button on screen with the word on it, so nothing has to be worked
    /// around — a return puts a line break in an item name and the user can see
    /// that it did.
    private func field(_ entry: FuelDialogEntry) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            TextField("", text: entry.$text, prompt: prompt(entry), axis: .vertical)
                .fuelStyle(FuelTypography.textEntry)
                .foregroundStyle(palette.ink)
                .tint(palette.accentColor)
                .focused($isWriting)
                .textInputAutocapitalization(.sentences)
                .accessibilityLabel(Text(entry.accessibilityLabel))
                .frame(minHeight: FuelMetrics.Control.minimumHitTarget, alignment: .top)
                .padding(.top, FuelMetrics.Space.s14)
                .padding(.bottom, FuelMetrics.Space.s12)

            palette.hair
                .frame(height: FuelMetrics.Line.hairline)
        }
        // The field is what the dialog is for, so it asks for the keyboard as
        // the sheet comes up — which is what the system alert this replaced did,
        // and the reason opening it did not cost a tap.
        //
        // `task` rather than `onAppear`, so the request is made once the view is
        // there to take it rather than while the sheet is still on its way up.
        //
        // **This is the one thing in this file no suite has watched happen.**
        // SwiftUI's focus engine does not engage in the test host at all: a
        // hosted field has not become first responder once the sheet has
        // settled, while the same field takes `becomeFirstResponder()` by hand
        // — the same shape of gap that stops a sheet's dismissal transition
        // from ever finishing there. So the sentence above says what the line
        // is for, not what was measured.
        .task { isWriting = true }
    }

    private func prompt(_ entry: FuelDialogEntry) -> Text {
        Text(entry.prompt)
            .foregroundStyle(palette.muted)
    }

    // MARK: - The answers

    /// The footer pair screens 14 and 15 draw, with this dialog's two words in
    /// it: the outlined pill hugging on the leading side, the accent-filled one
    /// taking the rest.
    ///
    /// **One deviation from that pair, and it is the label size on the way
    /// out.** The export sets its hugging secondary at `600 14px` and this sets
    /// it at `buttonLabel`, the `600 15px` it draws on every other labelled
    /// button — including the one full-width secondary it draws, screen 02's
    /// `Cancel`. The 14 belongs to `chipLabel`, which is pinned against Dynamic
    /// Type: right for the `New` chip and for a trash mark, wrong for a word a
    /// user has to read before deciding something irreversible. Everything else
    /// about the pair is the drawn one — the `s17`/`s20` padding, the hairline,
    /// the `Radius.pill`, the `s10` between them.
    ///
    /// Drawn here rather than reached for: the two pills this recomposes live
    /// in feature files — `MealResultPrimaryButton` in the log flow and
    /// `OnboardingButton` in onboarding — and the design layer does not reach
    /// upwards into a feature for a shape.
    private var answers: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s10) {
            Button(action: onCancel) {
                Text(copy.cancel)
                    .fuelStyle(FuelTypography.buttonLabel)
                    .foregroundStyle(palette.ink)
                    .padding(.vertical, FuelMetrics.Space.s17)
                    .padding(.horizontal, FuelMetrics.Space.s20)
                    .overlay {
                        RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                            .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
                    }
                    .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
            }
            .buttonStyle(FuelPressButtonStyle())

            Button(action: onConfirm) {
                Text(copy.confirm)
                    .fuelStyle(FuelTypography.buttonLabel)
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FuelMetrics.Space.s17)
                    .background(palette.accentColor, in: .rect(cornerRadius: FuelMetrics.Radius.pill))
                    .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
            }
            .buttonStyle(FuelPressButtonStyle())
        }
    }
}

// MARK: - Raising one

/// Puts a dialog in front of something, in the place a system alert or a
/// confirmation sheet used to stand.
///
/// **Both answers are carried out after the sheet has gone, not while it is
/// still up**, and the order is load-bearing rather than tidy. What a confirm
/// does here is close the screen underneath it — a meal deleted leaves for
/// Today, a discarded estimate leaves the flow — and dismissing a screen that
/// still has a sheet presented from it is a hierarchy tearing itself down in
/// two directions at once. Running the answer from `onDismiss` also puts the
/// destructive haptic where the meal actually disappears rather than where the
/// button was pressed, which is where `MealDetailView.delete` already argues it
/// belongs.
///
/// `onCancel` runs on every way out that is not the confirm button, including
/// the swipe and the tap outside, so a caller holding something pending gets it
/// back whichever way the user leaves.
private struct FuelDialogModifier: ViewModifier {

    let copy: FuelDialogCopy

    let entry: FuelDialogEntry?

    @Binding var isPresented: Bool

    let onConfirm: () -> Void

    let onCancel: () -> Void

    @Environment(\.fuelPalette) private var palette

    /// Which of the two answers the dialog left with. View state rather than
    /// something the caller can see: a dialog being answered is not a thing the
    /// model is doing.
    @State private var wasConfirmed = false

    /// How tall the question turned out to be.
    ///
    /// **A detent measured from the question rather than a height written down
    /// here**, because a height for a dialog is exactly the kind of number the
    /// export does not draw — and one written down here would be wrong at the
    /// first long question, the first wrapped hint and the first larger text
    /// size. `presentationSizing(.fitted)` is the API for this and iOS does not
    /// apply it to a sheet on a phone: with it, a two-line question came up 812
    /// points tall on an 874-point screen, which is the whole screen.
    ///
    /// It is held out here rather than inside the sheet so it survives the
    /// dialog being put away and asked again.
    @State private var height: CGFloat = .zero

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: answer) {
            FuelDialog(
                copy: copy,
                entry: entry,
                onConfirm: {
                    wasConfirmed = true
                    isPresented = false
                },
                onCancel: { isPresented = false }
            )
            // **The size alone, and nothing added to it for the home
            // indicator.** What comes back already includes the strip the
            // indicator needs — a sheet stands on the bottom edge of the screen
            // and the question is measured with that ground under it — so the
            // answers keep their own `s18` above it. Adding the safe area on
            // top was the first version of this line and it spent the same
            // distance twice: measured on a hosted render, the answers came to
            // rest 59 points above the card's bottom edge where 52 is the 18
            // they are drawn with and the 34 the indicator takes.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { measured in
                height = measured
            }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
            .presentationBackground(palette.background)
            .environment(\.fuelPalette, palette)
        }
    }

    private func answer() {
        guard wasConfirmed else {
            onCancel()
            return
        }
        wasConfirmed = false
        onConfirm()
    }
}

extension View {

    /// Asks the question in `copy` over this view, and carries out the answer.
    ///
    /// The one way a dialog is raised in Fuel. A feature file that reaches for
    /// `.alert` or `.confirmationDialog` is asking iOS to ask the question in
    /// its own words and its own drawing, which is the thing this replaced.
    func fuelDialog(
        _ copy: FuelDialogCopy,
        isPresented: Binding<Bool>,
        entry: FuelDialogEntry? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            FuelDialogModifier(
                copy: copy,
                entry: entry,
                isPresented: isPresented,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        )
    }
}
