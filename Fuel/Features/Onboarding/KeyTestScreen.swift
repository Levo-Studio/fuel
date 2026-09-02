import SwiftUI

// MARK: - Screens 02 and 03

/// `02 · Key test runs automatically` and `03 · Key test passed`, plus the
/// failed state the design notes specify and the screens do not draw.
///
/// One view for all three, because they are one layout: the same eyebrow, the
/// same four rows, and a headline and footer button that change with the phase.
/// The test starts on its own — there is nothing to tap here while it runs
/// except the way back.
struct KeyTestScreen: View {

    @Environment(\.fuelPalette) private var palette

    let model: OnboardingModel

    var body: some View {
        OnboardingScreen(topPadding: FuelMetrics.Screen.keyTestTopPadding) {
            OnboardingEyebrow(text: model.provider.modelName)

            Text(headline)
                .fuelStyle(FuelTypography.displaySmall)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FuelMetrics.Space.s14)

            steps
                .padding(.top, FuelMetrics.Space.s44)
        } footer: {
            if let note {
                Text(note)
                    .fuelStyle(FuelTypography.footnote)
                    .foregroundStyle(palette.error)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, FuelMetrics.Space.s14)
            }
            footerButton
        }
        .fuelAnimation(FuelMotion.progress, value: model.completedSteps)
    }

    // MARK: - Phase copy

    private var headline: LocalizedStringKey {
        switch model.phase {
        case .running: "onboarding.keyTest.headline.running"
        case .passed: "onboarding.keyTest.headline.passed"
        case .failed: "onboarding.keyTest.headline.failed"
        }
    }

    /// The note under a failed test, in the error colour.
    ///
    /// Each failure gets its own sentence because the user's next move differs:
    /// a rejected key is retyped, an account with no credit is topped up, and a
    /// dropped connection is simply tried again. A single generic line would
    /// leave all three looking like the same mistake.
    private var note: LocalizedStringKey? {
        guard case .failed(let failure) = model.phase else { return nil }
        switch failure {
        case .format(let problem): return problem.note
        case .invalidKey: return "onboarding.keyTest.note.invalidKey"
        case .noCredit: return "onboarding.keyTest.note.noCredit"
        case .network: return "onboarding.keyTest.note.network"
        case .storageFailed: return "onboarding.keyTest.note.storageFailed"
        }
    }

    @ViewBuilder
    private var footerButton: some View {
        switch model.phase {
        case .running:
            OnboardingButton(title: "onboarding.cancel", style: .outlined) {
                model.returnToKeyEntry()
            }
        case .passed:
            OnboardingButton(title: "onboarding.continue") {
                model.continueFromKeyTest()
            }
        case .failed:
            OnboardingButton(title: "onboarding.keyTest.changeKey", style: .outlined) {
                model.returnToKeyEntry()
            }
        }
    }

    // MARK: - Steps

    private var steps: some View {
        VStack(spacing: 0) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                VStack(spacing: 0) {
                    HStack(spacing: FuelMetrics.Space.s14) {
                        KeyTestStepMarker(state: model.state(of: step))
                        Text(step.title)
                            .fuelStyle(isPending(step) ? FuelTypography.listTitlePending : FuelTypography.listTitle)
                            .foregroundStyle(isPending(step) ? palette.muted : palette.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, FuelMetrics.Space.s15)

                    Rectangle()
                        .fill(palette.hairSoft)
                        .frame(height: FuelMetrics.Line.hairline)
                }
            }
        }
    }

    private func isPending(_ step: OnboardingModel.Step) -> Bool {
        model.state(of: step) == .pending
    }
}

// MARK: - Step marker

/// The 20pt slot at the head of a step row.
///
/// One frame for all three states so the labels keep a single left edge
/// whatever the row is doing — which is the reason the export gives the slot a
/// size of its own rather than letting each marker size itself.
struct KeyTestStepMarker: View {

    @Environment(\.fuelPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: OnboardingModel.StepState

    /// Drives the spinner. Set once the row appears so the rotation starts from
    /// a fixed place rather than from wherever the previous row left it.
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            switch state {
            case .done:
                check
            case .active:
                spinner
            case .pending:
                Circle()
                    .fill(palette.soft)
                    .frame(width: FuelMetrics.Control.stepMarkerDot, height: FuelMetrics.Control.stepMarkerDot)
            }
        }
        .frame(width: FuelMetrics.Control.stepMarkerSlot, height: FuelMetrics.Control.stepMarkerSlot)
    }

    /// The done marker.
    ///
    /// The export draws it as an SVG path — `M4 10.5l4 4L16 6`, stroked at
    /// 1.7 inside the 20-unit slot — and neither those coordinates nor that
    /// stroke weight exist in `FuelMetrics`. Rather than write the numbers into
    /// a feature file or add them to the design layer unasked, this uses the
    /// system checkmark scaled to the slot. It is the one place in this flow
    /// where the drawn glyph is not reproduced exactly, and it is reported as a
    /// design-layer gap rather than left to be noticed.
    private var check: some View {
        Image(systemName: "checkmark")
            .resizable()
            .scaledToFit()
            .foregroundStyle(palette.ink)
    }

    /// The active marker: a ring in `soft` with a quarter of it in `ink`,
    /// turning.
    ///
    /// The quarter is what the export's `border-top-color` paints, and a full
    /// turn is a full turn — neither is a drawn measurement, so neither belongs
    /// in the design layer. The duration and the decision to run at all come
    /// from `FuelMotion`, so Reduce Motion is honoured in the one place it is
    /// honoured everywhere else.
    private var spinner: some View {
        ZStack {
            Circle()
                .strokeBorder(palette.soft, lineWidth: FuelMetrics.Line.spinner)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(palette.ink, lineWidth: FuelMetrics.Line.spinner)
                .padding(FuelMetrics.Line.spinner / 2)
        }
        .rotationEffect(.degrees(isSpinning ? 360 : 0))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(FuelMotion.resolve(FuelMotion.progress, reduceMotion: false)?.repeatForever(autoreverses: false)) {
                isSpinning = true
            }
        }
    }
}

// MARK: - Step copy

extension OnboardingModel.Step {

    var title: LocalizedStringKey {
        switch self {
        case .openingConnection: "onboarding.keyTest.step.connection"
        case .sendingTestRequest: "onboarding.keyTest.step.request"
        case .responseReceived: "onboarding.keyTest.step.response"
        case .modelReady: "onboarding.keyTest.step.model"
        }
    }
}

// MARK: - Format problem copy

extension APIKeyFormatVerdict.Problem {

    /// The sentence shown for a key the offline check rejected. Each one names
    /// what is wrong with the string the user typed, because that is what they
    /// can fix without spending a request to find out.
    var note: LocalizedStringKey {
        switch self {
        case .empty: "onboarding.keyTest.note.empty"
        case .containsWhitespace: "onboarding.keyTest.note.whitespace"
        case .tooShort: "onboarding.keyTest.note.tooShort"
        case .tooLong: "onboarding.keyTest.note.tooLong"
        case .missingAnthropicPrefix: "onboarding.keyTest.note.anthropicPrefix"
        }
    }
}
