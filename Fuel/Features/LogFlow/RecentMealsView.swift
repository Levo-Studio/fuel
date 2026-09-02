import SwiftUI

// MARK: - Recent meals

/// Screen 13: the meals already eaten, one tap from being logged again.
///
/// Presentation only. The list arrives built and the tap goes back out, so the
/// screen renders in a preview without a container and the model stays the one
/// place the database is touched.
struct RecentMealsView: View {

    let meals: [RecentMeal]
    let onLog: (RecentMeal) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .zero) {
                Text(LogFlowCopy.recentTitle)
                    .fuelStyle(FuelTypography.sheetTitle)
                    .foregroundStyle(FuelPalette.Camera.ink)

                Text(LogFlowCopy.recentHint)
                    .fuelStyle(FuelTypography.hint)
                    .foregroundStyle(FuelPalette.Camera.muted)
                    .padding(.top, FuelMetrics.Space.s8)

                VStack(alignment: .leading, spacing: .zero) {
                    ForEach(meals) { meal in
                        RecentMealRow(meal: meal) { onLog(meal) }
                    }
                }
                .padding(.top, FuelMetrics.Space.s24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, FuelMetrics.Space.s34)
            // The export draws screen 13's body in the same inset as its
            // header, unlike the result screens, whose body returns to the
            // ordinary margin.
            .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Row

/// A meal, its macros, its calories and the `+`.
///
/// The whole row is the button. The `+` is drawn as an affordance rather than
/// as a separate control — the design notes say a tap logs the meal straight
/// away, and a plus that had to be hit exactly would make the row look tappable
/// where it is not.
private struct RecentMealRow: View {

    let meal: RecentMeal
    let onLog: () -> Void

    var body: some View {
        Button(action: onLog) {
            HStack(alignment: .center, spacing: .zero) {
                VStack(alignment: .leading, spacing: .zero) {
                    Text(meal.title)
                        .fuelStyle(FuelTypography.listTitle)
                        .foregroundStyle(FuelPalette.Camera.ink)

                    Text(LogFlowCopy.macroSummary(meal.macros))
                        .fuelStyle(FuelTypography.macroSummary)
                        .foregroundStyle(FuelPalette.Camera.dim)
                        .padding(.top, FuelMetrics.Space.s3)
                }

                Spacer(minLength: FuelMetrics.Space.s14)

                HStack(alignment: .center, spacing: FuelMetrics.Space.s14) {
                    Text(LogFlowFormat.figure(meal.kilocalories))
                        .fuelStyle(FuelTypography.listValue)
                        .foregroundStyle(FuelPalette.Camera.ink)

                    Text(LogFlowCopy.addGlyph)
                        .fuelStyle(FuelTypography.addGlyph)
                        .foregroundStyle(FuelPalette.Camera.inkSecondary)
                }
            }
            .padding(.vertical, FuelMetrics.Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(meal.title))
        .accessibilityValue(Text(LogFlowCopy.kilocaloriesValue(meal.kilocalories)))
        .accessibilityHint(Text(LogFlowCopy.logHint))
        .overlay(alignment: .bottom) {
            FuelPalette.Camera.divider
                .frame(height: FuelMetrics.Line.hairline)
        }
    }
}

// MARK: - Preview

#Preview("Recent meals") {
    ZStack {
        FuelPalette(theme: .light, accent: .mono).camera
            .ignoresSafeArea()

        RecentMealsView(meals: LogFlowPreviewData.meals, onLog: { _ in })
    }
}
