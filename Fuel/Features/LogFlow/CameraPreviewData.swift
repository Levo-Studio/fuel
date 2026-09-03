import Foundation

// MARK: - Preview data

/// The estimate screen 14 draws, so a preview shows the screen the design
/// shows.
///
/// The figures are the export's — 460 kcal, three macros, three recognised
/// items with their confidence lines — and only the words are translated. The
/// title is the export's own name for the meal even though screen 14 does not
/// print it, because the draft carries one and a placeholder here would be a
/// value nobody could check against the design.
nonisolated enum CameraPreviewData {

    static let draft = PhotoResultDraft(
        title: "Salmon with polenta",
        kilocalories: 460,
        macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
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
}
