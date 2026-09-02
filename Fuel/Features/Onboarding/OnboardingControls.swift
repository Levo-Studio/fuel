import SwiftUI

// MARK: - Screen frame

/// The shell all four onboarding screens sit in: the background, the drop from
/// the top of the frame, the 28pt side margin, and the footer pinned to the
/// bottom.
///
/// The two edges read the export differently, and they agree on hardware.
///
/// The top padding extends into the status-bar area. The export draws its own
/// mock status bar inside the 390×844 frame and measures every screen's first
/// line from the *frame* edge, so 88 and 96 are real distances from the top of
/// the screen; taken from the safe area instead they would push the headline
/// down by the height of a status bar iOS is already drawing for us.
///
/// The footer sits on the safe-area boundary with nothing added under it. The
/// export's `bottom:34px` is not a margin the designer wanted — 34pt is exactly
/// the iPhone's bottom safe inset, and the mockup has no home indicator, so he
/// drew by hand the clearance the device provides for free. Adding the drawn 34
/// on top of the inset would double it to about 68 on all four screens. Read
/// either way the button lands in the same place: 34pt up from the bottom of
/// the screen is the safe-area boundary.
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
            .ignoresSafeArea(.container, edges: .top)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                footer
            }
            .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
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
