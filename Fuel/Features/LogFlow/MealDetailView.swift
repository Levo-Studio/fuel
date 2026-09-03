import SwiftUI

// MARK: - Meal detail

/// A meal that is already logged, on the screen the export draws for one that
/// is not.
///
/// **There is no second drawing here.** It is `MealResultView` — screens 14 and
/// 15 — with three things handed to it and nothing added: no leading footer
/// control, because there is no estimate to throw away; `Delete` where `Add`
/// sits; and no lede, because a stored meal has neither the photograph screen
/// 14 puts above the label pill nor the sentence screen 15 does. Everything
/// from the pill down is the same drawing, including the rule that turns the
/// footer into `Re-analyse` once the breakdown has been changed.
///
/// The analysis states and the failure state sit over the whole screen, the
/// way they do over the log flow, because the export gives them no chrome to
/// sit inside.
struct MealDetailView: View {

    let model: MealDetailModel

    /// `‹ Back`, and where a deleted meal leaves the user: Today.
    let onClose: () -> Void

    /// Whether the delete confirmation is up.
    ///
    /// It lives here rather than on the model for the reason the discard
    /// confirmation lives inside `MealResultView`: a confirmation is a thing
    /// the interface is showing, not a thing the meal is doing, and the model
    /// must not be able to reach a state where a meal is half-deleted.
    @State private var isConfirmingDelete = false

    var body: some View {
        ZStack {
            MealResultView(
                draft: model.draft,
                flowLabel: MealDetailCopy.flow,
                itemsHeading: MealDetailCopy.itemsHeading,
                onBack: onClose,
                onCycleLabel: model.cycleLabel,
                onToggleFavourite: model.toggleFavourite,
                onRemoveItem: model.removeItem,
                onEditItem: model.editItem,
                onAddItem: model.addItem,
                onReanalyse: model.reanalyse,
                // Nothing to discard: the meal is written down already, and the
                // screen draws no leading control at all.
                onDiscard: nil,
                discardConfirmation: MealDetailCopy.discardEditsConfirmation,
                commit: MealResultAction(
                    title: MealDetailCopy.delete,
                    perform: { isConfirmingDelete = true }
                ),
                // A stored meal has no photograph and no typed sentence. What
                // the export puts above the label pill belongs to the flow that
                // produced the estimate, and this screen is not in one.
                lede: { EmptyView() }
            )

            switch model.stage {
            case .analysing(let step):
                // No frozen frame behind it: the request is about the item
                // list, and the meal's own photograph — if it had one — is not
                // kept past the flow that took it.
                AnalysisView(step: step, backdrop: .text, onCancel: model.cancelReanalysis)
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
        // The second way back to Today, for a thumb that reaches for the edge
        // before it reaches for the corner. `‹ Back` stays the drawn control
        // and nothing is added to the screen to advertise this one.
        //
        // **It is off the moment there is something to lose.** `MealResultView`
        // puts a confirmation in front of `‹ Back` once the breakdown has been
        // changed, and a gesture that skipped it would put back exactly the bug
        // that confirmation exists to fix — item edits thrown away without a
        // question. The confirmation belongs to that view and cannot be reached
        // from here, so with edits pending this offers nothing and the drawn
        // control, which asks, is the only way out. The analysis and failure
        // states are excluded for the plainer reason that they draw their own
        // cancel over the whole screen.
        .fuelBackSwipe(
            isEnabled: model.stage == .detail && !model.draft.hasItemEdits,
            perform: onClose
        )
        .fuelAnimation(FuelMotion.emphasised, value: model.stage)
    }

    // MARK: - Deleting

    /// A store that refused leaves the screen where it is, with the meal still
    /// on it — the same shape as a commit that could not write.
    private func delete() {
        guard model.delete() else { return }
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
