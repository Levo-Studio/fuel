import Foundation
import SwiftData

// MARK: - Food entry

/// One logged meal.
///
/// The store is local and stays local: no `ModelConfiguration` here names a
/// CloudKit container, no property is marked for cloud encryption, and nothing
/// in Fuel syncs. There is no account to sync to, and that is the product
/// rather than a feature that has not happened yet.
@Model
final class FoodEntry {

    /// A stable identity that survives the boundary into the nutrition core.
    ///
    /// `persistentModelID` cannot: it is a SwiftData type, and nothing from
    /// SwiftData travels deeper than the hand-off value.
    var entryID: UUID

    var title: String
    var kilocalories: Int

    var proteinGrams: Int
    var carbGrams: Int
    var fatGrams: Int

    var loggedAt: Date

    /// Source and label are persisted as their raw strings rather than as
    /// enums, so the stored shape stays readable and stable when a case is
    /// added or renamed in code.
    var sourceRawValue: String
    var labelRawValue: String

    /// Set once the user picks the label by hand on the result screen. From
    /// then on the label is theirs and re-deriving the day leaves it alone.
    var isLabelUserSet: Bool

    /// Drawn as the ☆ / ★ control on the result screen.
    var isFavourite: Bool

    /// The breakdown shown under `Recognised` / `Broken down`.
    ///
    /// An entry logged straight from the Recent list carries the breakdown of
    /// the meal it repeats, item for item and figure for figure. Nothing is
    /// re-estimated on that path: the items were settled when the meal was
    /// first logged, and a repeat is the same plate.
    ///
    /// Empty only where nothing ever supplied one — an entry written before
    /// this property existed, or one whose source meal had no breakdown of its
    /// own.
    var items: [RecognisedItem]

    /// The compressed photo behind a camera-mode entry — the same bytes the
    /// scan itself sent, not a second compression of them.
    ///
    /// `nil` for a text-mode or Recent-mode entry, and `nil` for any entry
    /// logged before this property existed: the field is new and optional, so
    /// SwiftData loads an older row with nothing here rather than failing to
    /// load it. `MealDetailView` reads that absence and falls back to the
    /// meal's own name in the slot this would otherwise fill.
    var capturedPhotoData: Data?

    /// The sentence behind a text-mode entry, exactly as typed.
    ///
    /// `nil` for a camera-mode or Recent-mode entry, and `nil` for any entry
    /// logged before this property existed, for the same reason
    /// `capturedPhotoData` is.
    var typedSentence: String?

    /// The advisor line the estimate came with, so the meal detail screen draws
    /// the same sentence the result screen did.
    ///
    /// **Kept for the same reason the photo and the sentence are**, and the
    /// argument is the owner's own: what the screen showed when the meal was
    /// logged is what it should show when the meal is opened again. Deriving it
    /// a second time is not an option — it would mean a request, and a request
    /// spends the user's credit to be told something they have already read.
    ///
    /// `nil` for a meal repeated from the Recent list, for an estimate whose
    /// model left the field out, and for any entry logged before this property
    /// existed — optional and new, so SwiftData opens an older row with nothing
    /// here rather than failing to open it, exactly as `typedSentence` did.
    var advice: String?

    /// How sure the model was of the estimate this meal was logged from, as a
    /// whole percent — the score `MealResultView` draws on the meal detail
    /// screen.
    ///
    /// **Stored rather than derived from `items`, and the Recent list is why.**
    /// A meal repeated from the Recent list carries the breakdown of the meal
    /// it repeats, confidences and all, because those figures were settled the
    /// first time round. Deriving the meal's figure from that breakdown would
    /// print a percentage for an estimate that never ran — the model was not
    /// asked anything about this plate at this time. Writing the figure down
    /// when an estimate produces one, and leaving it alone otherwise, is what
    /// makes the absence say what it means.
    ///
    /// `nil` for a meal repeated from the Recent list, for an estimate whose
    /// model answered nothing readable, and for any entry logged before this
    /// property existed — optional and new, so SwiftData opens an older row
    /// with nothing here rather than failing to open it, exactly as `advice`
    /// and `typedSentence` did.
    var estimateConfidencePercent: Int?

    init(
        entryID: UUID = UUID(),
        title: String,
        kilocalories: Int,
        macros: MacroTotals,
        loggedAt: Date,
        source: EntrySource,
        label: MealLabel = .snack,
        isLabelUserSet: Bool = false,
        isFavourite: Bool = false,
        advice: String? = nil,
        estimateConfidencePercent: Int? = nil,
        items: [RecognisedItem] = [],
        capturedPhotoData: Data? = nil,
        typedSentence: String? = nil
    ) {
        self.entryID = entryID
        self.title = title
        self.kilocalories = kilocalories
        self.proteinGrams = macros.protein
        self.carbGrams = macros.carbs
        self.fatGrams = macros.fat
        self.loggedAt = loggedAt
        self.sourceRawValue = source.rawValue
        self.labelRawValue = label.rawValue
        self.isLabelUserSet = isLabelUserSet
        self.isFavourite = isFavourite
        self.advice = advice
        self.estimateConfidencePercent = estimateConfidencePercent
        self.items = items
        self.capturedPhotoData = capturedPhotoData
        self.typedSentence = typedSentence
    }

    // MARK: - Typed accessors

    var macros: MacroTotals {
        get { MacroTotals(protein: proteinGrams, carbs: carbGrams, fat: fatGrams) }
        set {
            proteinGrams = newValue.protein
            carbGrams = newValue.carbs
            fatGrams = newValue.fat
        }
    }

    /// A row written by an older build with a case this one no longer knows
    /// still has to appear in the list, so an unreadable value falls back
    /// rather than crashing.
    var source: EntrySource {
        get { EntrySource(rawValue: sourceRawValue) ?? .text }
        set { sourceRawValue = newValue.rawValue }
    }

    /// Snack is the safe fallback for the same reason, and the same reason it
    /// is what a new entry starts as before the day is derived: it is the
    /// label that claims nothing.
    var label: MealLabel {
        get { MealLabel(rawValue: labelRawValue) ?? .snack }
        set { labelRawValue = newValue.rawValue }
    }
}
