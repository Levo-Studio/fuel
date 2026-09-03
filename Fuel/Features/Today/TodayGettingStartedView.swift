import SwiftUI

// MARK: - Getting started

/// What Today draws while the day has no entries: four things to do, in the
/// space the meal sections would otherwise occupy.
///
/// **The export draws no empty state**, on either Today screen. Nothing here is
/// therefore a drawn screen being reproduced, and none of it invents a visual
/// language either: every value is one the export already draws somewhere,
/// recomposed. Where each comes from is named at the line that uses it, because
/// a reviewer holding this against `design/` has no single frame to hold it
/// against and has to be able to check them one by one.
struct TodayGettingStartedView: View {

    let checklist: TodayGettingStarted

    let onOpenSettings: () -> Void
    let onAddEntry: () -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            // The meal-section heading of screens 05 and 06, verbatim: 600
            // 11.5px, .08em, uppercase, muted, ten above its `hair` rule. The
            // block stands where a meal section would, so it is headed the way
            // one is.
            Text(TodayCopy.gettingStartedHeading)
                .fuelStyle(FuelTypography.sectionLabel)
                .foregroundStyle(palette.muted)
                .padding(.bottom, FuelMetrics.Space.s10)

            TodayHairline(color: palette.hair)

            ForEach(checklist.items) { item in
                TodayGettingStartedRow(item: item, action: { open(item.step) })

                // Screens 16 and 17's row vocabulary: `hairSoft` between rows,
                // and the last row of a section left open.
                if item.step != checklist.items.last?.step {
                    TodayHairline(color: palette.hairSoft)
                }
            }
        }
        // The same curve the day list uses for a group arriving, for the same
        // reason: a tick that appears on the way back from Settings is a row
        // changing under the user rather than a control answering their finger.
        .fuelAnimation(FuelMotion.emphasised, value: checklist)
    }

    private func open(_ step: TodayGettingStartedStep) {
        switch step.destination {
        case .settings: onOpenSettings()
        case .logFlow: onAddEntry()
        }
    }
}

// MARK: - Row

/// A title on the leading edge, the drawn check on the trailing edge when the
/// step is done, and nothing there when it is not.
private struct TodayGettingStartedRow: View {

    let item: TodayGettingStartedItem
    let action: () -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: FuelMetrics.Space.s12) {
                // Screen 16's row label: 500 14px, ink.
                Text(TodayCopy.gettingStartedTitle(item.step))
                    .fuelStyle(FuelTypography.itemTitle)
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: .zero)

                // The check of screen 03, in the twenty-unit box it is authored
                // in and at the weight the design states for it. The slot is
                // held whether or not the check is in it, so the four titles
                // and the rule under them do not shift as rows are ticked.
                ZStack {
                    if item.isDone {
                        FuelCheckGlyph()
                            .stroke(
                                palette.ink,
                                style: StrokeStyle(
                                    lineWidth: FuelMetrics.Line.Glyph.check,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }
                }
                .frame(
                    width: FuelMetrics.Line.Glyph.viewBox,
                    height: FuelMetrics.Line.Glyph.viewBox
                )
            }
            // The day-list row's own padding, drawn `14px 0` on screens 05 and
            // 06 — this block stands in that list's place. It also settles the
            // touch target: 14 above and below a 14pt title is past 44, and the
            // minimum below is the floor rather than the thing doing the work.
            .padding(.vertical, FuelMetrics.Space.s14)
            .frame(maxWidth: .infinity, minHeight: FuelMetrics.Control.minimumHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(TodayCopy.gettingStartedState(isDone: item.isDone)))
    }
}
