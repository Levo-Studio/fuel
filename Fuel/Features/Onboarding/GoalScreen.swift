import SwiftUI

// MARK: - Screen 04

/// `04 · Onboarding · goal or count only`.
///
/// Two choices in one column, separated by a hairline. The goal card is the
/// selected one in the export and carries the figure and the three macro cards;
/// count-only is a title and a subtitle. Selecting count-only collapses the
/// goal card, because the numbers under it are the goal, and showing a goal for
/// a mode that has none would be the wrong screen.
struct GoalScreen: View {

    @Environment(\.fuelPalette) private var palette

    @Bindable var model: OnboardingModel

    /// What is in the calorie field. Parsed into the model on every keystroke;
    /// see `goalValue` for why it is not bound to the `Int` directly.
    @State private var goalDraft = ""

    @FocusState private var isEditingGoal: Bool

    var body: some View {
        OnboardingScreen(topPadding: FuelMetrics.Screen.onboardingTopPadding) {
            OnboardingEyebrow(text: "onboarding.step2")

            Text("onboarding.goal.headline")
                .fuelStyle(FuelTypography.display)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FuelMetrics.Space.s16)

            choices
                .padding(.top, FuelMetrics.Space.s44)
        } footer: {
            OnboardingFootnote(text: "onboarding.goal.footnote")
            OnboardingButton(title: "onboarding.continue") {
                isEditingGoal = false
                model.complete()
            }
        }
    }

    // MARK: - Choices

    private var choices: some View {
        VStack(spacing: 0) {
            goalCard
                .padding(.bottom, FuelMetrics.Space.s24)

            OnboardingHairline()

            countOnlyRow
                .padding(.vertical, FuelMetrics.Space.s22)
        }
        .fuelAnimation(FuelMotion.standard, value: model.countsAgainstGoal)
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                model.selectGoalMode()
            } label: {
                HStack(spacing: 0) {
                    Text("onboarding.goal.option")
                        .fuelStyle(FuelTypography.optionTitle)
                        .foregroundStyle(palette.ink)
                    Spacer(minLength: FuelMetrics.Space.s12)
                    OnboardingSelectionDot(isSelected: model.countsAgainstGoal)
                }
                .optionRowHitTarget()
            }
            .buttonStyle(.plain)

            if model.countsAgainstGoal {
                goalValue
                    .padding(.top, FuelMetrics.Space.s20)

                macroCards
                    .padding(.top, FuelMetrics.Space.s22)
            }
        }
    }

    /// The calorie figure.
    ///
    /// It binds to a `String` and commits on every keystroke rather than to the
    /// `Int` through a format style. `TextField(value:format:)` writes back
    /// when editing *ends*, and a number pad has no return key, so the only way
    /// off this field is the footer button — which saves. A goal typed and then
    /// confirmed would have been stored as the value it replaced, with nothing
    /// on screen to say so. A `String` also draws the figure the way the export
    /// does: `2400`, with no group separator.
    private var goalValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: FuelMetrics.Space.s8) {
            // The title is empty, the same pattern the key field uses.
            // `TextField(_:text:)` draws its title as the placeholder whenever
            // the field is empty, so passing the choice-card title here
            // rendered "Set a calorie goal" at 50pt mono, straight through both
            // 28pt margins, in the cleared state this field is built to allow.
            // Neither `.labelsHidden()` nor `prompt: nil` suppresses it — both
            // look as though they should, and `OnboardingTests` measures a
            // field written each way to keep that from being rediscovered. The
            // export draws no placeholder here, so there is none; the title
            // names the field for VoiceOver, which is what it was for.
            TextField("", text: $goalDraft)
                .accessibilityLabel(Text("onboarding.goal.option"))
                .fixedSize()
                .focused($isEditingGoal)
                .keyboardType(.numberPad)
                .fuelStyle(FuelTypography.goalValue)
                .foregroundStyle(palette.ink)
                .tint(palette.accentColor)
                .onChange(of: goalDraft) { _, typed in
                    let digits = GoalFieldInput.digits(in: typed)
                    if digits != typed { goalDraft = digits }
                    model.targets.kilocalories = GoalFieldInput.kilocalories(
                        from: digits,
                        previous: model.targets.kilocalories
                    )
                }

            Text("onboarding.goal.unit")
                .fuelStyle(FuelTypography.unit)
                .foregroundStyle(palette.muted)

            Spacer(minLength: 0)
        }
        // The field keeps its intrinsic width so `kcal` sits against the
        // digits, as drawn; the row is what takes the tap. Without this the
        // only target is the glyphs themselves, and a cleared field would have
        // no target at all.
        .contentShape(Rectangle())
        .onTapGesture { isEditingGoal = true }
        .onAppear { goalDraft = String(model.targets.kilocalories) }
        .onChange(of: isEditingGoal) { _, editing in
            // The export draws a figure here, never an empty space, so a field
            // left blank is put back to the goal it stands for. The goal itself
            // was kept while the field was empty — that is `GoalFieldInput`'s
            // rule — so this is the user's own number returning rather than a
            // default overwriting an edit. The macro cards below and the four
            // Settings rows do the same; without it this was the one field on
            // the screen that could be walked away from showing nothing.
            if !editing && goalDraft.isEmpty {
                goalDraft = String(model.targets.kilocalories)
            }
        }
    }

    /// The three macro targets, in the order the export draws them.
    ///
    /// **They are edited here at the owner's instruction.** The export draws
    /// them as three plain read-only cards, and this is the one place on screen
    /// 04 where the code does something the export does not show; it is written
    /// down here rather than left to be discovered. What is drawn is unchanged
    /// — the same border, radius, paddings, type and colour, and the same
    /// position for every glyph on the card. Only the tap is new.
    private var macroCards: some View {
        HStack(spacing: FuelMetrics.Space.s10) {
            MacroCard(title: "onboarding.goal.macro.protein", value: $model.targets.protein)
            MacroCard(title: "onboarding.goal.macro.carbs", value: $model.targets.carbs)
            MacroCard(title: "onboarding.goal.macro.fat", value: $model.targets.fat)
        }
    }

    private var countOnlyRow: some View {
        Button {
            model.selectCountOnly()
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("onboarding.goal.countOnly")
                        .fuelStyle(FuelTypography.optionTitle)
                        .foregroundStyle(palette.ink)
                    Text("onboarding.goal.countOnly.subtitle")
                        .fuelStyle(FuelTypography.caption)
                        .foregroundStyle(palette.muted)
                        .padding(.top, FuelMetrics.Space.s3)
                }
                Spacer(minLength: FuelMetrics.Space.s12)
                OnboardingSelectionDot(isSelected: !model.countsAgainstGoal)
            }
            .optionRowHitTarget()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Macro card

