import SwiftUI

// MARK: - An empty day, still running

/// One meal section with one row in it, standing where the day list will be.
///
/// **The export draws no empty state**, on either Today screen, so nothing here
/// reproduces a frame. Every value is one the export draws somewhere else,
/// recomposed, and each is named at the line that uses it — a reviewer holding
/// this against `design/` has no single frame to hold it against and has to be
/// able to check them one at a time.
///
/// The two things it is made of are the day list's own: the section heading of
/// screens 05 and 06, and a row with that list's geometry. It stands in for a
/// meal row, so it is one, down to the rule that closes it.
struct TodayEmptyDayView: View {

    let emptyDay: TodayEmptyDay

    /// The plus control's destination, which is where the checklist's meal row
    /// goes too. This block opens no route of its own.
    let onAddEntry: () -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            // Headed as a meal section, because it is one: the meal the label
            // rule would give a meal logged at this moment. No figure beside
            // it — see `TodayMealHeading.kilocalories`.
            TodayMealHeading(label: emptyDay.label, kilocalories: nil)

            Button(action: onAddEntry) {
                TodayDayRow {
                    // The entry title of screens 05 and 06: 500 14.5px, ink.
                    // One line where an entry has two, because the second is
                    // an entry's time and its source and there is neither.
                    Text(TodayCopy.emptyDayTitle)
                        .fuelStyle(FuelTypography.entryTitle)
                        .foregroundStyle(palette.ink)
                } trailing: {
                    // Screen 13's own `+`, in the place a row's trailing value
                    // stands: `300 22px`, the only weight-300 glyph the export
                    // draws, and drawn there for exactly this meaning — tapping
                    // this row logs a meal. The add button's plus is the other
                    // one the export draws and is not this: it is a path inside
                    // a 58pt accent circle, a control floating over the list
                    // rather than an element of a row in it.
                    //
                    // Screen 13 draws it a step below its row's ink, on the
                    // camera surface and in the camera's own colours. `muted`
                    // is this palette's step below `ink` and is what the meta
                    // line of a meal row is already drawn in, so the transfer
                    // is the drawn relationship rather than the drawn alpha.
                    Text(TodayCopy.emptyDayAddGlyph)
                        .fuelStyle(FuelTypography.addGlyph)
                        .foregroundStyle(palette.muted)
                }
            }
            .buttonStyle(FuelPressButtonStyle())
            // Named rather than combined, so the `+` is not read out after the
            // words that already say what it does — the way screen 13's rows
            // name themselves. The label is the action, so there is no hint to
            // add to it.
            .accessibilityLabel(Text(TodayCopy.emptyDayTitle))

            // The day list's closing rule, not the checklist's open last row.
            // The checklist leaves its last row open because three fixed rows
            // are a finished set, the way a section of screen 17 is; this is
            // the other case that comment names — a list that continues, whose
            // next rows arrive as the day is logged.
            TodayHairline(color: palette.hairSoft)
        }
        // The heading changes under the user when the day reaches the next
        // meal, which is a row changing rather than a control answering a
        // finger — the same reading, and the same curve, as a group arriving in
        // the day list. Reduce Motion is `FuelMotion`'s to answer.
        .fuelAnimation(FuelMotion.emphasised, value: emptyDay)
    }
}

// MARK: - Previews

#Preview("Empty day · breakfast") {
    TodayEmptyDayPreview(hour: 8, palette: FuelPalette(theme: .dark, accent: .mono))
}

/// The heading the owner did not name, and the one the rule reaches in the
/// small hours: an entry at 02:00 is a snack whatever the day did.
#Preview("Empty day · the small hours") {
    TodayEmptyDayPreview(hour: 2, palette: FuelPalette(theme: .light, accent: .green))
}

/// The block at a chosen time of day, built through the real initialiser so a
/// preview cannot show a heading the rule would not give.
private struct TodayEmptyDayPreview: View {

    let hour: Int
    let palette: FuelPalette

    private var emptyDay: TodayEmptyDay? {
        let calendar = Calendar.current
        let moment = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date())
        return TodayEmptyDay(
            isToday: true,
            hasEntries: false,
            isGettingStartedOffered: false,
            now: moment ?? Date(),
            calendar: calendar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            if let emptyDay {
                TodayEmptyDayView(emptyDay: emptyDay, onAddEntry: {})
            }
        }
        .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.background)
        .environment(\.fuelPalette, palette)
    }
}
