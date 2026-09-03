import SwiftUI

// MARK: - Backdrop

/// What an analysis state is drawn over, and by the same token which log mode
/// is being waited on.
///
/// The export draws the four analysis screens over the frozen photo, because
/// the only mode that had run by screen 08 is the camera one. The bar, the
/// step labels and the `CANCEL` under them say nothing about a photograph —
/// they describe the work — so the text mode walks the same four states with
/// nothing behind them but the surface screen 12 already sits on. What the
/// export does not draw is a picture where there is none.
enum AnalysisBackdrop {

    /// The camera mode: the frame being analysed. `nil` in a preview, where
    /// the hatch the export itself draws stands in.
    case photo(UIImage?)

    /// The text mode, which has no picture to freeze.
    case text

    var mode: AILogMode {
        switch self {
        case .photo: .photo
        case .text: .text
        }
    }
}

// MARK: - Analysis

/// Screens 08 to 11: a quarter-filled bar and the current step, over whatever
/// the backdrop puts behind them — the frozen frame, dimmed, after a photo;
/// the bare camera surface after a typed sentence.
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

    let backdrop: AnalysisBackdrop

    let onCancel: () -> Void

    var body: some View {
        AnalysisSurface(backdrop: backdrop) {
            VStack(alignment: .center, spacing: FuelMetrics.Progress.labelGap) {
                progressBar

                Text(AnalysisCopy.step(step))
                    .fuelStyle(FuelTypography.analysisStep)
                    .foregroundStyle(FuelPalette.Camera.ink)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(AnalysisCopy.progress(step)))
        } footer: {
            AnalysisAction(title: AnalysisCopy.cancel, action: onCancel)
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
/// screens already use: the same backdrop, the step label's own type for the
/// headline, and the `CANCEL` row's type for the actions. No provider message
/// reaches it — `AnalysisFailure` carries three cases and no text, and the one
/// thing the mode changes is which of two hints is printed.
struct AnalysisFailureView: View {

    let failure: AnalysisFailure
    let backdrop: AnalysisBackdrop
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        AnalysisSurface(backdrop: backdrop) {
            VStack(alignment: .center, spacing: FuelMetrics.Space.s8) {
                Text(AnalysisCopy.failureTitle(failure))
                    .fuelStyle(FuelTypography.analysisStep)
                    .foregroundStyle(FuelPalette.Camera.ink)

                Text(AnalysisCopy.failureHint(failure, mode: backdrop.mode))
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

                AnalysisAction(title: AnalysisCopy.failureDismiss, action: onDismiss)
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
            (AnalysisCopy.failureBilling, { openURL(billingPage) })
        case .retry:
            (AnalysisCopy.failureRetry, onRetry)
        }
    }
}

// MARK: - Shared surface

/// What every analysis state is drawn on: the backdrop, a block at the
/// export's drop from the top, and a foot.
private struct AnalysisSurface<Content: View, Footer: View>: View {

    let backdrop: AnalysisBackdrop
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
                    // The text mode has nothing to freeze and nothing to dim:
                    // both the frame and the scrim over it belong to the
                    // photograph, and drawing the hatch without one would claim
                    // a picture that was never taken.
                    if case .photo(let photo) = backdrop {
                        frozenFrame(photo)

                        // The scrim is what makes the bar and the label
                        // readable on any photograph, which is why it is a
                        // fixed camera ink rather than an opacity on the image.
                        FuelPalette.Camera.scrim
                    }

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

    private func frozenFrame(_ photo: UIImage?) -> some View {
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
    AnalysisView(step: .identifyingIngredients, backdrop: .photo(nil), onCancel: {})
}

#Preview("Analysis · state 2 after text") {
    AnalysisView(step: .identifyingIngredients, backdrop: .text, onCancel: {})
}

#Preview("Analysis · no credit") {
    AnalysisFailureView(
        failure: .noCredit(billingPage: AIError.billingPage(for: .claude)),
        backdrop: .photo(nil),
        onRetry: {},
        onDismiss: {}
    )
}
