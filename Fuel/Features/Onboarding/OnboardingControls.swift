import SwiftUI

// MARK: - Screen frame

/// The shell all four onboarding screens sit in: the background, the drop from
/// the top safe area, the 28pt side margin, and the footer held above the
/// bottom one.
///
/// Both edges read the export the same way, because the mockup has no safe
/// areas of its own. Its status bar is a stand-in for the device's and is drawn
/// as a sibling row *before* the container that carries `padding:88px 28px 0`,
/// so the drawn 88 is a distance below the bar rather than from the frame edge
/// — which makes it 88 below the real top safe area. The mockup draws no home
/// indicator at all, so the drawn `bottom:34px` is measured to an edge the
/// device does not have there: it becomes 34 above the bottom safe area.
///
/// An earlier reading put the footer flat on the safe-area boundary, on the
/// grounds that 34 is exactly the iPhone's bottom inset and the designer had
/// drawn by hand the clearance hardware gives for free. That was wrong in the
/// same way the top was: the mockup omits the chrome the device draws, and a
/// button 34 above the glass sits in the home indicator.
struct OnboardingScreen<Content: View, Footer: View>: View {

    @Environment(\.fuelPalette) private var palette

    let topPadding: CGFloat
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        ZStack(alignment: .top) {
            palette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, topPadding)
            .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                footer
            }
            .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
            .padding(.bottom, FuelMetrics.Space.s34)
        }
    }
}

// MARK: - Eyebrow and headline

/// The tracked uppercase line above every onboarding headline.
struct OnboardingEyebrow: View {

    @Environment(\.fuelPalette) private var palette

    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .fuelStyle(FuelTypography.eyebrow)
            .foregroundStyle(palette.muted)
    }
}

// MARK: - Footer

/// The centred line above a footer button.
struct OnboardingFootnote: View {

    @Environment(\.fuelPalette) private var palette

    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .fuelStyle(FuelTypography.footnote)
            .foregroundStyle(palette.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.bottom, FuelMetrics.Space.s14)
    }
}

/// A full-width pill button.
///
/// The two variants differ by one point of padding — the filled one is drawn at
/// 18 and the outlined one at 17 — because the outline adds its own hairline on
/// each edge and the export keeps the two buttons the same height.
struct OnboardingButton: View {

    enum Style {
        case filled
        case outlined
    }

    @Environment(\.fuelPalette) private var palette

    let title: LocalizedStringKey
    var style: Style = .filled
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fuelStyle(FuelTypography.buttonLabel)
                .foregroundStyle(style == .filled ? palette.onAccent : palette.ink)
                .frame(maxWidth: .infinity)
                .padding(style == .filled ? FuelMetrics.Space.s18 : FuelMetrics.Space.s17)
                .background(background)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .filled:
            RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                .fill(palette.accentColor)
        case .outlined:
            RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
        }
    }
}

// MARK: - Selection dot

/// The radio dot on an onboarding choice card: accent-filled when chosen, a
/// ring in the heavier of the two line weights when it is not.
struct OnboardingSelectionDot: View {

    @Environment(\.fuelPalette) private var palette

    let isSelected: Bool

    var body: some View {
        Group {
            if isSelected {
                Circle().fill(palette.accentColor)
            } else {
                Circle().strokeBorder(palette.hair2, lineWidth: FuelMetrics.Line.selectionBorder)
            }
        }
        .frame(width: FuelMetrics.Control.selectionDot, height: FuelMetrics.Control.selectionDot)
        .fuelAnimation(FuelMotion.standard, value: isSelected)
    }
}

// MARK: - Hairline

/// The 1pt rule under the key field and between the two choice cards.
struct OnboardingHairline: View {

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.hair)
            .frame(height: FuelMetrics.Line.hairline)
    }
}
