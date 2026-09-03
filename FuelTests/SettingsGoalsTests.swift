import Foundation
import SwiftUI
import Testing

@testable import Fuel

// MARK: - Suite

/// The second half of Settings: the counting mode, the four targets, and the
/// three label rows.
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

    // MARK: - The three label rows

    /// The keys the three rows carry, in the drawn order. Named once here
    /// because both label tests want them and the second one has to resolve
    /// them: `LocalizedStringKey` hands its own key back to nobody.
    private static let drawnWindowKeys = [
        "settings.labels.breakfast.window",
        "settings.labels.lunch.window",
        "settings.labels.dinner.window"
    ]

    @Test("the label rows are the drawn three, in the drawn order")
    func labelRowsAreAsDrawn() {
        #expect(SettingsLabelRow.drawn.map(\.id) == ["breakfast", "lunch", "dinner"])
        #expect(SettingsLabelRow.drawn.map(\.titleKey) == [
            "settings.labels.breakfast",
            "settings.labels.lunch",
            "settings.labels.dinner"
        ])
        let windowKeys: [LocalizedStringKey] = Self.drawnWindowKeys.map { LocalizedStringKey($0) }
        #expect(SettingsLabelRow.drawn.map(\.windowKey) == windowKeys)
    }

    /// The guard that keeps the rows from being "simplified" into a projection
    /// of the labelling rule.
    ///
    /// The export's own snack row used to make that impossible by accident —
    /// four drawn rows against three main meals, so a count settled it. The
    /// snack row is gone on the owner's instruction, the counts now match, and
    /// counting proves nothing. What still separates the two is the text: the
    /// rows print the windows the export drew, and the rule reaches past two of
    /// them. A list derived from the labeler would print the reaches instead,
    /// and both halves of this test would go red.
    @Test("the drawn windows are the export's, not the reach the rule runs by")
    func labelRowsAreNotTheRule() throws {
        #expect(Self.drawnWindowKeys.map(catalogValue) == [
            "04:00 – 10:59",
            "11:00 – 14:59",
            "18:00 – 22:59"
        ])

        // Read out of the rule rather than restated, so a rule that changed
        // cannot take this expectation along with it.
        let reaches = try MainMeal.inDayOrder.map(reachText)
        #expect(reaches == ["04:00 – 10:59", "11:00 – 17:59", "18:00 – 23:59"])

        // The same three divergences by name, so a rule change reads here as
        // more than a shifted string. Lunch reaches through the gap the removed
        // snack row used to claim, dinner reaches to the end of the calendar
        // day, and the small hours claim no main meal at all.
        #expect(MainMeal.claimable(atMinuteOfDay: 16 * 60) == .lunch)
        #expect(MainMeal.claimable(atMinuteOfDay: 23 * 60 + 30) == .dinner)
        #expect(MainMeal.claimable(atMinuteOfDay: 2 * 60) == nil)
    }

    // MARK: - Reading the two sides

    /// What a catalog key resolves to. The guard above is about the text the
    /// user reads, not about which key produced it.
    private func catalogValue(_ key: String) -> String {
        String(localized: .init(stringLiteral: key))
    }

    /// How far a meal actually reaches, in the `HH:mm – HH:mm` shape the rows
    /// print. The reach is contiguous, so its first and last claimed minute are
    /// its ends.
    private func reachText(of meal: MainMeal) throws -> String {
        let claimed = (0 ..< 24 * 60).filter { MainMeal.claimable(atMinuteOfDay: $0) == meal }
        let first = try #require(claimed.first)
        let last = try #require(claimed.last)
        return "\(clock(first)) – \(clock(last))"
    }

    private func clock(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }
}
