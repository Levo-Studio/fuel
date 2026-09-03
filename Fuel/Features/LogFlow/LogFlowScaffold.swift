import SwiftUI

// MARK: - Scaffold

/// The chrome every log screen carries: the dark camera surface, the cancel
/// control top left, and the three-tab bar at the foot.
///
/// It is a container rather than a screen, because the export draws the same
/// three pieces around three different bodies — the viewfinder on screen 07,
/// the text field on screen 12, the Recent list on screen 13. A tab owns what
/// sits between the header and the bar and nothing else, which is what lets the
/// camera and text modes arrive later without touching this file.
///
/// The body is handed no horizontal inset. Screen 13 sits in
/// `logFlowHorizontalPadding` and screen 07's viewfinder is full-bleed, so the
/// inset belongs to the tab, not to the chrome.
struct LogFlowScaffold<Content: View, HeaderAccessory: View>: View {

    @Binding var selection: LogFlowTab

    let onCancel: () -> Void

    /// Drawn opposite the cancel control. Screen 07 puts the gallery button
    /// here and screens 12 and 13 leave the row empty, so the accessory is per
    /// tab rather than fixed.
    let headerAccessory: (LogFlowTab) -> HeaderAccessory

    let content: (LogFlowTab) -> Content

    @Environment(\.fuelPalette) private var palette

    init(
        selection: Binding<LogFlowTab>,
        onCancel: @escaping () -> Void,
        @ViewBuilder headerAccessory: @escaping (LogFlowTab) -> HeaderAccessory,
        @ViewBuilder content: @escaping (LogFlowTab) -> Content
    ) {
        self._selection = selection
        self.onCancel = onCancel
        self.headerAccessory = headerAccessory
        self.content = content
    }

    var body: some View {
        ZStack {
            // Dark in light mode too. Settings says so in words: a viewfinder
            // that turned white would wash out the preview it exists to show,
            // and the chrome over it has to stay legible on whatever the lens
            // is pointed at. Every ink below is therefore a fixed
            // `FuelPalette.Camera` value rather than the theme's.
            palette.camera
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: .zero) {
                LogFlowHeader(onCancel: onCancel) {
                    headerAccessory(selection)
                }

                content(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                LogFlowTabBar(selection: $selection)
            }
        }
    }
}

extension LogFlowScaffold where HeaderAccessory == EmptyView {

    init(
        selection: Binding<LogFlowTab>,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping (LogFlowTab) -> Content
    ) {
        self.init(selection: selection, onCancel: onCancel, headerAccessory: { _ in EmptyView() }, content: content)
    }
}

// MARK: - Header

/// The cancel control, and whatever the current tab puts opposite it.
private struct LogFlowHeader<Accessory: View>: View {

    let onCancel: () -> Void
    let accessory: () -> Accessory

    init(onCancel: @escaping () -> Void, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.onCancel = onCancel
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: .zero) {
            Button(action: onCancel) {
                Text(LogFlowCopy.cancel)
                    .fuelStyle(FuelTypography.eyebrow)
                    .foregroundStyle(FuelPalette.Camera.inkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LogFlowCopy.cancelLabel))

            // No minimum: the export draws the row `space-between`, and a
            // floor here would be a distance the design does not set at this
            // position.
            Spacer(minLength: .zero)

            accessory()
        }
        .padding(.top, FuelMetrics.Space.s22)
        .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
    }
}

// MARK: - Tab bar

/// Camera, Text, Recent — three equal columns under a hairline, exactly as the
/// export draws them.
private struct LogFlowTabBar: View {

    @Binding var selection: LogFlowTab

    var body: some View {
        HStack(alignment: .center, spacing: .zero) {
            // The columns are equal because the export writes
            // `repeat(3,1fr)`, not because three labels happen to measure the
            // same. `maxWidth: .infinity` on each is that rule, and it holds
            // when a translation makes one label longer.
            ForEach(LogFlowTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(LogFlowCopy.tabName(tab))
                        .fuelStyle(FuelTypography.tabLabel)
                        .foregroundStyle(tab == selection ? FuelPalette.Camera.ink : FuelPalette.Camera.inactive)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
        .fuelAnimation(FuelMotion.standard, value: selection)
        .padding(.top, FuelMetrics.Space.s14)
        .padding(.horizontal, FuelMetrics.Space.s24)
        .padding(.bottom, FuelMetrics.Space.s30)
        // Over the padded bounds, so the rule runs the full width of the bar
        // rather than only over the labels.
        .overlay(alignment: .top) {
            FuelPalette.Camera.divider
                .frame(height: FuelMetrics.Line.hairline)
        }
    }
}
