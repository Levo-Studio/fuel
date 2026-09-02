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
    private var goalValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: FuelMetrics.Space.s8) {
            TextField(
                "onboarding.goal.option",
                value: $model.targets.kilocalories,
                format: .number
            )
            .labelsHidden()
            .fixedSize()
            .keyboardType(.numberPad)
            .fuelStyle(FuelTypography.goalValue)
            .foregroundStyle(palette.ink)
            .tint(palette.accentColor)

            Text("onboarding.goal.unit")
                .fuelStyle(FuelTypography.unit)
                .foregroundStyle(palette.muted)
        }
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
