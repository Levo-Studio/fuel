import SwiftUI

// MARK: - Day list

/// The day, grouped under its meal headings.
///
/// The order and the membership are `DayGrouping`'s: Breakfast, Lunch, Snack,
/// Dinner, entries sorted by time inside a group, and a group with no entries
/// already dropped. Nothing here re-sorts or re-filters, so a group cannot be
/// hidden in one place and counted in another.
struct TodayDayList: View {

    let groups: [MealGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: FuelMetrics.Space.s20) {
            ForEach(groups) { group in
                TodayMealGroupView(group: group)
            }
        }
        .fuelAnimation(FuelMotion.emphasised, value: groups)
    }
}

// MARK: - Group

private struct TodayMealGroupView: View {

    let group: MealGroup

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack(alignment: .firstTextBaseline) {
                Text(TodayCopy.mealHeading(group.label))
                    .fuelStyle(FuelTypography.sectionLabel)
                    .foregroundStyle(palette.muted)

                Spacer(minLength: .zero)

                Text(TodayCopy.groupKilocalories(group.kilocalories))
                    .fuelStyle(FuelTypography.meta)
                    .foregroundStyle(palette.muted)
            }
            .padding(.bottom, FuelMetrics.Space.s10)
            .accessibilityElement(children: .combine)

            TodayHairline(color: palette.hair)

            ForEach(group.entries) { entry in
                TodayEntryRow(entry: entry)
                    .padding(.vertical, FuelMetrics.Space.s14)

                TodayHairline(color: palette.hairSoft)
            }
        }
    }
}

// MARK: - Entry

private struct TodayEntryRow: View {

    let entry: NutritionEntry

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: .zero) {
                // The title is the one attacker-influenced string that survives
                // the provider parser: the model wrote it, and the model read a
                // photo or a sentence the user did not necessarily compose.
                // `Text(String)` is verbatim, so it renders no markdown and no
                // attributed markup however the title is punctuated; it still
                // wants a length cap, which belongs in the parser rather than
                // here so the stored entry is bounded too.
                Text(entry.title)
                    .fuelStyle(FuelTypography.entryTitle)
                    .foregroundStyle(palette.ink)

                Text(TodayCopy.entryMeta(time: TodayFormat.time(entry.loggedAt), source: entry.source))
                    .fuelStyle(FuelTypography.timestamp)
                    .foregroundStyle(palette.muted)
                    .padding(.top, FuelMetrics.Space.s3)
            }

            Spacer(minLength: .zero)

            Text(TodayFormat.figure(entry.kilocalories))
                .fuelStyle(FuelTypography.listValue)
                .foregroundStyle(palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rule

/// The divider under a heading and under every row.
///
/// A `Rectangle` rather than `Divider`, because `Divider` takes its thickness
/// and its colour from the system and the export states both.
private struct TodayHairline: View {

    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: FuelMetrics.Line.hairline)
    }
}