/// One of the three macro targets: its name, and the figure under it.
///
/// A type of its own rather than a function on `GoalScreen` because each card
/// holds a draft and a focus of its own, and neither can live in a view
/// builder's local scope.
///
/// The field is written the way the calorie field above it is, for the reasons
/// stated there: a `String` rather than the `Int`, committed on every
/// keystroke, because a number pad has no return key and the only way off the
/// screen is the footer button that saves. An empty title, because
/// `TextField(_:text:)` draws its title as the placeholder whenever the field
/// is empty — which would put "Protein" a second time on the card, at the
/// figure's 21pt, in the state the field is built to allow — and the name goes
/// on the field for VoiceOver instead.
private struct MacroCard: View {

    @Environment(\.fuelPalette) private var palette

    let title: LocalizedStringKey

    @Binding var value: Int

    @State private var draft = ""

    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .fuelStyle(FuelTypography.macroLabelSmall)
                .foregroundStyle(palette.muted)
            // The figure is laid out by the `Text` the card was drawn with and
            // painted by the field on top of it. A `TextField` is a UIKit text
            // field underneath and stands a point and a half taller than the
            // same string as a `Text`, which grew the card and pushed the
            // hairline and the count-only row below it down — visible in a
            // screenshot, and a design deviation the owner did not ask for. The
            // hidden `Text` keeps the card the size the export draws; the
            // overlay draws nothing of its own beyond the digits.
            //
            // It measures `value` rather than `draft` on purpose: a field the
            // user has cleared still stands for the figure the target holds, so
            // the card does not shrink for as long as it takes to retype it.
            //
            // The overlay is aligned on the **baseline** and not on an edge or
            // a centre. Two text renderers put the same string in boxes of
            // different heights, so any of those leaves the digits a device
            // pixel or three off where the `Text` drew them; the baseline is
            // the line both of them actually set the glyphs on, and with it a
            // screenshot of the screen is identical to the one taken before
            // the field arrived.
            Text(value, format: .number)
                .fuelStyle(FuelTypography.macroValueCard)
                .hidden()
                .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                    TextField("", text: $draft)
                        .accessibilityLabel(Text(title))
                        .fixedSize()
                        .focused($isEditing)
                        .keyboardType(.numberPad)
                        .fuelStyle(FuelTypography.macroValueCard)
                        .foregroundStyle(palette.ink)
                        .tint(palette.accentColor)
                        .onChange(of: draft) { _, typed in
                            let digits = GoalFieldInput.digits(in: typed)
                            if digits != typed { draft = digits }
                            value = GoalFieldInput.value(from: digits, previous: value)
                        }
                }
                .padding(.top, FuelMetrics.Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, FuelMetrics.Space.s12)
        .padding(.horizontal, FuelMetrics.Space.s13)
        .background {
            RoundedRectangle(cornerRadius: FuelMetrics.Radius.card)
                .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
        }
        // The field keeps its intrinsic width so the figure sits where the
        // export draws it, which leaves the card as the thing that takes the
        // tap — the arrangement the calorie field and the Settings rows both
        // use. The card is taller than a fingertip already, so nothing here
        // grows the region the way the choice rows above need to.
        .contentShape(Rectangle())
        .onTapGesture { isEditing = true }
        .onAppear { draft = String(value) }
        .onChange(of: isEditing) { _, editing in
            // The export draws a number on every card, so a field left empty is
            // put back to what it stands for. The target kept its value while
            // the field was blank — that is `GoalFieldInput`'s rule — so this is
            // the user's own figure returning, not a default overwriting an
            // edit. Settings does the same on its four rows.
            if !editing && draft.isEmpty {
                draft = String(value)
            }
        }
    }
}

