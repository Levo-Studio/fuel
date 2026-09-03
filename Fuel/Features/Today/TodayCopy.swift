import Foundation

// MARK: - Copy

/// Every word and figure the Today screens print.
///
/// Nothing here holds English text: each entry names a key in
/// `Localizable.xcstrings`, which is where the words live. The screens are
/// drawn in German and the catalog carries the translation; only the words
/// change, never the geometry or the casing.
///
/// The formats that take a number go through `String(format:)` rather than
/// through an interpolated `LocalizedStringResource`, so the catalog key stays
/// the name of the thing (`today.total.goalSuffix`) instead of the name with a
/// format specifier stuck on the end.
nonisolated enum TodayCopy {

    // MARK: - Header

    static var title: String {
        String(localized: "today.title")
    }

    static var settingsLabel: String {
        String(localized: "today.settings.label")
    }

    static var addLabel: String {
        String(localized: "today.add.label")
    }

    // MARK: - Total

    static func goalSuffix(_ kilocalories: Int) -> String {
        String(format: String(localized: "today.total.goalSuffix"), kilocalories)
    }

    static var countOnlySuffix: String {
        String(localized: "today.total.countOnlySuffix")
    }

    static func percentage(_ percent: Int) -> String {
        String(format: String(localized: "today.ring.percentage"), percent)
    }

    /// What the ring is announced as. The drawn `68%` says nothing on its own
    /// once it is read out away from the figure it sits beside.
    static func ringAccessibilityLabel(_ percent: Int) -> String {
        String(format: String(localized: "today.ring.accessibilityLabel"), percent)
    }

    // MARK: - Macros

    static func macroName(_ macro: TodayMacro) -> String {
        switch macro {
        case .protein: String(localized: "today.macro.protein")
        case .carbs: String(localized: "today.macro.carbs")
        case .fat: String(localized: "today.macro.fat")
        }
    }

    /// The `118/160` at the end of a macro bar. Goal mode only.
    static func macroRatio(used: Int, goal: Int) -> String {
        String(format: String(localized: "today.macro.ratio"), used, goal)
    }

    /// The `118 g` under a macro name. Count-only mode only.
    static func macroGrams(_ grams: Int) -> String {
        String(format: String(localized: "today.macro.grams"), grams)
    }

    // MARK: - Day list

    static func mealHeading(_ label: MealLabel) -> String {
        switch label {
        case .breakfast: String(localized: "today.group.breakfast")
        case .lunch: String(localized: "today.group.lunch")
        case .snack: String(localized: "today.group.snack")
        case .dinner: String(localized: "today.group.dinner")
        }
    }

    static func groupKilocalories(_ kilocalories: Int) -> String {
        String(format: String(localized: "today.group.kilocalories"), kilocalories)
    }

    static func sourceName(_ source: EntrySource) -> String {
        switch source {
        case .photo: String(localized: "today.source.photo")
        case .text: String(localized: "today.source.text")
        case .recent: String(localized: "today.source.recent")
        }
    }

    /// The `08:14 · Photo` line under an entry's name.
    static func entryMeta(time: String, source: EntrySource) -> String {
        String(format: String(localized: "today.entry.meta"), time, sourceName(source))
    }

    // MARK: - Empty day

    // None of the copy below is in the export, which draws no empty state on
    // either Today screen. Every key carries that in its comment in the
    // catalog, so a reader who greps the screens for one of these lines and
    // finds nothing is told why before they go looking.

    static var gettingStartedHeading: String {
        String(localized: "today.gettingStarted.heading")
    }

    static func gettingStartedTitle(_ step: TodayGettingStartedStep) -> String {
        switch step {
        case .key: String(localized: "today.gettingStarted.key")
        case .goal: String(localized: "today.gettingStarted.goal")
        case .appearance: String(localized: "today.gettingStarted.appearance")
        case .firstMeal: String(localized: "today.gettingStarted.firstMeal")
        }
    }

    /// What a row's state is announced as. The check is drawn and its absence
    /// is drawn as nothing at all, so neither says anything out loud.
    static func gettingStartedState(isDone: Bool) -> String {
        isDone
            ? String(localized: "today.gettingStarted.state.done")
            : String(localized: "today.gettingStarted.state.notDone")
    }
}

// MARK: - Figures

/// The number formats the screens draw, which are not copy and so are not in
/// the catalog.
nonisolated enum TodayFormat {

    /// A bare figure. Grouping is off because the export draws `1640`, not
    /// `1,640`, and a separator appearing past a thousand kilocalories would
    /// change the width of the largest thing on the screen.
    static func figure(_ value: Int) -> String {
        value.formatted(.number.grouping(.never))
    }

    /// The locale the date above the title is built in.
    ///
    /// Pinned rather than taken from the device. The eyebrow is still formatted
    /// by a locale rather than reproduced from the export's German
    /// `Mi, 2. September`, because a date is not copy — but Fuel's interface is
    /// English and only English, and following the device put a German date on
    /// an English screen: `Thu 3. September`, whose ordinal dot after the day is
    /// a German form and which drops the comma the export draws after the
    /// weekday. `en` is the one localization the catalog carries.
    static let eyebrowLocale = Locale(identifier: "en")

    /// The date above the title, in the drawn field set: abbreviated weekday,
    /// day, wide month. Their order is the locale's business, so English reads
    /// `Thu, September 3` where the export reads `Mi, 2. September`.
    static func eyebrowDate(
        _ date: Date,
        locale: Locale = eyebrowLocale,
        timeZone: TimeZone = .current
    ) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, timeZone: timeZone)
                .weekday(.abbreviated)
                .day()
                .month(.wide)
        )
    }

    /// An entry's time, in the 24-hour clock the export draws.
    ///
    /// Verbatim rather than a locale-driven time style: `08:14` and `19:20` are
    /// drawn on the same screen, and a locale that renders a 12-hour clock
    /// would turn the second into `07:20` beside a dinner heading.
    static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
                timeZone: timeZone,
                calendar: Calendar(identifier: .gregorian)
            )
        )
    }
}
