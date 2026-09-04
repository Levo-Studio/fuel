import SwiftUI
import UIKit

// MARK: - What a dialog says

/// The words on a dialog: the question, the line under it where there is one,
/// and the two answers.
///
/// A value rather than four parameters, because the same strings travel
/// together to more than one caller and one of them — the discard question — is
/// deliberately shared word for word between two screens. A type keeps that one
/// value one value.
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

    /// Whether the answer that goes ahead destroys something.
    ///
    /// It decides which of the two answers the dialog puts its weight behind —
    /// see `FuelDialog.answers` — so it is stated by the caller rather than
    /// guessed from the verb. Three of the four questions this app asks destroy
    /// something and the fourth writes a line of text down, and no reading of
    /// the words would tell them apart.
    let destroys: Bool

    init(title: String, hint: String? = nil, confirm: String, cancel: String, destroys: Bool) {
        self.title = title
        self.hint = hint
        self.confirm = confirm
        self.cancel = cancel
        self.destroys = destroys
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
/// and no destructive control of any kind on any of the seventeen screens.
/// Anything here is therefore undrawn, and the whole of this view is a
/// recomposition of things the export does draw, on the owner's instruction
/// that a question the app asks should look like the app asking it rather than
/// like iOS asking on its behalf.
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
/// - The two answers are the footer pair screens 14 and 15 draw: a pill that
///   hugs its label, an accent-filled pill that takes the rest, `s10` between
///   them. Which of the two carries which answer is `answers`' subject.
/// - The field is screen 12's own — `textEntry`, the type that screen sets a
///   written sentence in — over the hairline rule the onboarding key field
///   draws under itself, which is the export's only chrome on a field on a
///   themed surface.
///
/// **Every way out of this sheet except the confirm button is the safe
/// answer.** The swipe down, the tap outside, and the way out itself all
/// cancel. That is what lets the platform's own dismissal be left switched on
/// for a question about deleting an entry — a gesture made by accident, an app
/// sent to the background, a device rotated, all end with the entry still
/// there.
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
    /// it: one pill hugging its label, one accent-filled pill taking the rest,
    /// `s10` between them.
    ///
    /// **Which answer gets the fill is decided by what the other one does.**
    /// The app puts its weight behind the answer it would rather the user
    /// took: on a question that only writes something down that is the answer
    /// that goes ahead, and on a question that destroys something it is the way
    /// out. So the filled pill carries `Done` on the item field and `Keep` in
    /// front of a delete, and the hugging pill carries the other one. It is the
    /// owner's ruling, and it is the platform's own convention on the dialog
    /// this replaced — iOS draws the destructive verb apart and leaves the
    /// default weight on the safe answer — so a user's muscle memory is not
    /// being retrained by this app alone.
    ///
    /// **The way out keeps the leading side either way**, which is what makes
    /// the arrangement safer rather than only different. Both controls that can
    /// raise a destructive question — the trash circle on a logged meal, the
    /// trash pill on a scan result — are drawn in the *leading* corner of a
    /// footer, so a second tap that arrives before the sheet is up lands on the
    /// answer that changes nothing; and the largest, easiest control on the
    /// sheet is now that same answer, so a careless deliberate tap fails safe
    /// too. The pair is therefore mirrored against the export's own footer,
    /// which draws the hug leading and the fill trailing.
    ///
    /// **The destructive verb is drawn in `palette.error`, and only its ink
    /// is.** The export draws no destructive control anywhere and no red — the
    /// only chromatic marks in the seventeen screens are the four accent
    /// swatches in Settings — so the colour cannot come from the screens. It
    /// comes from the notes, which specify a sixth value that is explicitly not
    /// an accent: `oklch(0.62 0.17 25)`, `design/Fuel Design Notes.md` lines 82
    /// to 84. Three things follow from how that value is specified and used,
    /// and together they decide the whole treatment:
    ///
    /// - It carries **no on-colour**, unlike every accent, so it cannot fill
    ///   anything: there is no stated ink for a label sitting on it, and
    ///   inventing one is the gap the design rules forbid filling with taste.
    /// - Everywhere it is already drawn it is **ink** — the failed-key note in
    ///   Settings and the failed-estimate title on the analysis surface — so
    ///   ink is the use the design system actually establishes for it.
    /// - The notes say the accent drives filled buttons, and a filled pill in
    ///   the accent is what `Add` and `Continue` are. A destructive verb drawn
    ///   that way would be the same button as those, in the user's own accent.
    ///
    /// So the destructive answer is the drawn outlined pill with one thing
    /// changed: its label's ink. Its hairline stays `hair` and its shape,
    /// padding and type stay the pill's — recolouring the border would be a
    /// second decision the export does not support.
    ///
    /// **One deviation from the drawn pair beyond that, and it is the label
    /// size on the hugging pill.** The export sets it at `600 14px` and this
    /// sets it at `buttonLabel`, the `600 15px` it draws on every other
    /// labelled button — including the one full-width secondary it draws,
    /// screen 02's `Cancel`. The 14 belongs to `chipLabel`, which is pinned
    /// against Dynamic Type: right for the `New` chip and for a trash mark,
    /// wrong for a word a user has to read before deciding something
    /// irreversible. Everything else is the drawn one — the `s17`/`s20`
    /// padding, the hairline, the `Radius.pill`, the `s10` between them.
    ///
    /// Drawn here rather than reached for: the two pills this recomposes live
    /// in feature files — `MealResultPrimaryButton` in the log flow and
    /// `OnboardingButton` in onboarding — and the design layer does not reach
    /// upwards into a feature for a shape.
    private var answers: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s10) {
            if copy.destroys {
                filled(copy.cancel, perform: onCancel)
                hugging(copy.confirm, ink: palette.error, perform: onConfirm)
            } else {
                hugging(copy.cancel, ink: palette.ink, perform: onCancel)
                filled(copy.confirm, perform: onConfirm)
            }
        }
    }

    /// The accent-filled pill, which takes whatever width the other one leaves.
    private func filled(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .fuelStyle(FuelTypography.buttonLabel)
                .foregroundStyle(palette.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, FuelMetrics.Space.s17)
                .background(palette.accentColor, in: .rect(cornerRadius: FuelMetrics.Radius.pill))
                .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
        }
        .buttonStyle(FuelPressButtonStyle())
    }

    /// The outlined pill, which hugs its label.
    private func hugging(_ title: String, ink: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .fuelStyle(FuelTypography.buttonLabel)
                .foregroundStyle(ink)
                .padding(.vertical, FuelMetrics.Space.s17)
                .padding(.horizontal, FuelMetrics.Space.s20)
                .overlay {
                    RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                        .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
                }
                .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
        }
        .buttonStyle(FuelPressButtonStyle())
    }

    // MARK: - How tall the shortest question is

    /// The height of a question with one line of title, no line under it, no
    /// field, and its two answers: the delete question and both discard
    /// questions, which is three of the four this app asks.
    ///
    /// **It exists to open the sheet at, not to draw at.** The detent is
    /// measured from the question — see `FuelDialogModifier.height` — and a
    /// measurement does not exist until the question has been laid out once, so
    /// without this the first raise asks UIKit for a detent of zero and the
    /// sheet grows under the user's finger. Every term is a drawn value or the
    /// bundled face's own line height for a drawn type; nothing here is a
    /// number for a panel.
    static var shortestQuestion: CGFloat {
        FuelMetrics.Space.s22
            + FuelTypography.sheetTitle.height(ofLines: 1)
            + FuelMetrics.Space.s24
            + FuelMetrics.Space.s17 + FuelTypography.buttonLabel.height(ofLines: 1) + FuelMetrics.Space.s17
            + FuelMetrics.Space.s18
    }

    /// What to open the sheet at, before the question has been measured on it.
    ///
    /// **A zero detent is not a neutral placeholder.** UIKit refuses it and
    /// says so — `[Invalid Configuration] Invalid sheet detent height: 0.0`,
    /// once per raise — and then opens the sheet at a height of its own
    /// choosing, which the measurement corrects a frame later by moving every
    /// answer on it. `MealDetailView` is built again on every push, so that is
    /// not a first-run cost: it is what a user would see every time they open a
    /// meal and reach for the trash mark.
    ///
    /// **The question is asked its own height rather than told what it is.**
    /// The obvious seed — the paddings and one line of each type, added up,
    /// which is `shortestQuestion` — is right only for a question that fits on
    /// one line, and the one this app asks most does not: the owner's delete
    /// sentence wraps at 22 points, and a seed short by that line opened the
    /// sheet 28 points under its settled height. Laying the same view out once,
    /// at the width it is about to come up at, is the only thing that knows how
    /// many lines a question takes at the user's own text size.
    ///
    /// `shortestQuestion` stays as the answer before the screen underneath has
    /// reported its own width, which is the one moment there is nothing to
    /// measure against.
    static func seed(
        for copy: FuelDialogCopy,
        entry: FuelDialogEntry?,
        on ground: FuelDialogGround,
        palette: FuelPalette,
        textSize: DynamicTypeSize
    ) -> CGFloat {
        guard ground.width > .zero else { return shortestQuestion + ground.inset }
        let measuring = UIHostingController(
            rootView: FuelDialog(copy: copy, entry: entry, onConfirm: {}, onCancel: {})
                .environment(\.fuelPalette, palette)
                .dynamicTypeSize(textSize)
        )
        let fitted = measuring.sizeThatFits(
            in: CGSize(width: ground.width, height: .greatestFiniteMagnitude)
        )
        return fitted.height + ground.inset
    }
}