// MARK: - The region an option row answers in

private extension View {

    /// Makes a choice row answer to a tap anywhere along it, and to a finger
    /// rather than to a stylus.
    ///
    /// Both halves fix something that was observed on the device. A row is a
    /// title, a `Spacer` and the selection dot, and a `Spacer` is not
    /// hit-testable: without the content shape the span between the two ends
    /// responds to nothing, so the only targets are the glyphs of the title and
    /// the 18pt dot, and the middle of a row the user is aiming at is dead.
    ///
    /// The height is the second half. The goal row draws a single 17pt line and
    /// is 21.7pt tall — half a fingertip — and the export has nothing to say
    /// about that, because a static render has no touches. `Color.clear` in an
    /// **overlay** is what grows the region without moving anything: an overlay
    /// is sized to its parent and takes no part in the parent's layout, so a
    /// child given a larger minimum simply overhangs it, centred. The row keeps
    /// the height, the position and the spacing the export draws; only what
    /// answers is bigger. A `frame` or a `padding` on the row itself would have
    /// pushed the calorie figure down.
    func optionRowHitTarget() -> some View {
        contentShape(Rectangle())
            .overlay {
                Color.clear
                    .frame(minHeight: FuelMetrics.Control.minimumHitTarget)
                    .contentShape(Rectangle())
            }
    }
}

// MARK: - Calorie field input

/// What the calorie field does with what is typed into it.
///
/// It is a type of its own rather than two closures inside the view because it
/// is the rule that replaced a lost edit, and a rule that fixed a bug has to be
/// testable. A test that sets `targets.kilocalories` directly — which is what
/// the first one did — cannot see this go wrong.
nonisolated enum GoalFieldInput {

    /// Anything that is not a digit is dropped as it is typed. A number pad
    /// does not offer much else, but a hardware keyboard and a paste both do.
    static func digits(in typed: String) -> String {
        String(typed.filter(\.isNumber))
    }

    /// The goal the field now means.
    ///
    /// An empty field keeps `previous` rather than becoming zero: clearing the
    /// field to retype it must not, for those few keystrokes, mean a goal of no
    /// calories, and the export draws no state for one.
    static func kilocalories(from typed: String, previous: Int) -> Int {
        value(from: typed, previous: previous)
    }

    /// The same rule for any of the four target fields.
    ///
    /// Settings draws three more of them — protein, carbs and fat, in grams —
    /// and they clear and refill exactly like this one. A second copy of the
    /// rule beside them would be a second place for the cleared field to start
    /// meaning zero again, which is the bug this type was written for.
    static func value(from typed: String, previous: Int) -> Int {
        Int(digits(in: typed)) ?? previous
    }
}
