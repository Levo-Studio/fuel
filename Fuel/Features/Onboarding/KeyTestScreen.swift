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

    /// The done marker, as the export draws it.
    ///
    /// A system checkmark stood here while `FuelMetrics` had no stroke weight
    /// for a drawn glyph. It has one now, and the design layer's rule is that
    /// a glyph drawn as a path is built from the path: a symbol's weight is a
    /// design of its own and would not have matched, and a symbol scaled to
    /// fill the slot is half again the size of the drawn mark, which spans only
    /// x 4→16 and y 6→14.5 of the twenty.
    private var check: some View {
        KeyTestCheck()
            .stroke(
                palette.ink,
                style: StrokeStyle(
                    lineWidth: FuelMetrics.Line.Glyph.check,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
    }

    /// The active marker: a ring in `soft` with `Line.spinnerArc` of it in
    /// `ink`, turning.
    ///
    /// A full turn is a full turn rather than a measurement, so that one stays
    /// here; the arc the export paints is a drawn value and lives in the design
    /// layer with the stroke it belongs to.
    ///
    /// The `reduceMotion` guard is not a design-layer bypass and is meant to
    /// come out. `FuelMotion` has no representation for a *repeating*
    /// animation: `progress` reduces to a cross-fade, and `.repeatForever` on a
    /// 0.15s linear curve spins faster rather than stopping — the opposite of
    /// what the user asked for. Until `FuelMotion` can say "this one does not
    /// repeat when motion is reduced", the flag is read here and only here.
    private var spinner: some View {
        ZStack {
            Circle()
                .strokeBorder(palette.soft, lineWidth: FuelMetrics.Line.spinner)
            Circle()
                .trim(from: 0, to: FuelMetrics.Line.spinnerArc)
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

// MARK: - Check glyph

/// The check the export draws on a completed step: `d="M4 10.5l4 4L16 6"`.
///
/// The three points are the path's own coordinates in the export's twenty-unit
/// glyph box, which is why they sit here rather than in `FuelMetrics` — they
/// describe the shape of a mark, not a distance in the app's layout, and the
/// design layer says as much where it supplies the box and the stroke and
/// leaves the path to the call site. Scaled by the frame so the glyph follows
/// its slot instead of assuming the two are the same size.
private struct KeyTestCheck: Shape {

    private static let points: [CGPoint] = [
        CGPoint(x: 4, y: 10.5),
        CGPoint(x: 8, y: 14.5),
        CGPoint(x: 16, y: 6)
    ]

    nonisolated func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / FuelMetrics.Line.Glyph.viewBox
        var path = Path()
        for (position, point) in Self.points.enumerated() {
            let scaled = CGPoint(x: point.x * scale, y: point.y * scale)
            if position == 0 {
                path.move(to: scaled)
            } else {
                path.addLine(to: scaled)
            }
        }
        return path
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