// MARK: - Which answer was taken

/// Which of a dialog's two answers it was left with.
///
/// **A value with a rule of its own, rather than three lines inside the
/// modifier**, for the reason the nutrition core is not allowed to know about
/// SwiftData: what decides whether an irreversible action goes ahead is worth
/// being able to run without a screen. It could not be run at all where it
/// lived — a sheet's dismissal never completes in a test host, so both branches
/// of it executed zero times and every assertion about them passed by never
/// being reached.
nonisolated enum FuelDialogAnswer {

    /// The confirm button was pressed.
    case wentAhead

    /// Everything else: the way out, the swipe down, the tap outside, and a
    /// screen that went away underneath the question.
    case changedNothing

    /// Reads the answer out of the flag the confirm button sets, and puts the
    /// flag down on the way past.
    ///
    /// **The reset is the part worth testing, not the branch.** `guard` on a
    /// `Bool` is not where a bug would hide; a flag left standing is. Left set,
    /// the next dismissal of the next dialog raised from the same modifier —
    /// the same screen, the meal after this one — would answer `wentAhead`
    /// without anyone having pressed anything, and what that runs is a delete.
    /// It goes down *before* the answer is handed back rather than after, so
    /// there is no window in which the caller's own work could see it still
    /// set.
    static func taken(from confirmed: inout Bool) -> FuelDialogAnswer {
        guard confirmed else { return .changedNothing }
        confirmed = false
        return .wentAhead
    }
}

