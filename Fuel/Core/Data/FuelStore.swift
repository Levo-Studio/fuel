import Foundation
import SwiftData

// MARK: - Store

/// Owns the `ModelContainer` and is the only place features reach the
/// database.
///
/// It is deliberately thin. Everything that can go wrong in arithmetic or in
/// the meal-label rule lives in `Nutrition/`, on plain values, so it can be
/// tested without a container; this type's whole job is to fetch, to write, and
/// to convert at the boundary.
@MainActor
final class FuelStore {

    let container: ModelContainer

    /// Decides which day an entry belongs to. Injected for the same reason the
    /// labeler takes one.
    var calendar: Calendar

    private var context: ModelContext { container.mainContext }

    private var labeler: MealLabeler { MealLabeler(calendar: calendar) }

    /// Both models and nothing else. No CloudKit container is named and none
    /// will be: Fuel has no account, so there is nowhere to sync to.
    static let schema = Schema([FoodEntry.self, GoalSettings.self])

    init(inMemory: Bool = false, calendar: Calendar = .current) throws {
        let configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: inMemory)
        self.container = try ModelContainer(for: Self.schema, configurations: configuration)
        self.calendar = calendar
    }

    // MARK: - Reading a day

    /// One calendar day's entries, oldest first.
    func entries(on day: Date) throws -> [FoodEntry] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.loggedAt >= start && $0.loggedAt < end },
            sortBy: [SortDescriptor(\.loggedAt)]
        )
        return try context.fetch(descriptor)
    }

    /// The same day as plain values. This is the boundary: past this call
    /// nothing knows that SwiftData exists.
    func nutritionEntries(on day: Date) throws -> [NutritionEntry] {
        try entries(on: day).map(\.nutritionValue)
    }

    /// Whether anything has ever been logged, on any day.
    ///
    /// Deliberately not "today has an entry". It answers whether the user has
    /// ever used the app to log a meal, which is a thing that happens once and
    /// stays true; a reading scoped to the current day would come back false
    /// again every midnight.
    ///
    /// One row is enough to answer it, so the fetch is limited to one rather
    /// than counting a store that grows for the life of the app.
    func hasAnyEntry() throws -> Bool {
        var descriptor = FetchDescriptor<FoodEntry>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    /// When the oldest stored meal was logged, or `nil` when nothing has ever
    /// been logged.
    ///
    /// It is the far end of what Today can be browsed back to. Days older than
    /// this are not days the user forgot to log — they are days before Fuel had
    /// anything to say about them, and paging into them would be a walk with no
    /// end and nothing in it.
    ///
    /// The instant rather than the day, because the day depends on a calendar
    /// and this file already holds one that a caller may not share. Whoever
    /// asks decides which day this instant falls in.
    ///
    /// One row answers it, so the fetch is limited to one rather than sorting a
    /// store that grows for the life of the app — the same shape `hasAnyEntry`
    /// uses, for the same reason.
    func earliestEntryDate() throws -> Date? {
        var descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.loggedAt)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.loggedAt
    }

    /// The most recently logged entries, newest first, for the Recent tab.
    func recentEntries(limit: Int) throws -> [FoodEntry] {
        var descriptor = FetchDescriptor<FoodEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// The most recently logged entries the user marked as a favourite, newest
    /// first, for the Recent tab's second list.
    ///
    /// A fetch of its own rather than a filter over `recentEntries(limit:)`. A
    /// favourite is a meal the user asked to keep, so one starred before the
    /// last `limit` meals were logged has to still be in the list; filtering
    /// that window would quietly drop it the moment enough other meals were
    /// logged on top of it.
    func favouriteEntries(limit: Int) throws -> [FoodEntry] {
        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.isFavourite },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// One stored meal, by the identity that survives the boundary.
    ///
    /// `entryID` rather than `persistentModelID`, because the identity a screen
    /// is opened on came out of a `NutritionEntry` — the only shape of an entry
    /// anything outside this file has — and `persistentModelID` is a SwiftData
    /// type that deliberately never travels that far.
    func entry(withID id: UUID) throws -> FoodEntry? {
        var descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.entryID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Writing an entry

    /// Logs a meal, then re-derives the labels of the day it lands in.
    ///
    /// The entry is inserted before it has a meaningful label because the
    /// labeler decides the whole day at once. `loggedAt` is an arbitrary date,
    /// so an entry can land behind ones already stored; deriving only from
    /// "the day so far" would hand it a meal a later entry already holds.
    @discardableResult
    func log(
        title: String,
        kilocalories: Int,
        macros: MacroTotals,
        loggedAt: Date,
        source: EntrySource,
        isFavourite: Bool = false,
        advice: String? = nil,
        estimateConfidencePercent: Int? = nil,
        items: [RecognisedItem] = [],
        capturedPhotoData: Data? = nil,
        typedSentence: String? = nil
    ) throws -> FoodEntry {
        let entry = FoodEntry(
            title: title,
            kilocalories: kilocalories,
            macros: macros,
            loggedAt: loggedAt,
            source: source,
            isFavourite: isFavourite,
            advice: advice,
            estimateConfidencePercent: estimateConfidencePercent,
            items: items,
            capturedPhotoData: capturedPhotoData,
            typedSentence: typedSentence
        )
        context.insert(entry)
        try context.save()
        try relabelDay(containing: loggedAt)
        return entry
    }

    /// Runs the day through the labeler and writes the result back.
    ///
    /// Entries the user labelled by hand are passed through untouched — the
    /// labeler holds their meal against the others and returns them unchanged,
    /// and the write below skips them as well, so a correction cannot be lost
    /// to a rounding of the rule on either side.
    private func relabelDay(containing date: Date) throws {
        let rows = try entries(on: date)
        let labels = labeler
            .relabelling(rows.map(\.nutritionValue))
            .reduce(into: [UUID: MealLabel]()) { $0[$1.id] = $1.label }
        for row in rows where !row.isLabelUserSet {
            guard let label = labels[row.entryID], label != row.label else { continue }
            row.label = label
        }
        try context.save()
    }

    /// Applies the user's own choice from the result screen. The entry is
    /// marked as theirs from here on, so nothing re-derives it back.
    func overrideLabel(_ label: MealLabel, on entry: FoodEntry) throws {
        entry.label = label
        entry.isLabelUserSet = true
        try context.save()
        // The meal the user just claimed may be held twice now, so the rest of
        // the day is derived again around their choice.
        try relabelDay(containing: entry.loggedAt)
    }

    func setFavourite(_ isFavourite: Bool, on entry: FoodEntry) throws {
        entry.isFavourite = isFavourite
        try context.save()
    }

    /// Puts a fresh estimate over a meal that is already stored.
    ///
    /// **In place, rather than a delete and a new row.** The identity is what
    /// the screen showing the meal was opened on and what anything holding the
    /// meal refers to, so replacing the row would leave that screen pointed at
    /// nothing. It would also cost the entry its place in the day: `log`
    /// re-derives the whole day's labels around a new arrival, and a meal that
    /// held breakfast could come back as a snack because the row it lost was
    /// the one holding the meal.
    ///
    /// **`loggedAt` and `source` are deliberately not arguments.** A meal was
    /// eaten when it was eaten, and re-pricing it is not a second meal; the day
    /// it belongs to and its `08:14 · Photo` line are the same as before. That
    /// is also why nothing is relabelled here — the label is derived from the
    /// time, and the time has not moved.
    /// **`advice` is written rather than left alone, and it has no default.**
    /// It is part of what the screen shows about a meal, so a caller that
    /// re-priced one has to say what the line now reads — including saying it
    /// is gone. A defaulted `nil` would erase it on every caller that forgot,
    /// and a parameter left out of this signature would strand it on a meal
    /// whose figures no longer match it.
    ///
    /// **`estimateConfidencePercent` is the same argument about a number.** It
    /// describes the estimate the meal's figures came from, so a caller that
    /// replaced those figures has to say how sure the model is of the new ones
    /// — including saying it does not know. Left out, a meal re-priced from a
    /// reply that answered nothing readable would keep the old estimate's
    /// percentage over a set of numbers it was never about.
    func update(
        _ entry: FoodEntry,
        title: String,
        kilocalories: Int,
        macros: MacroTotals,
        advice: String?,
        estimateConfidencePercent: Int?,
        items: [RecognisedItem]
    ) throws {
        entry.title = title
        entry.kilocalories = kilocalories
        entry.macros = macros
        entry.advice = advice
        entry.estimateConfidencePercent = estimateConfidencePercent
        entry.items = items
        try context.save()
    }

    /// Throws a meal away, then re-derives the labels of the day it left.
    ///
    /// The relabelling is not housekeeping. Breakfast, lunch and dinner are
    /// each handed out once a day, so a day whose only breakfast is deleted has
    /// the meal free again — and the entry that was a snack because breakfast
    /// was taken is a breakfast now. Leaving the day underived would show a
    /// morning with no breakfast group and a snack in its place.
    func delete(_ entry: FoodEntry) throws {
        let day = entry.loggedAt
        context.delete(entry)
        try context.save()
        try relabelDay(containing: day)
    }

    // MARK: - Goal and counting mode

    /// The stored settings, or `nil` when onboarding has not been answered yet.
    func existingGoalSettings() throws -> GoalSettings? {
        var descriptor = FetchDescriptor<GoalSettings>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The settings row, created with the defaults if it is not there yet.
    ///
    /// The name says "creating" because the create is not an implementation
    /// detail: the row existing is what marks onboarding as answered, so a
    /// screen that only wanted to read the goal would end onboarding by asking.
    @discardableResult
    func goalSettingsCreatingIfNeeded() throws -> GoalSettings {
        if let existing = try existingGoalSettings() { return existing }
        let settings = GoalSettings()
        context.insert(settings)
        try context.save()
        return settings
    }

    /// How the Today screen should read. Before onboarding has run there is no
    /// row, and goal mode with the defaults is what onboarding itself opens on.
    func countingMode() throws -> CountingMode {
        try existingGoalSettings()?.mode ?? .goal(.default)
    }

    /// The four targets as stored, whichever mode the user is in.
    ///
    /// `countingMode()` cannot answer this: in count-only mode it returns a
    /// case that carries no targets, which is the point of the type. The
    /// numbers are still on the row — `GoalSettings` keeps them so switching
    /// back in Settings returns the user's own goal rather than the defaults —
    /// and this is how a caller reads them without unwrapping a mode that is
    /// deliberately empty. Before onboarding has run there is no row, and the
    /// defaults are what onboarding itself opens on.
    func storedTargets() throws -> DailyTargets {
        try existingGoalSettings()?.targets ?? .default
    }

    func setCountingMode(_ mode: CountingMode) throws {
        let settings = try goalSettingsCreatingIfNeeded()
        settings.mode = mode
        try context.save()
    }
}

// MARK: - Boundary

extension FoodEntry {

    /// The hand-off value. Line items and the favourite flag stay behind: the
    /// nutrition core has no use for either, and what it cannot see it cannot
    /// come to depend on.
    ///
    /// The accuracy figure stays behind with them. It was carried here while
    /// the score stood on a day-list row; the owner has since put it on the
    /// meal detail screen alone, which reads the entry itself, so the nutrition
    /// core would be holding a field nothing asks it for.
    var nutritionValue: NutritionEntry {
        NutritionEntry(
            id: entryID,
            title: title,
            kilocalories: kilocalories,
            macros: macros,
            loggedAt: loggedAt,
            source: source,
            label: label,
            isLabelUserSet: isLabelUserSet
        )
    }

    /// The hand-off value the Recent list reads.
    ///
    /// A second value at the same boundary rather than a widening of the first.
    /// The Recent list repeats a meal whole — its line items included, so the
    /// figures the user accepted come back rather than being estimated a second
    /// time — and the items are exactly what `nutritionValue` leaves behind.
    /// Adding them there would hand the nutrition core a field it has no use
    /// for; see `RecentEntry`.
    ///
    /// **The confidences do not come with them, and that is the same omission
    /// the photo and the typed sentence get.** A row's figures are facts about
    /// a food and repeat with it; a confidence is the record of one particular
    /// act of estimating, and a repeat estimates nothing — no model is asked
    /// anything about this plate at this time. Carrying them would let the
    /// repeated meal average them back into an accuracy figure and present it
    /// as the model's opinion of a request that was never made. Stripped here,
    /// at the boundary, so nothing downstream has to remember to.
    var recentValue: RecentEntry {
        RecentEntry(
            id: entryID,
            title: title,
            kilocalories: kilocalories,
            macros: macros,
            items: items.map { item in
                var repeated = item
                repeated.confidence = nil
                return repeated
            }
        )
    }
}
