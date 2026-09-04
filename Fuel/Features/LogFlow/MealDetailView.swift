import SwiftUI

// MARK: - Meal detail

/// A meal that is already logged, on the screen the export draws for one that
/// is not.
///
/// **Everything above the footer is `MealResultView` unchanged** — screens 14
/// and 15 — with no leading footer control, because there is no estimate to
/// throw away, and, in the lede slot, whichever of the photograph or the
/// sentence this meal was logged with, or its own name where neither exists.
/// See `lede` for that rule and `MealDetailModel.photo` for why a meal can
/// lack both.
///
/// **The footer is this screen's own**, not `MealResultView`'s built-in one —
/// see `footer` for why and `MealResultView.commit` for the seam that lets it
/// opt out. Once the breakdown has changed it is the same full-width
/// `Re-analyse` pill the scan screens draw, reusing `MealResultPrimaryButton`
/// rather than a second copy of it. Otherwise it is `Delete`, small and in a
/// corner rather than the wide pill the export has no drawing for at all —
/// the owner's call, so it cannot be reached by an accidental tap the way a
/// footer-wide button can.
///
/// The analysis states and the failure state sit over the whole screen, the
/// way they do over the log flow, because the export gives them no chrome to
/// sit inside.
struct MealDetailView: View {

    let model: MealDetailModel

    /// `‹ Back`, and where a deleted meal leaves the user: Today.
    let onClose: () -> Void

    @Environment(\.fuelPalette) private var palette

    /// Whether the delete confirmation is up.
    ///
    /// It lives here rather than on the model for the reason the discard
    /// confirmation lives inside `MealResultView`: a confirmation is a thing
    /// the interface is showing, not a thing the meal is doing, and the model
    /// must not be able to reach a state where a meal is half-deleted.
    @State private var isConfirmingDelete = false

    /// Whether a re-analysis is running that the user has not called off.
    ///
    /// It exists because the two ways out of `.analysing` on this screen are
    /// the same case: an estimate that arrived returns to `.detail`, and so
    /// does a cancelled one. The log flow does not have this problem — its
    /// success is `.result` — so the flag lives here rather than being carried
    /// by the stage for everybody. Without it, calling a re-analysis off would
    /// be answered with the haptic for one that succeeded.
    @State private var isReanalysing = false

    var body: some View {
        ZStack {
            MealResultView(
                draft: model.draft,
                flowLabel: MealDetailCopy.flow,
                itemsHeading: MealDetailCopy.itemsHeading,
                onBack: onClose,
                onCycleLabel: cycleLabel,
                onToggleFavourite: model.toggleFavourite,
                onRemoveItem: model.removeItem,
                onEditItem: model.editItem,
                onAddItem: model.addItem,
                onReanalyse: model.reanalyse,
                // Nothing to discard: the meal is written down already, and the
                // screen draws no leading control at all.
                onDiscard: nil,
                discardConfirmation: MealDetailCopy.discardEditsConfirmation,
                // `nil` rather than a `Delete` action handed in the way the
                // scan screens hand in `Add`: this screen's footer is not the
                // filled full-width pill that value would draw, so drawing it
                // at all here would be a footer nobody can see built beneath
                // the one this screen actually shows. See `footer`.
                commit: nil,
                // The same slot `PhotoResultView`/`TextResultView` fill on the
                // scan screens, reusing their exact rendering: the photo for a
                // camera-mode meal, the sentence for a text-mode one. Neither
                // exists for a meal repeated from Recent or logged before
                // either was kept, so `MealTitleLede` keeps the slot from
                // opening on a gap — see `MealDetailModel.photo`.
                lede: { lede }
            )
            .safeAreaInset(edge: .bottom, spacing: .zero) { footer }

            switch model.stage {
            case .analysing(let step):
                // No frozen frame behind it: the request is about the item
                // list, and the meal's own photograph — if it had one — is not
                // kept past the flow that took it.
                AnalysisView(step: step, backdrop: .text, onCancel: cancelReanalysis)
            case .failed(let failure):
                AnalysisFailureView(
                    failure: failure,
                    backdrop: .text,
                    onRetry: model.retry,
                    onDismiss: model.dismissFailure
                )
            case .detail:
                EmptyView()
            }
        }
        // The platform's own confirmation, and deliberately the same one the
        // discard control uses on the scan screens: `confirmationDialog`, the
        // destructive verb in the role the platform draws destructive verbs in,
        // and a cancel that does nothing at all. The export draws no modal of
        // any kind, so a drawn one would be a second undrawn surface where iOS
        // already has the honest answer.
        .confirmationDialog(
            MealDetailCopy.deleteTitle,
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(MealDetailCopy.deleteConfirm, role: .destructive) { delete() }

            Button(MealDetailCopy.deleteCancel, role: .cancel) {}
        }
        // No `fuelBackSwipe` here, unlike Settings. This screen is pushed on
        // `RootShell`'s navigation stack rather than presented in a cover, so
        // it already has a real edge-swipe — the system's own interactive pop
        // — and a hand-built one beside it would be a second recogniser
        // answering the same drag. The discard confirmation a custom gesture
        // would have needed to route around is handled where the pop itself is
        // caught: `RootShell.mealDetailPath`, the one place that can intercept
        // it before the screen is gone.
        .onChange(of: model.stage) { previous, current in
            reportOutcome(from: previous, to: current)
        }
        .fuelAnimation(FuelMotion.emphasised, value: model.stage)
    }

