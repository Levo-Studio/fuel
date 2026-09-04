import Foundation

// MARK: - Preview data

/// The estimate screen 15 draws, so a preview shows the screen the design
/// shows.
///
/// The figures are the export's — 628 kcal, three macros, three items with
/// their amount lines, the favourite set — and only the words are translated.
/// The title is a name for the meal even though screen 15 does not print it,
/// because the draft carries one and it is what the day list would show.
///
/// Main-actor, like its neighbour `CameraPreviewData`: it builds a `FuelStore`,
/// which is.
enum TextPreviewData {

    /// The sentence the export draws in the field on screen 12 and quotes back
    /// on screen 15.
    nonisolated static let typedText = "2 eggs with 200g cottage cheese and polenta"

    nonisolated static let draft = MealResultDraft(
        title: "Eggs with cottage cheese and polenta",
        kilocalories: 628,
        macros: MacroTotals(protein: 47, carbs: 63, fat: 25),
        // Not in the export, which draws nothing in this place — a sample of
        // the kind of sentence a model returns, so the canvas shows the line at
        // the length it will usually be.
        advice: "Good protein for a breakfast. Light on fibre — a piece of fruit would round it out.",
        items: [
            RecognisedItem(name: "2 eggs", kilocalories: 158, note: .text(amount: .recognised)),
            RecognisedItem(name: "200g cottage cheese", kilocalories: 320, note: .text(amount: .recognised)),
            RecognisedItem(name: "Polenta", kilocalories: 150, note: .text(amount: .estimated)),
        ],
        label: .breakfast,
        isLabelUserSet: false,
        isFavourite: true
    )

    /// A text flow that never reaches a network.
    ///
    /// `nil` only if SwiftData cannot open a container at all, which is a
    /// broken toolchain rather than a state a preview should try to draw.
    static func model(hasKey: Bool) -> TextLogModel? {
        guard let store = try? FuelStore(inMemory: true) else { return nil }
        let model = TextLogModel(
            store: store,
            client: PreviewEstimator(),
            keys: PreviewKeys(hasKey: hasKey)
        )
        model.typedText = typedText
        return model
    }
}

// MARK: - Stand-ins

/// Answers the key question without a Keychain, which a preview process has no
/// access group for.
private struct PreviewKeys: MealKeyPresence {

    let hasKey: Bool

    func hasKey(for provider: AIProvider) -> Bool { hasKey }
}

/// A client that hands back the export's own estimate.
///
/// It makes no request. A preview that reached a provider would spend the
/// developer's credit every time the canvas refreshed.
private struct PreviewEstimator: AIClient {

    let provider: AIProvider = .claude

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .passed }

    func estimate(photo: MealPhoto, context: String?) async throws -> MealEstimate { Self.estimate }

    func estimate(text: String) async throws -> MealEstimate { Self.estimate }

    /// No conversation either. The canvas has nothing to adjust and no credit
    /// to spend doing it.
    func adjust(
        _ meal: AdjustableMeal,
        history: [MealChatTurn],
        message: String
    ) -> AsyncThrowingStream<MealChatEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: AIError.cancelled) }
    }

    private static let estimate = MealEstimate(
        title: TextPreviewData.draft.title,
        kilocalories: TextPreviewData.draft.kilocalories,
        macros: TextPreviewData.draft.macros,
        items: TextPreviewData.draft.items
    )
}