// MARK: - The screen underneath

/// What a dialog needs to know about the screen it is raised over before it has
/// a sheet of its own to measure.
nonisolated struct FuelDialogGround: Equatable {

    var width: CGFloat = .zero

    /// The strip the home indicator takes, which the card has to pay for out of
    /// its own height.
    var inset: CGFloat = .zero
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
    /// dialog being put away and asked again — though not the screen being
    /// pushed again, which is why the value below matters.
    @State private var height: CGFloat = .zero

    /// The screen this is raised over: how wide it is, and how much of its
    /// bottom the home indicator takes.
    ///
    /// Read from the screen rather than from the sheet because both are needed
    /// *before* the sheet exists — see `seed`. What the sheet itself measures
    /// already includes the strip, so nothing is added to it there.
    @State private var ground = FuelDialogGround()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var seed: CGFloat {
        FuelDialog.seed(
            for: copy,
            entry: entry,
            on: ground,
            palette: palette,
            textSize: dynamicTypeSize
        )
    }

    func body(content: Content) -> some View {
        content
        .onGeometryChange(for: FuelDialogGround.self) { proxy in
            FuelDialogGround(width: proxy.size.width, inset: proxy.safeAreaInsets.bottom)
        } action: { measured in
            ground = measured
        }
        .sheet(isPresented: $isPresented, onDismiss: answer) {
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
            .presentationDetents([.height(height > .zero ? height : seed)])
            .presentationDragIndicator(.visible)
            .presentationBackground(palette.background)
            .environment(\.fuelPalette, palette)
        }
    }

    /// Which answer the dialog was left with, carried out once it has gone.
    private func answer() {
        switch FuelDialogAnswer.taken(from: &wasConfirmed) {
        case .wentAhead:
            onConfirm()
        case .changedNothing:
            onCancel()
        }
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