    // MARK: - Lede

    /// What fills the slot screen 14 gives the photo and screen 15 gives the
    /// quote. Photo first, then the sentence, then the meal's own name — the
    /// order a meal can actually be in, since a stored entry has at most one
    /// of the two.
    @ViewBuilder
    private var lede: some View {
        if let photo = model.photo {
            MealPhotoLede(photo: photo)
        } else if let typedSentence = model.typedSentence {
            MealQuoteLede(text: typedSentence)
        } else {
            MealTitleLede(title: model.draft.title)
        }
    }

    // MARK: - Footer

    /// This screen's own footer, in `MealResultView`'s place for one —
    /// `commit: nil` above means it draws none.
    ///
    /// **Not one fixed shape.** Once the breakdown has changed there is a
    /// real request behind `Re-analyse`, worth the same full-width pill the
    /// scan screens spend on `Add`/`Re-analyse` — built from
    /// `MealResultPrimaryButton`, the same view they use, so the two cannot
    /// draw it differently by accident. `MealResultDraft.canReanalyse` is the
    /// exact condition `MealResultView.primaryAction` gates on internally;
    /// reading it again here is the one small price of drawing this outside
    /// that view rather than forking it.
    ///
    /// Otherwise the footer is `Delete`. **Deliberately not that pill** —
    /// there is no drawing for this screen at all, so nothing here is a
    /// deviation from a frame the export draws, only from the seam the two
    /// scan screens happen to share. A meal already sits in the store; the
    /// owner does not want the one control that removes it sitting where a
    /// scroll gone a fingerwidth too far, or a tap meant for the last
    /// breakdown row, can catch it. See `deleteCorner`.
    @ViewBuilder
    private var footer: some View {
        Group {
            if model.draft.canReanalyse {
                MealResultPrimaryButton(
                    action: MealResultAction(title: MealResultCopy.reanalyse, perform: model.reanalyse)
                )
            } else {
                deleteCorner
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
        .padding(.bottom, FuelMetrics.Space.s34)
        .fuelAnimation(FuelMotion.standard, value: model.draft.hasItemEdits)
    }

    /// `Delete`, small and in the leading corner.
    ///
    /// **Leading, not trailing — the same corner the discard control on the
    /// scan screens already claims for a control that throws something
    /// away**, so the app has one place a destructive control lives in a
    /// footer rather than two. It also keeps this control off the trailing
    /// edge, where every breakdown row's own remove mark already sits above
    /// it — a column a scroll that overshoots would otherwise carry a thumb
    /// straight through.
    ///
    /// **Sized at `Control.circleButton`, the 34pt circle Today's gear is
    /// already drawn at, floored at the same `Control.minimumHitTarget` every
    /// control in this app answers a finger within** — smaller than the pill
    /// it replaces, but not smaller than a finger, which is the difference
    /// between "harder to reach by accident" and "harder to reach". The
    /// overhang trick is the gear's own: the hit region grows past the drawn
    /// circle and a negative padding gives the layout its 34 back, so nothing
    /// else in the row moves for it.
    ///
    /// The trash glyph and the `ink` it is drawn in are `discardControl`'s own
    /// choices, reused rather than re-decided — the same mark means the same
    /// thing wherever this app draws it. `surface` behind it for the reason
    /// fix gave the same glyph a fill on the scan screens: an outlined circle
    /// with one small symbol in it and nothing else nearby reads as barely
    /// there, and a control this deliberately small cannot afford to also
    /// read as absent.
    private var deleteCorner: some View {
        Button {
            isConfirmingDelete = true
        } label: {
            Image(systemName: "trash")
                .fuelStyle(FuelTypography.iconGlyph)
                .foregroundStyle(palette.ink)
                .frame(width: FuelMetrics.Control.circleButton, height: FuelMetrics.Control.circleButton)
                .background {
                    Circle().fill(palette.surface)
                }
                .overlay {
                    Circle().strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
                }
                .frame(width: FuelMetrics.Control.minimumHitTarget, height: FuelMetrics.Control.minimumHitTarget)
                .contentShape(Rectangle())
                .padding(-FuelMetrics.Control.hitTargetOverhang(around: FuelMetrics.Control.circleButton))
        }
        .buttonStyle(FuelPressButtonStyle())
        .accessibilityLabel(Text(MealDetailCopy.delete))
    }

    // MARK: - Editing

    /// The label pill, which steps Breakfast → Lunch → Snack → Dinner and
    /// wraps.
    ///
    /// The one control on this screen that gets a haptic on the tap itself: it
    /// is a stepper through four values, and the click is what makes a stepper
    /// read as one. The favourite mark beside it does not, because a star that
    /// has just filled in has already said so.
    private func cycleLabel() {
        FuelHaptics.play(.selectionChanged)
        model.cycleLabel()
    }

    // MARK: - Re-analysing

    private func cancelReanalysis() {
        isReanalysing = false
        model.cancelReanalysis()
    }

    /// Answers a re-analysis that has finished, which is a wait of several
    /// seconds the user is entitled to look away from.
    private func reportOutcome(from previous: MealDetailModel.Stage, to current: MealDetailModel.Stage) {
        switch (previous, current) {
        // The two ways in, and not `(_, .analysing)`: that also matches the
        // step walker advancing from one analysis step to the next, which
        // re-arms the flag in the middle of a scan. Cancelling clears the flag
        // and then cancels, but the walker is a task of its own that stops a
        // moment later — long enough, if a step lands in between, for a
        // cancelled scan to arrive back at `.detail` armed and be answered with
        // the haptic for one that succeeded.
        case (.detail, .analysing), (.failed, .analysing):
            isReanalysing = true
        case (.analysing, .failed):
            isReanalysing = false
            FuelHaptics.play(.scanFailed)
        case (.analysing, .detail):
            guard isReanalysing else { return }
            isReanalysing = false
            FuelHaptics.play(.scanSucceeded)
        default:
            break
        }
    }

    // MARK: - Deleting

    /// A store that refused leaves the screen where it is, with the meal still
    /// on it — the same shape as a commit that could not write.
    ///
    /// The haptic sits after that guard rather than on the confirmation's
    /// button, so what is felt is the meal being gone rather than the dialog
    /// being answered.
    private func delete() {
        guard model.delete() else { return }
        FuelHaptics.play(.destructiveConfirmed)
        onClose()
    }
}

// MARK: - Preview

#Preview("A logged meal") {
    if let model = MealDetailPreviewData.model() {
        MealDetailView(model: model, onClose: {})
            .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
    }
}

#Preview("A logged meal, light") {
    if let model = MealDetailPreviewData.model() {
        MealDetailView(model: model, onClose: {})
            .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .green))
    }
}

