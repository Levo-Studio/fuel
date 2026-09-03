import Foundation

// MARK: - Provisional label

extension FuelStore {

    /// What a result screen shows on its label pill, unless the user overrules
    /// it.
    ///
    /// Derived through `MealLabeler` rather than restated, because the
    /// course-of-the-day rule has exactly one implementation and neither result
    /// screen may become a second one. The claimed set is what the day has
    /// already handed out.
    ///
    /// A read, not a write: the label the entry ends up with is the one
    /// `log(...)` derives for the whole day at commit time. This is the same
    /// rule asked the same question early, so the pill is not blank while the
    /// user decides.
    func provisionalLabel(at date: Date) -> MealLabel {
        let claimed = (try? nutritionEntries(on: date))?
            .reduce(into: Set<MealLabel>()) { $0.insert($1.label) } ?? []
        return MealLabeler(calendar: calendar).label(forEntryAt: date, claimedLabels: claimed)
    }
}
