import Foundation

// MARK: - Preview data

/// The estimate screen 14 draws, so a preview shows the screen the design
/// shows.
///
/// The figures are the export's — 460 kcal, three macros, three recognised
/// items — and only the words are translated. The items still carry the notes
/// the export writes under them, because `RecognisedItem` still stores one and
/// a preview that dropped them would not be the export's data; the result
/// screen no longer draws that line. The
/// title is the export's own name for the meal even though screen 14 does not
/// print it, because the draft carries one and a placeholder here would be a
/// value nobody could check against the design.
///
/// Main-actor, like its neighbour `LogFlowPreviewData`: it builds a
/// `FuelStore`, which is.
enum CameraPreviewData {

    /// `nonisolated` so the stand-in client below, which is not on the main
    /// actor, can hand it back.
    nonisolated static let draft = MealResultDraft(
        title: "Salmon with polenta",
        kilocalories: 460,
        macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
        // Not in the export, which draws nothing in this place — a sample of
        // the kind of sentence a model returns, so the canvas shows the line at
        // the length it will usually be.
        advice: "Plenty of protein and healthy fats. The plate is light on carbohydrate for an evening meal.",
        items: [
            RecognisedItem(
                name: "Salmon fillet, pan-fried",
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
        ],
        label: .dinner,
        isLabelUserSet: false,
        isFavourite: false
    )

    /// A camera flow that never reaches a network and never opens a camera.
    ///
    /// `nil` only if SwiftData cannot open a container at all, which is a
    /// broken toolchain rather than a state a preview should try to draw.
    static func model(hasKey: Bool) -> CameraLogModel? {
        guard let store = try? FuelStore(inMemory: true) else { return nil }
        return CameraLogModel(
            store: store,
            client: PreviewEstimator(),
            camera: UnavailableCamera(),
            keys: PreviewKeys(hasKey: hasKey)
        )
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
        title: CameraPreviewData.draft.title,
        kilocalories: CameraPreviewData.draft.kilocalories,
        macros: CameraPreviewData.draft.macros,
        items: CameraPreviewData.draft.items
    )
}
