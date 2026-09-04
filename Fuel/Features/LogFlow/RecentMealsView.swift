import SwiftUI

// MARK: - Segment labels

extension RecentList {

    /// The label on the switch. Both are new words: the export draws neither
    /// the switch nor a second list. See `RecentList`.
    var segmentTitle: LocalizedStringKey {
        switch self {
        case .recent: "logFlow.recent.segment.recent"
        case .favourites: "logFlow.recent.segment.favourites"
        }
    }
}

// MARK: - Recent meals

/// Screen 13: the meals already eaten, one tap from being logged again — and,
/// on the owner's instruction, the starred ones under a switch.
///
/// **The export draws no such switch.** Screen 13 is one list under one
/// heading, and the favourite exists in the design only as the `☆ Favourite` /
/// `★ Favourite` control on the two result screens, with nothing anywhere that
/// reads it back. The owner asked for the second list and for the switch above
/// it; that is the deviation, and it is theirs rather than a reading of the
/// export.
///
/// What the switch is made of is not invented, though. It is the same
/// `SettingsSegmentedControl` the provider picker and Light/Dark draw, standing
/// on the camera surface — see `FuelSegmentedSurface`.
///
/// Presentation only. Both lists arrive built and the tap goes back out, so the
/// screen renders in a preview without a container and the model stays the one
/// place the database is touched.
struct RecentMealsView: View {

    let meals: [RecentMeal]

    /// The same rows, narrowed to the starred meals.
    let favourites: [RecentMeal]

    let onLog: (RecentMeal) -> Void

    /// Which of the two lists is showing.
    ///
    /// View state, not a stored preference, and deliberately: the flow is
    /// opened in order to log something, Recent is the drawn screen, and it is
    /// the list that always has rows once anything has been logged at all. A
    /// remembered switch would open the tab on an empty Favourites list for
    /// anyone who once looked at it, which is a worse place to land than the
    /// one the design draws.
    @State private var shown: RecentList = .recent

    private var shownMeals: [RecentMeal] {
        switch shown {
        case .recent: meals
        case .favourites: favourites
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .zero) {
                // The heading follows the switch. A fixed `Recently eaten` over
                // the starred list would be the one thing worse than an
                // undrawn control: drawn copy that is untrue half the time.
                Text(LogFlowCopy.listTitle(shown))
                    .fuelStyle(FuelTypography.sheetTitle)
                    .foregroundStyle(FuelPalette.Camera.ink)

                // The hint explains a tap, so it is drawn only when there is
                // something to tap. On a fresh install it would otherwise
                // promise a row that is not on the screen.
                //
                // The heading stays either way: a titled screen with nothing
                // under it reads as empty, an untitled one reads as broken.
                if !shownMeals.isEmpty {
                    Text(LogFlowCopy.recentHint)
                        .fuelStyle(FuelTypography.hint)
                        .foregroundStyle(FuelPalette.Camera.muted)
                        .padding(.top, FuelMetrics.Space.s8)
                }

                // Between the header block and the list, because that is what
                // it does: it selects which list is under it, and it leaves
                // screen 13's drawn heading-and-hint pair where the export puts
                // them. The gap is the export's own `24` above the list —
                // whatever stands directly above the rows keeps that distance
                // from them, and the switch now stands there.
                SettingsSegmentedControl(
                    options: RecentList.allCases,
                    titleKey: \.segmentTitle,
                    selection: $shown,
                    surface: .camera
                )
                .padding(.top, FuelMetrics.Space.s24)

                list
                    .padding(.top, FuelMetrics.Space.s24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, FuelMetrics.Space.s34)
            // The export draws screen 13's body in the same inset as its
            // header, unlike the result screens, whose body returns to the
            // ordinary margin.
            .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
        }
        .fuelScrolling()
        // The same curve Today's day list uses for a group arriving, for the
        // same reason: the rows change under the user because the switch was
        // moved, not because a row answered their finger.
        .fuelAnimation(FuelMotion.emphasised, value: shown)
    }

    // MARK: - The rows

    @ViewBuilder
    private var list: some View {
        if shownMeals.isEmpty, shown == .favourites {
            // **The export draws no empty state**, here or anywhere. This
            // borrows rather than invents, the way Today's get-started block
            // does: it is screen 13's own hint — `400 12.5px`, `muted` — in the
            // place the rows would be, saying the one thing this screen cannot
            // otherwise say, which is where a favourite is made. Nothing is
            // offered to tap, because the control that makes one is on a result
            // screen and there is no route to it from here.
            //
            // Recent's own empty state is left as it was: the heading alone,
            // with no hint under it. That was settled before this feature and
            // is not this feature's to reopen.
            Text(LogFlowCopy.favouritesEmpty)
                .fuelStyle(FuelTypography.hint)
                .foregroundStyle(FuelPalette.Camera.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: .zero) {
                ForEach(shownMeals) { meal in
                    RecentMealRow(meal: meal) { onLog(meal) }
                }
            }
        }
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

                // No minimum, for the same reason as the header row: the
                // export draws the row `space-between`, and the 14 below is
                // the gap inside the right-hand group, not a floor between the
                // two sides.
                Spacer(minLength: .zero)

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
        .buttonStyle(FuelPressButtonStyle())
        .accessibilityLabel(Text(meal.title))
        .accessibilityValue(Text(LogFlowCopy.kilocaloriesValue(meal.kilocalories)))
        .accessibilityHint(Text(LogFlowCopy.logHint))
        .overlay(alignment: .bottom) {
            FuelPalette.Camera.divider
                .frame(height: FuelMetrics.Line.hairline)
        }
    }
}

// MARK: - Previews

#Preview("Recent meals") {
    ZStack {
        FuelPalette(theme: .light, accent: .mono).camera
            .ignoresSafeArea()

        RecentMealsView(
            meals: LogFlowPreviewData.meals,
            favourites: LogFlowPreviewData.favourites,
            onLog: { _ in }
        )
    }
}

/// A fresh install, which is the state the tab is there for: the heading
/// stands, the hint does not.
#Preview("Recent meals · nothing logged yet") {
    ZStack {
        FuelPalette(theme: .dark, accent: .mono).camera
            .ignoresSafeArea()

        RecentMealsView(meals: [], favourites: [], onLog: { _ in })
    }
}

/// The state the empty line exists for: meals have been logged, none of them
/// starred. Switch to Favourites to see it.
#Preview("Recent meals · nothing starred yet") {
    ZStack {
        FuelPalette(theme: .dark, accent: .mono).camera
            .ignoresSafeArea()

        RecentMealsView(meals: LogFlowPreviewData.meals, favourites: [], onLog: { _ in })
    }
}
