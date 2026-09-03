import SwiftUI

// MARK: - Automatic labels section

/// The second section of screen 17: the line saying where a label comes from,
/// and the clock rows under it.
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

/// One of the clock rows under `Automatic labels`.
///
/// **The export draws four rows here**, with a `Snack` row at `15:00 – 17:59`
/// between lunch and dinner. **The snack row is removed on the owner's
/// instruction**, and this is the one place the code deliberately draws less
/// than the export. Snack is not a clock window: it is what an entry gets when
/// no main meal is still available to it, so a row naming hours for it states
/// something the app does not do. An entry at 23:30 is a snack that the drawn
/// band excludes, and an entry at 16:00 on a day with no lunch yet is *lunch*,
/// which the drawn band gets outright wrong. Three rows, one per main meal, is
/// what is left once the false one goes.
///
/// **The three that remain are still literal copy, and are deliberately not
/// derived from `MealLabel` or `MainMeal`.** Their equal count is a
/// coincidence, not a correspondence. The rows are the plain-language summary
/// the user reads, and the rule the app runs reaches further than any of them
/// says — the divergences are written down in `design/Fuel Design Notes.md`
/// under "Two things in the export that are not the rule" and "Owner ruling:
/// the late hours":
///
/// - Lunch's row stops at `14:59`; lunch's reach runs through the
///   `15:00 – 17:59` gap the removed row used to claim.
/// - Dinner's row stops at `22:59`; dinner's reach runs to the end of the
///   calendar day.
/// - The small hours claim no main meal at all, which no row here says.
///
/// Deriving the list from the labeler would therefore either print reaches the
/// design does not draw, or force `Nutrition/` to publish a shape that exists
/// only to feed this list. Neither is worth it for three static rows, so
/// nothing in this file imports the rule.
struct SettingsLabelRow: Identifiable, Equatable {

    /// The label this row is about, as a name rather than a `MealLabel` — the
    /// enum belongs to the rule, and this row is not.
    let id: String

    let titleKey: LocalizedStringKey
    let windowKey: LocalizedStringKey

    /// The three rows, in the order screen 17 draws them.
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
            id: "dinner",
            titleKey: "settings.labels.dinner",
            windowKey: "settings.labels.dinner.window"
        )
    ]
}