// MARK: - Preview data

/// A meal in a store that lives for as long as the canvas does.
///
/// The figures are screen 14's, because this is screen 14 with a different
/// footer, and the meal has to be written down for the screen to have one to
/// open on.
private enum MealDetailPreviewData {

    /// `nil` only if SwiftData cannot open a container at all, which is a
    /// broken toolchain rather than a state a preview should try to draw.
    static func model() -> MealDetailModel? {
        guard
            let store = try? FuelStore(inMemory: true),
            let entry = try? store.log(
                title: "Salmon with polenta",
                kilocalories: 460,
                macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
                loggedAt: Date(),
                source: .photo,
                advice: "Plenty of protein and healthy fats. The plate is light on carbohydrate for an evening meal.",
                items: [
                    RecognisedItem(
                        name: "Salmon fillet, fried",
                        kilocalories: 240,
                        note: .photo(confidence: .confident, approximateGrams: 150)
                    ),
                    RecognisedItem(
                        name: "Polenta",
                        kilocalories: 150,
                        note: .photo(confidence: .confident, approximateGrams: 180)
                    ),
                    RecognisedItem(
                        name: "Leaf spinach",
                        kilocalories: 70,
                        note: .photo(confidence: .unsure, approximateGrams: 90)
                    ),
                ]
            )
        else {
            return nil
        }

        return MealDetailModel(
            entryID: entry.entryID,
            store: store,
            client: PreviewEstimator(),
            keys: PreviewKeys()
        )
    }
}

// MARK: - Stand-ins

/// Answers the key question without a Keychain, which a preview process has no
/// access group for.
private struct PreviewKeys: MealKeyPresence {

    func hasKey(for provider: AIProvider) -> Bool { true }
}

/// A client that makes no request. A preview that reached a provider would
/// spend the developer's credit every time the canvas refreshed.
private struct PreviewEstimator: AIClient {

    let provider: AIProvider = .claude

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .passed }

    func estimate(photo: MealPhoto) async throws -> MealEstimate { throw AIError.cancelled }

    func estimate(text: String) async throws -> MealEstimate { throw AIError.cancelled }
}
