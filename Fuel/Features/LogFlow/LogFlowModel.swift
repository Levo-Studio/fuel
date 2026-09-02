import Foundation

// MARK: - Model

/// What the log flow knows: which tab is showing, and the meals the Recent tab
/// offers.
///
/// It reaches the database and nothing else. There is no provider client here,
/// no Keychain read and no `URLRequest`, and that is the point of the Recent
/// tab: repeating a meal the user has already eaten is arithmetic Fuel has
/// stored, so it works before a key exists and it keeps working after one is
/// removed. The camera and text modes need a key; this one must never be made
/// to.
@Observable
final class LogFlowModel {

    /// Which of the three log modes is showing.
    var selectedTab: LogFlowTab

    private(set) var recentMeals: [RecentMeal] = []

    private let store: FuelStore

    /// When a tapped meal is logged. Injected so a test can put the entry at a
    /// chosen time of day and read the label the day rule gives it.
    private let now: () -> Date

    init(store: FuelStore, selectedTab: LogFlowTab = .camera, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.selectedTab = selectedTab
        self.now = now
    }

    // MARK: - Reading

    /// Rebuilds the Recent list from what has been logged so far.
    ///
    /// A failed read leaves the list as it was rather than emptying it. Screen
    /// 13 draws no error state, so the only two things the tab can say are
    /// "here is what you ate" and "nothing yet" — and claiming the second when
    /// the read merely failed would be a lie about the user's own history.
    func reload() {
        guard let entries = try? store.recentEntries(limit: RecentMeals.historyWindow) else { return }
        recentMeals = RecentMeals.list(from: entries.map(\.nutritionValue))
    }

    // MARK: - Logging

    /// Logs a meal again, at the current moment.
    ///
    /// The label is not set here and is not derived here either. `FuelStore.log`
    /// re-derives the whole day through `MealLabeler`, which is the one place
    /// the course-of-the-day rule lives; a second derivation at this call site
    /// would be a second rule to keep in step with the first.
    ///
    /// The `Bool` says whether the write happened, so the flow stays open on a
    /// failure instead of returning to Today as though something had been
    /// logged.
    @discardableResult
    func log(_ meal: RecentMeal) -> Bool {
        do {
            try store.log(
                title: meal.title,
                kilocalories: meal.kilocalories,
                macros: meal.macros,
                loggedAt: now(),
                source: .recent
            )
            return true
        } catch {
            return false
        }
    }
}
