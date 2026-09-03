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

    /// The calorie figure, and the only editable number on this screen.
    ///
    /// The three macro values are shown but not edited here: the export draws
    /// them as read-only cards, and Settings is where they are changed. A field
    /// that looks like a card is worse than a card.
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
    }

    private var macroCards: some View {
        HStack(spacing: FuelMetrics.Space.s10) {
            macroCard(title: "onboarding.goal.macro.protein", value: model.targets.protein)
            macroCard(title: "onboarding.goal.macro.carbs", value: model.targets.carbs)
            macroCard(title: "onboarding.goal.macro.fat", value: model.targets.fat)
        }
    }

    private func macroCard(title: LocalizedStringKey, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .fuelStyle(FuelTypography.macroLabelSmall)
                .foregroundStyle(palette.muted)
            Text(value, format: .number)
                .fuelStyle(FuelTypography.macroValueCard)
                .foregroundStyle(palette.ink)
                .padding(.top, FuelMetrics.Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, FuelMetrics.Space.s12)
        .padding(.horizontal, FuelMetrics.Space.s13)
        .background {
            RoundedRectangle(cornerRadius: FuelMetrics.Radius.card)
                .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
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
        }
        .buttonStyle(.plain)
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
