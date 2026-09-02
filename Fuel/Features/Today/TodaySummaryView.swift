import SwiftUI

// MARK: - Summary

/// The block under the title: the day's total, and then whatever the counting
/// mode has to say about it.
///
/// Goal mode draws the ring with three macro bars beside it. Count-only draws
/// neither — its three macros are a plain row of figures. The two are separate
/// branches rather than one layout with parts switched off, because that is how
/// the export draws them.
struct TodaySummaryView: View {

    let kilocalories: Int
    let suffix: String
    let summary: TodaySummary

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            total

            switch summary {
            case .goal(let goal):
                TodayGoalSummary(goal: goal)
                    .padding(.top, FuelMetrics.Space.s24)
            case .countOnly(let figures):
                TodayCountOnlySummary(figures: figures)
                    .padding(.top, FuelMetrics.Space.s26)
            }
        }
    }

    /// The figure and its suffix share a baseline-ish bottom edge: the export
    /// aligns them at the foot of the box and lifts the suffix by 8.
    private var total: some View {
        HStack(alignment: .bottom, spacing: FuelMetrics.Space.s10) {
            Text(TodayFormat.figure(kilocalories))
                .fuelStyle(FuelTypography.dayTotal)
                .foregroundStyle(palette.ink)

            Text(suffix)
                .fuelStyle(FuelTypography.totalSuffix)
                .foregroundStyle(palette.muted)
                .padding(.bottom, FuelMetrics.Space.s8)
        }
        .fuelAnimation(FuelMotion.value, value: kilocalories)
    }
}

// MARK: - Goal mode

/// Screen 05: the ring, and the three macro bars beside it.
private struct TodayGoalSummary: View {

    let goal: TodaySummary.Goal

    var body: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Ring.trailingGap) {
            TodayRing(fraction: goal.ringFraction, percentage: goal.percentage)

            VStack(alignment: .leading, spacing: FuelMetrics.Space.s13) {
                ForEach(goal.bars) { bar in
                    TodayMacroBarRow(bar: bar)
                }
            }
        }
    }
}

/// The calorie ring.
///
/// The export authors it against a 120-unit box and renders it into 104, so the
/// circle is built at full box size and scaled down as a whole. Drawing it at
/// 104 directly would mean converting the radius and the stroke by hand, and
/// two conversions are two chances to round.
private struct TodayRing: View {

    let fraction: Double
    let percentage: Int

    @Environment(\.fuelPalette) private var palette

    /// `Circle` fills its frame, so its radius is half the box; the export's
    /// stroke is centred on r 54, which is that inset in.
    private static let radiusInset = FuelMetrics.Ring.viewBox / 2 - FuelMetrics.Ring.radius

    var body: some View {
        ZStack {
            Circle()
                .inset(by: Self.radiusInset)
                .stroke(palette.soft, lineWidth: FuelMetrics.Ring.strokeWidth)

            Circle()
                .inset(by: Self.radiusInset)
                .trim(from: .zero, to: fraction)
                .stroke(
                    palette.accentColor,
                    style: StrokeStyle(lineWidth: FuelMetrics.Ring.strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(FuelMetrics.Ring.startAngleDegrees))
                .fuelAnimation(FuelMotion.value, value: fraction)
        }
        .frame(width: FuelMetrics.Ring.viewBox, height: FuelMetrics.Ring.viewBox)
        .scaleEffect(FuelMetrics.Ring.size / FuelMetrics.Ring.viewBox)
        .frame(width: FuelMetrics.Ring.size, height: FuelMetrics.Ring.size)
        .overlay {
            Text(TodayCopy.percentage(percentage))
                .fuelStyle(FuelTypography.monoValue)
                .foregroundStyle(palette.ink)
        }
        // Combined on its own the ring reads as a bare "68%", which says
        // nothing about what the share is of.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(TodayCopy.ringAccessibilityLabel(percentage)))
    }
}

/// One macro bar: name, track, fill, and the `used/goal` figure.
private struct TodayMacroBarRow: View {

    let bar: TodayMacroBar

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s10) {
            Text(TodayCopy.macroName(bar.macro))
                .fuelStyle(FuelTypography.macroLabel)
                .foregroundStyle(palette.muted)
                .frame(width: FuelMetrics.Control.macroLabelColumn, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.soft)
                    Rectangle()
                        .fill(palette.accentColor)
                        .frame(width: proxy.size.width * CGFloat(bar.fraction))
                }
            }
            .frame(height: FuelMetrics.Control.macroBarHeight)
            .fuelAnimation(FuelMotion.value, value: bar.fraction)

            Text(TodayCopy.macroRatio(used: bar.used, goal: bar.goal))
                .fuelStyle(FuelTypography.macroRatio)
                .foregroundStyle(palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Count-only mode

/// Screen 06: three figures in a row, with no goal to measure them against and
/// therefore no bar and no ring.
private struct TodayCountOnlySummary: View {

    let figures: [TodayMacroFigure]

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: FuelMetrics.Space.s26) {
            ForEach(figures) { figure in
                VStack(alignment: .leading, spacing: .zero) {
                    Text(TodayCopy.macroName(figure.macro))
                        .fuelStyle(FuelTypography.macroLabel)
                        .foregroundStyle(palette.muted)

                    Text(TodayCopy.macroGrams(figure.grams))
                        .fuelStyle(FuelTypography.macroValueLarge)
                        .foregroundStyle(palette.ink)
                        .padding(.top, FuelMetrics.Space.s2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .fuelAnimation(FuelMotion.value, value: figures)
    }
}
