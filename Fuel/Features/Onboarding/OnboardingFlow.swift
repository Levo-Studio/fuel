import SwiftUI

// MARK: - Flow

/// Screens 01 to 04, in the order the export numbers them.
///
/// The four screens are one flow and not a navigation stack: there is no title
/// bar, no back chevron and no swipe-back drawn on any of them, and the only
/// ways backwards are the two footer buttons the design does draw. A
/// `NavigationStack` would add all three for free, which is why there is none.
struct OnboardingFlow: View {

    let model: OnboardingModel

    var body: some View {
        ZStack {
            switch model.stage {
            case .key:
                APIKeyScreen(model: model)
            case .keyTest:
                KeyTestScreen(model: model)
            case .goal:
                GoalScreen(model: model)
            }
        }
        .fuelAnimation(FuelMotion.emphasised, value: model.stage)
    }
}
