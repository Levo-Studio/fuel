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
            TodayMealHeading(label: group.label, kilocalories: group.kilocalories)

            ForEach(group.entries) { entry in
                TodayEntryRow(entry: entry, onSelect: onSelect)

                TodayHairline(color: palette.hairSoft)
            }
        }
    }
}

// MARK: - Heading

/// The heading over a section of the day list: the meal on the leading edge,
/// what the section is worth opposite it, and the `hair` rule under both.
///
/// Extracted from the group above rather than written twice, because the row an
/// empty day carries stands in this list's place and is headed the way a
/// section of it is — see `TodayEmptyDayView`. A heading copied into a second
/// place is a heading that can be corrected here and left wrong there.
struct TodayMealHeading: View {

    let label: MealLabel

    /// What the section is worth, or `nil` for one with nothing to total.
    ///
    /// Screens 05 and 06 always draw the figure, because a group with no
    /// entries is never rendered at all. The empty day's row is the one section
    /// that stands with nothing under it, and `0 kcal` beside its heading would
    /// be a figure the export never draws — so it draws none, the way the
    /// get-started block's heading beside it does.
    let kilocalories: Int?

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack(alignment: .firstTextBaseline) {
                Text(TodayCopy.mealHeading(label))
                    .fuelStyle(FuelTypography.sectionLabel)
                    .foregroundStyle(palette.muted)

                Spacer(minLength: .zero)

                if let kilocalories {
                    Text(TodayCopy.groupKilocalories(kilocalories))
                        .fuelStyle(FuelTypography.meta)
                        .foregroundStyle(palette.muted)
                }
            }
            .padding(.bottom, FuelMetrics.Space.s10)
            .accessibilityElement(children: .combine)

            TodayHairline(color: palette.hair)
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
/// that is already past a fingertip; the floor `TodayDayRow` carries is never
/// reached here and so moves nothing.
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
        TodayDayRow {
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
        } trailing: {
            Text(TodayFormat.figure(entry.kilocalories))
                .fuelStyle(FuelTypography.listValue)
                .foregroundStyle(palette.ink)
        }
    }
}

// MARK: - Row geometry

/// One row of the day list, drawn `padding:14px 0` with its two halves pushed
/// apart — the leading block on one edge and a single value on the other.
///
/// Extracted rather than reproduced, for the reason `TodayMealHeading` is: the
/// row an empty day carries has to *be* a meal row rather than resemble one, so
/// the two share the geometry instead of each stating it. What differs between
/// them is what goes in the two slots, which is the whole of the difference.
///
/// The minimum is a floor and not the thing doing the work. At the drawn `s14`
/// either side of a 14.5pt title the region that answers to a finger is already
/// past it, so a frame that is never reached changes no layout — the same
/// reading the header's title block takes. It is here rather than at one call
/// site because the smallest text sizes are where it would otherwise be missed,
/// and the empty day's row is a single line where the entry row is two.
struct TodayDayRow<Leading: View, Trailing: View>: View {

    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            leading

            Spacer(minLength: .zero)

            trailing
        }
        .padding(.vertical, FuelMetrics.Space.s14)
        .frame(minHeight: FuelMetrics.Control.minimumHitTarget)
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
