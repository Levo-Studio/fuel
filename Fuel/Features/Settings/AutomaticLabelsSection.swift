import SwiftUI

// MARK: - Automatic labels section

/// The second section of screen 17: the line saying where a label comes from,
/// and the four clock rows under it.
struct AutomaticLabelsSection: View {

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        SettingsSection(
            titleKey: "settings.section.labels",
            headingSpacing: FuelMetrics.Space.s10
        ) {
            // Spec, but not drawn: the line is a `[P]` row in the design notes'
            // copy table and grepping `Screens2c.dc.html` for it comes back
            // empty, so it has no drawn geometry of its own. The gap is the one
            // the export's only comparable note has — the privacy line at the
            // foot of this screen, which is `monoNote` in `muted` sitting `16`
            // under the rule above it — and the same borrowing the camera note
            // on screen 16 does.
            Text("settings.labels.note")
                .fuelStyle(FuelTypography.monoNote)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FuelMetrics.Space.s16)

            ForEach(SettingsLabelRow.drawn) { row in
                SettingsRow(
                    topPadding: FuelMetrics.Space.s11,
                    bottomPadding: FuelMetrics.Space.s11,
                    showsHairline: row != SettingsLabelRow.drawn.last
                ) {
                    Text(row.titleKey)
                        .fuelStyle(FuelTypography.settingsRowLabel)
                        .foregroundStyle(palette.ink)

                    Spacer(minLength: FuelMetrics.Space.s12)

                    Text(row.windowKey)
                        .fuelStyle(FuelTypography.settingsRowTime)
                        .foregroundStyle(palette.muted)
                }
            }
        }
    }
}

// MARK: - The drawn rows

/// One of the four rows the export draws under `Automatic labels`.
///
/// **These are drawn copy, not a projection of the labelling rule, and they are
/// deliberately not derived from `MealLabel` or `MainMeal`.** The rows are the
/// plain-language summary the user reads; the rule the app runs differs from
/// them in three places, all of them written down in
/// `design/Fuel Design Notes.md` under "Two things in the export that are not
/// the rule" and "Owner ruling: the late hours":
///
/// - Snack has no window of its own. The `15:00 – 17:59` on its row names the
///   ordinary gap between lunch and dinner; an entry at 16:00 on a day with no
///   lunch yet is *lunch*, and no code reads a snack window.
/// - Dinner's reach runs to the end of the calendar day, not to the `22:59`
///   this row prints.
/// - The small hours are always a snack, which no row here says.
///
/// Deriving the list from the labeler would therefore either print something
/// the design does not draw, or force `Nutrition/` to publish a shape that
/// exists only to feed this list. Neither is worth it for four static rows, so
/// nothing in this file imports the rule.
struct SettingsLabelRow: Identifiable, Equatable {

    /// The label this row is about, as a name rather than a `MealLabel` — the
    /// enum belongs to the rule, and this row is not.
    let id: String

    let titleKey: LocalizedStringKey
    let windowKey: LocalizedStringKey

    /// The four rows, in the order screen 17 draws them.
    static let drawn: [SettingsLabelRow] = [
        SettingsLabelRow(
            id: "breakfast",
            titleKey: "settings.labels.breakfast",
            windowKey: "settings.labels.breakfast.window"
        ),
        SettingsLabelRow(
            id: "lunch",
            titleKey: "settings.labels.lunch",
            windowKey: "settings.labels.lunch.window"
        ),
        SettingsLabelRow(
            id: "snack",
            titleKey: "settings.labels.snack",
            windowKey: "settings.labels.snack.window"
        ),
        SettingsLabelRow(
            id: "dinner",
            titleKey: "settings.labels.dinner",
            windowKey: "settings.labels.dinner.window"
        )
    ]
}
