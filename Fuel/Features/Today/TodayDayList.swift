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

    /// A row was tapped: open that meal. The identity is the entry's own, the
    /// one that survives the boundary out of SwiftData.
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FuelMetrics.Space.s20) {
            ForEach(groups) { group in
                TodayMealGroupView(group: group, onSelect: onSelect)
            }
        }
        .fuelAnimation(FuelMotion.emphasised, value: groups)
    }
}

// MARK: - Group

private struct TodayMealGroupView: View {

    let group: MealGroup

    let onSelect: (UUID) -> Void

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
                TodayEntryRow(entry: entry, onSelect: onSelect)

                TodayHairline(color: palette.hairSoft)
            }
        }
    }
}

// MARK: - Entry

/// One meal in the list, and the way into it.
///
/// **The export draws no control on this row**, and nothing here is added to
/// it: the two lines, the figure, their type, their colour and the `s14` bands
/// above and below are the drawn ones. What changed is that the drawn row is
/// now the button rather than sitting inside one — the padding moved in with
/// it, so the region that answers to a finger is the whole row and not the
/// height of the title. At the drawn `s14` either side of two lines of text
/// that is already past a fingertip, so no minimum has to be imposed on top.
private struct TodayEntryRow: View {

    let entry: NutritionEntry

    let onSelect: (UUID) -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        Button {
            onSelect(entry.id)
        } label: {
            row
        }
        .buttonStyle(FuelPressButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(TodayCopy.entryHint))
    }

    private var row: some View {
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
        .padding(.vertical, FuelMetrics.Space.s14)
        .contentShape(.rect)
    }
}

// MARK: - Rule

/// The divider under a heading and under every row.
///
/// A `Rectangle` rather than `Divider`, because `Divider` takes its thickness
/// and its colour from the system and the export states both.
///
/// Shared with the get-started checklist, which stands in the same place and
/// draws the same two rules — `hair` under a heading, `hairSoft` between rows.
struct TodayHairline: View {

    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: FuelMetrics.Line.hairline)
    }
}
