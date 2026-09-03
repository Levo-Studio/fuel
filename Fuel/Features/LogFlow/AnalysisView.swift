import SwiftUI

// MARK: - Analysis

/// Screens 08 to 11: the frozen frame, dimmed, with a quarter-filled bar and
/// the current step over it.
///
/// **One screen rendered four times.** The export draws four frames, and the
/// only difference between them is how much of the 120×2 bar is painted and
/// which of the four labels sits under it. Building four views would be
/// building three copies of the same drawing.
///
/// It covers the whole flow rather than sitting inside `LogFlowScaffold`,
/// because the export gives it no tab bar and no cancel row — the `CANCEL`
/// under the bar is its own control, in its own place, in mono rather than in
/// the scaffold's eyebrow.
struct AnalysisView: View {

    let step: AnalysisStep

    /// The frame being analysed. `nil` in a preview, where the hatch the
    /// export itself draws stands in.
    let photo: UIImage?

    let onCancel: () -> Void

    var body: some View {
        AnalysisSurface(photo: photo) {
            VStack(alignment: .center, spacing: FuelMetrics.Progress.labelGap) {
                progressBar

                Text(CameraCopy.analysisStep(step))
                    .fuelStyle(FuelTypography.analysisStep)
                    .foregroundStyle(FuelPalette.Camera.ink)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(CameraCopy.analysisProgress(step)))
        } footer: {
            AnalysisAction(title: CameraCopy.analysisCancel, action: onCancel)
        }
    }

    // MARK: - Bar

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            FuelPalette.Camera.hairSoft

            FuelPalette.Camera.ink
                .frame(width: FuelMetrics.Progress.width * step.progress)
        }
        .frame(width: FuelMetrics.Progress.width, height: FuelMetrics.Progress.height)
        // Linear, because the bar stands in for elapsed time and an eased one
        // reads as a stalling one.
        .fuelAnimation(FuelMotion.progress, value: step)
    }
}

// MARK: - Failure

/// A scan that did not produce an estimate, in the same place the progress bar
/// sat.
///
/// **Not in the export.** The design draws the four analysis states and the
/// result, and nothing between them, so this is assembled from what those
/// screens already use: the same dimmed frame, the step label's own type for
/// the headline, and the `CANCEL` row's type for the actions. No provider
/// message reaches it — `AnalysisFailure` carries three cases and no text.
struct AnalysisFailureView: View {

    let failure: AnalysisFailure
    let photo: UIImage?
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        AnalysisSurface(photo: photo) {
            VStack(alignment: .center, spacing: FuelMetrics.Space.s8) {
                Text(CameraCopy.failureTitle(failure))
                    .fuelStyle(FuelTypography.analysisStep)
                    .foregroundStyle(FuelPalette.Camera.ink)

                Text(CameraCopy.failureHint(failure))
                    .fuelStyle(FuelTypography.hintWrapping)
                    .foregroundStyle(FuelPalette.Camera.muted)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
        } footer: {
            HStack(alignment: .center, spacing: FuelMetrics.Space.s24) {
                if let action = primaryAction {
                    AnalysisAction(title: action.title, action: action.perform)
                }

                AnalysisAction(title: CameraCopy.failureDismiss, action: onDismiss)
            }
        }
    }

    /// What the user can do about this failure, beyond leaving.
    ///
    /// An invalid key has none: the remedy is in Settings, and a second attempt
    /// with the same key would only spend another request to fail the same way.
    private var primaryAction: (title: String, perform: () -> Void)? {
        switch failure {
        case .invalidKey:
            nil
        case .noCredit(let billingPage):
            (CameraCopy.failureBilling, { openURL(billingPage) })
        case .retry:
            (CameraCopy.failureRetry, onRetry)
        }
    }
}

// MARK: - Shared surface

/// The frame every analysis state is drawn on: the captured photo, a scrim over
/// it, a block at the export's drop from the top, and a foot.
private struct AnalysisSurface<Content: View, Footer: View>: View {

    let photo: UIImage?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        ZStack {
            // The camera surface, the same token screen 07 sits on and the same
            // one `LogFlowScaffold` uses. It is what shows in the safe-area band
            // above the frozen frame and in the footer band below it, so it has
            // to be a surface — `placeholderBase` is a stop in the hatch
            // gradient and has no business being one.
            palette.camera
                .ignoresSafeArea()

            VStack(alignment: .center, spacing: .zero) {
                ZStack(alignment: .top) {
                    frozenFrame

                    // The scrim is what makes the bar and the label readable on
                    // any photograph, which is why it is a fixed camera ink
                    // rather than an opacity on the image.
                    FuelPalette.Camera.scrim

                    content()
                        .padding(.top, FuelMetrics.Progress.topOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                footer()
                    .padding(.top, FuelMetrics.Space.s20)
                    .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
                    .padding(.bottom, FuelMetrics.Space.s34)
            }
        }
    }

    private var frozenFrame: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                PhotoHatch(
                    base: FuelPalette.Camera.placeholderBase,
                    stripe: FuelPalette.Camera.placeholderStripe
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Foot control

/// The `CANCEL` under the bar, and the failure states' actions, which the
/// export gives the same mono, letter-spaced treatment.
private struct AnalysisAction: View {

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fuelStyle(FuelTypography.overlayAction)
                .foregroundStyle(FuelPalette.Camera.dim)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Analysis · state 2") {
    AnalysisView(step: .identifyingIngredients, photo: nil, onCancel: {})
}

#Preview("Analysis · no credit") {
    AnalysisFailureView(
        failure: .noCredit(billingPage: AIError.billingPage(for: .claude)),
        photo: nil,
        onRetry: {},
        onDismiss: {}
    )
}
