import Foundation
import SwiftUI
import Testing

@testable import Fuel

// MARK: - Suite

/// The second half of Settings: the counting mode, the four targets, and the
/// four label rows.
@Suite("Settings counting and labels")
@MainActor
struct SettingsGoalsTests {

    // MARK: - Fixtures

    /// In memory, so a suite run leaves nothing behind and two tests running at
    /// once cannot see each other's goal.
    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true)
    }

    /// A defaults suite of the test's own. The counting state does not belong
    /// in `UserDefaults` at all — one test below says so — and this is what
    /// lets it say it without reading the machine's real plist.
    private func makeDefaults() -> (suite: String, defaults: UserDefaults) {
        let suite = "apps.levo-studio.Fuel.tests.settings.goals.\(UUID().uuidString)"
        return (suite, UserDefaults(suiteName: suite)!)
    }

    // MARK: - Opening the screen

    @Test("an untouched screen opens on the goal segment and the design's defaults")
    func opensOnTheDefaults() throws {
        let model = try CountingSettingsModel(store: try makeStore())

        #expect(model.choice == .withGoal)
        #expect(model.targets == .default)
        #expect(model.value(for: .calories) == 2400)
        #expect(model.value(for: .protein) == 160)
        #expect(model.value(for: .carbs) == 240)
        #expect(model.value(for: .fat) == 70)
    }

    @Test("opening Settings does not end onboarding")
    func openingWritesNothing() throws {
        let store = try makeStore()

        _ = try CountingSettingsModel(store: store)

        // The row existing is what marks onboarding as answered, so a screen
        // that created one by being looked at would answer for the user.
        #expect(try store.existingGoalSettings() == nil)
    }

    /// The same invariant one step further along, where it was actually broken.
    ///
    /// Constructing the model writes nothing, but the rows do not stop there:
    /// each one seeds its text field from the model when it appears, and the
    /// field's change handler cannot tell that seed from a keystroke. Four rows
    /// therefore hand the model back its own numbers on every appearance, and a
    /// setter that stored them would create the `GoalSettings` row — which is
    /// what marks onboarding as answered. Opening Settings to read a goal must
    /// not answer the question for the user.
    @Test("the rows seeding their fields does not end onboarding")
    func seedingTheFieldsWritesNothing() throws {
        let store = try makeStore()
        let model = try CountingSettingsModel(store: store)

        for target in GoalTarget.allCases {
            model.setValue(from: String(model.value(for: target)), for: target)
        }

        #expect(try store.existingGoalSettings() == nil)
        #expect(model.targets == .default)
    }

    // MARK: - Switching modes

    @Test("switching to count-only and back keeps the four numbers")
    func countOnlyKeepsTheNumbers() throws {
        let store = try makeStore()
        let model = try CountingSettingsModel(store: store)
        model.setValue(from: "2100", for: .calories)
        model.setValue(from: "150", for: .protein)
        model.setValue(from: "210", for: .carbs)
        model.setValue(from: "80", for: .fat)

        model.choice = .countOnly
        model.choice = .withGoal

        #expect(model.targets == DailyTargets(kilocalories: 2100, protein: 150, carbs: 210, fat: 80))
        #expect(try store.storedTargets() == model.targets)
        #expect(try store.countingMode() == .goal(model.targets))
    }

    @Test("the numbers survive count-only across a fresh screen")
    func countOnlySurvivesReopening() throws {
        let store = try makeStore()
        let first = try CountingSettingsModel(store: store)
        first.setValue(from: "1800", for: .calories)
        first.choice = .countOnly

        // What the next launch does: a new model over the same store.
        let second = try CountingSettingsModel(store: store)

        #expect(second.choice == .countOnly)
        #expect(second.value(for: .calories) == 1800)
        #expect(try store.countingMode() == .countOnly)
    }

    // MARK: - Editing a target

    @Test("an edited target is written through the store")
    func editingWritesThrough() throws {
        let store = try makeStore()
        let model = try CountingSettingsModel(store: store)

        model.setValue(from: "2750", for: .calories)
        model.setValue(from: "185", for: .protein)

        #expect(try store.storedTargets().kilocalories == 2750)
        #expect(try store.storedTargets().protein == 185)
        #expect(try store.countingMode().targets?.kilocalories == 2750)
    }

    @Test("a cleared field keeps the value it had", arguments: GoalTarget.allCases)
    func clearingKeepsThePreviousValue(target: GoalTarget) throws {
        let store = try makeStore()
        let model = try CountingSettingsModel(store: store)
        let before = model.value(for: target)

        // Clearing a field to retype it must not mean a target of nothing for
        // those few keystrokes, and the export draws no state for one.
        model.setValue(from: "", for: target)

        #expect(model.value(for: target) == before)
        #expect(before > 0)
        #expect(try store.storedTargets()[keyPath: target.keyPath] == before)
    }

    @Test("anything that is not a digit never reaches a target")
    func nonDigitsAreDropped() throws {
        let model = try CountingSettingsModel(store: try makeStore())

        model.setValue(from: "2,100 kcal", for: .calories)

        #expect(model.value(for: .calories) == 2100)
    }

    @Test("the goal is not kept in UserDefaults")
    func theGoalIsNotAPreference() throws {
        let (suite, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SettingsPreferences(defaults: defaults)
        preferences.theme = .light
        let model = try CountingSettingsModel(store: try makeStore())

        model.setValue(from: "2750", for: .calories)
        model.choice = .countOnly

        // The three preferences are presentation state and belong in a plist;
        // the goal is the user's own data and belongs in the store. A screen
        // holding both must not blur the two.
        #expect(defaults.string(forKey: SettingsPreferences.Key.theme) == FuelTheme.light.rawValue)
        #expect(!defaults.dictionaryRepresentation().values.contains { ($0 as? Int) == 2750 })
    }

    // MARK: - The four label rows

    @Test("the label rows are the drawn four, in the drawn order")
    func labelRowsAreAsDrawn() {
        #expect(SettingsLabelRow.drawn.map(\.id) == ["breakfast", "lunch", "snack", "dinner"])
        #expect(SettingsLabelRow.drawn.map(\.windowKey) == [
            "settings.labels.breakfast.window",
            "settings.labels.lunch.window",
            "settings.labels.snack.window",
            "settings.labels.dinner.window"
        ])
    }

    /// The rows are drawn copy and the rule is something else, so the two are
    /// expected to disagree — and this test fails the moment somebody "fixes"
    /// the rows by deriving them from the labeler, because a derived list
    /// cannot hold a snack window at all.
    @Test("the rows are drawn copy rather than a projection of the labelling rule")
    func labelRowsAreNotTheRule() {
        // A snack row is drawn at 15:00 – 17:59, and no code reads a snack
        // window: 16:00 on a day with no lunch yet is lunch.
        #expect(MainMeal.claimable(atMinuteOfDay: 16 * 60) == .lunch)

        // The dinner row stops at 22:59; dinner's reach runs to the end of the
        // calendar day.
        #expect(MainMeal.claimable(atMinuteOfDay: 23 * 60 + 30) == .dinner)

        // No row says anything about the small hours, which are always a snack.
        #expect(MainMeal.claimable(atMinuteOfDay: 2 * 60) == nil)

        // And the shape does not match either: three meals own a window, four
        // rows are drawn.
        #expect(SettingsLabelRow.drawn.count == MainMeal.allCases.count + 1)
    }
}
