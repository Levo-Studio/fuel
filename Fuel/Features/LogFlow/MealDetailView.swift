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

    /// Whether the conversation sheet is up.
    ///
    /// It lives here for the reason the delete confirmation does: what is
    /// presented is a thing the interface is showing, not a thing the meal is
    /// doing. The conversation itself is on the model, so closing the sheet
    /// keeps it.
    @State private var isTalking = false

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
            .mealResultFooter { footer }

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
        // **The platform's own presentation, at the platform's own large
        // detent.** The owner asked for a sheet that rises to near the top of
        // the screen and named iOS's standard behaviour for it; the export
        // draws no sheet of any kind, so the honest answer to "what does it
        // look like coming up" is the one the system already has. Nothing
        // about the rise, the corner, the dimming or the swipe is Fuel's.
        //
        // The grabber is asked for explicitly: at `.large` the system does not
        // draw one by default, and the sheet's own `Done` should not be the
        // only thing that says this can be put away.
        .sheet(isPresented: $isTalking) {
            MealChatSheet(
                model: model.chat,
                mealTitle: model.draft.title,
                onClose: { isTalking = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .environment(\.fuelPalette, palette)
        }
        // The system's own interactive pop, and not `fuelBackSwipe` — this
        // screen is pushed on `RootShell`'s navigation stack rather than
        // presented in a cover, so the platform already has the gesture and a
        // hand-built one beside it would be a second recogniser answering the
        // same drag. What it needed was not to be armed but to be let through:
        // the breakdown below is a scroll view from edge to edge, and neither
        // of the platform's two back gestures — the leading-edge pan, and the
        // mid-content one iOS 26 added — had a failure requirement with it, so
        // a horizontal drag became a scroll on a list with nowhere sideways to
        // go. `FuelInteractivePop` states both requirements the recognisers
        // were missing and says at length why they are stated the way they are,
        // including what the second one costs a vertical scroll on this screen.
        //
        // The discard confirmation the gesture would otherwise walk straight
        // through is handled where the pop is caught rather than here:
        // `RootShell.mealDetailPath`, the one place that can intercept it
        // before the screen is gone.
        .fuelInteractivePop()
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
    /// Otherwise the footer is two small corner controls: `Delete` leading and
    /// the conversation trailing. **Deliberately not that pill** — there is no
    /// drawing for this screen at all, so nothing here is a deviation from a
    /// frame the export draws, only from the seam the two scan screens happen
    /// to share. A meal already sits in the store; the owner does not want the
    /// one control that removes it sitting where a scroll gone a fingerwidth
    /// too far, or a tap meant for the last breakdown row, can catch it. See
    /// `deleteCorner`, and `chatCorner` for the one opposite it.
    ///
    /// **Both go when the pill comes**, which is the same rule stated once:
    /// while the breakdown carries edits nobody has priced, the only thing
    /// this footer offers is the request that prices them.
    ///
    /// Where it stands is not this screen's to decide: the inset from the sides
    /// and from the bottom edge is `mealResultFooter`'s, the same ground the
    /// scan screens' footer rests on.
    @ViewBuilder
    private var footer: some View {
        Group {
            if model.draft.canReanalyse {
                MealResultPrimaryButton(
                    action: MealResultAction(title: MealResultCopy.reanalyse, perform: model.reanalyse)
                )
            } else {
                HStack(alignment: .center, spacing: FuelMetrics.Space.s10) {
                    deleteCorner
                    Spacer(minLength: FuelMetrics.Space.s10)
                    chatCorner
                }
            }
        }
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
    /// **That second argument is why `chatCorner` may stand in the column this
    /// one avoids.** What it protects against is a destructive tap arriving by
    /// accident; the control opposite opens a sheet, which an accidental tap
    /// puts away again, and which spends nothing until a message is sent.
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

    /// The control that opens the conversation, in the trailing corner.
    ///
    /// **Not in the export**, which draws no second corner control and no chat
    /// to put behind one. The owner asked for it here, mirroring the delete
    /// mark opposite, and it is the same drawing as that mark down to the
    /// circle, the fill, the hairline and the hit region — only the glyph and
    /// the corner differ. A second recipe for one small circular control would
    /// be a second place its size could drift from the first.
    ///
    /// **Trailing, which is the column `deleteCorner` argues for staying out
    /// of**, and the argument does not carry across: that one is about a
    /// destructive tap arriving by accident from an overshot scroll. This tap
    /// opens a sheet. Dismissing it costs nothing, and nothing is sent until
    /// something has been typed and the send mark pressed.
    ///
    /// **It is drawn only where `Delete` is**, which is to say only when the
    /// footer is not the `Re-analyse` pill, and that is a rule rather than a
    /// convenience: while the breakdown carries edits nobody has priced, the
    /// figures on the screen belong to a meal that no longer exists, and a
    /// conversation about how much of it there was would be a conversation
    /// about the wrong plate. The user prices their edits first, and then the
    /// meal is a meal again.
    private var chatCorner: some View {
        Button {
            isTalking = true
        } label: {
            Image(systemName: "bubble.left")
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
        .accessibilityLabel(Text(MealChatCopy.open))
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
                // Derived rather than written down, so the canvas cannot show a
                // score the rows under it do not add up to. The percentages are
                // `CameraPreviewData`'s, which is where the reasoning for them
                // is: screen 14's own three rows, chosen to sit either side of
                // the two words the export draws on them.
                estimateConfidencePercent: EstimateConfidence.percent(
                    of: CameraPreviewData.items.map(\.confidence)
                ),
                items: CameraPreviewData.items
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

    func estimate(photo: MealPhoto, context: String?) async throws -> MealEstimate { throw AIError.cancelled }

    func estimate(text: String) async throws -> MealEstimate { throw AIError.cancelled }

    /// No conversation either. The canvas has nothing to adjust and no credit
    /// to spend doing it.
    func adjust(
        _ meal: AdjustableMeal,
        history: [MealChatTurn],
        message: String
    ) -> AsyncThrowingStream<MealChatEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: AIError.cancelled) }
    }
}
