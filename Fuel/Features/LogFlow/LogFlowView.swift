import SwiftUI

// MARK: - Log flow

/// The log flow: the chrome from screen 07 around whichever of the three modes
/// is selected.
///
/// Only Recent is built. The camera and text tabs select and draw their empty
/// bodies, so the bar is honest about how many modes there are while the two
/// that need a key and a capture session are still to come — see
/// `LogFlowPlaceholder`.
struct LogFlowView: View {

    @Bindable var model: LogFlowModel

    /// Leaves the flow without logging anything — the `✕ Cancel` control.
    let onCancel: () -> Void

    /// A meal was logged and the flow is done. Recent returns to Today on the
    /// tap itself; there is no result screen in this mode, because nothing was
    /// estimated.
    let onLogged: () -> Void

    var body: some View {
        LogFlowScaffold(selection: $model.selectedTab, onCancel: onCancel) { tab in
            switch tab {
            case .camera:
                LogFlowPlaceholder()
            case .text:
                LogFlowPlaceholder()
            case .recent:
                RecentMealsView(meals: model.recentMeals, onLog: log)
            }
        }
        .onAppear { model.reload() }
    }

    private func log(_ meal: RecentMeal) {
        guard model.log(meal) else { return }
        onLogged()
    }
}

// MARK: - Placeholder

/// What the camera and text tabs draw until they are built.
///
/// Deliberately empty rather than a message: the camera mode's body is the live
/// viewfinder (screen 07) and the text mode's is the entry field and its
/// `Analyse` button (screen 12), and neither has a designed loading or
/// unavailable state that this could stand in for. An invented placeholder
/// would be a screen the export does not contain.
///
/// The camera agent replaces the `.camera` arm above with its viewfinder and
/// hands the scaffold a `headerAccessory` for screen 07's gallery button; the
/// text agent replaces the `.text` arm. Neither needs to change the scaffold,
/// the tab bar or this file's neighbours.
private struct LogFlowPlaceholder: View {

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Recent") {
    if let model = LogFlowPreviewData.model(showing: .recent) {
        LogFlowView(model: model, onCancel: {}, onLogged: {})
            .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
    }
}

#Preview("Camera placeholder") {
    if let model = LogFlowPreviewData.model(showing: .camera) {
        LogFlowView(model: model, onCancel: {}, onLogged: {})
            .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .green))
    }
}
