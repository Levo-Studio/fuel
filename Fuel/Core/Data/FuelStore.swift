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

    /// The most recently logged entries, newest first, for the Recent tab.
    func recentEntries(limit: Int) throws -> [FoodEntry] {
        var descriptor = FetchDescriptor<FoodEntry>(
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    // MARK: - Writing an entry

    /// Logs a meal and derives its label from what the day has already been
    /// handed.
    @discardableResult
    func log(
        title: String,
        kilocalories: Int,
        macros: MacroTotals,
        loggedAt: Date,
        source: EntrySource,
        isFavourite: Bool = false,
        items: [RecognisedItem] = []
    ) throws -> FoodEntry {
        let sameDay = try nutritionEntries(on: loggedAt)
        let entry = FoodEntry(
            title: title,
            kilocalories: kilocalories,
            macros: macros,
            loggedAt: loggedAt,
            source: source,
            label: labeler.label(forEntryAt: loggedAt, existing: sameDay),
            isFavourite: isFavourite,
            items: items
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    /// Applies the user's own choice from the result screen. The entry is
    /// marked as theirs from here on, so nothing re-derives it back.
    func overrideLabel(_ label: MealLabel, on entry: FoodEntry) throws {
        entry.label = label
        entry.isLabelUserSet = true
        try context.save()
    }

    func setFavourite(_ isFavourite: Bool, on entry: FoodEntry) throws {
        entry.isFavourite = isFavourite
        try context.save()
    }

    // MARK: - Goal and counting mode

    /// The stored settings, or `nil` when onboarding has not been answered yet.
    func existingGoalSettings() throws -> GoalSettings? {
        var descriptor = FetchDescriptor<GoalSettings>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The settings row, created with the defaults if it is not there yet.
    @discardableResult
    func goalSettings() throws -> GoalSettings {
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

    func setCountingMode(_ mode: CountingMode) throws {
        let settings = try goalSettings()
        settings.mode = mode
        try context.save()
    }
}

// MARK: - Boundary

extension FoodEntry {

    /// The hand-off value. Line items and the favourite flag stay behind: the
    /// nutrition core has no use for either, and what it cannot see it cannot
    /// come to depend on.
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
}
