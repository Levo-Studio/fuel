import Foundation

// MARK: - Copy

/// Every word the log flow's chrome and its Recent tab print.
///
/// Nothing here holds English text: each entry names a key in
/// `Localizable.xcstrings`, which is where the words live. The screens are
/// drawn in German and the catalog carries the translation; only the words
/// change, never the geometry, the casing or the colour.
///
/// The uppercase of the cancel control is *not* in the catalog value. It is
/// `text-transform: uppercase` in the export, which belongs to the text style —
/// `FuelTypography.eyebrow` applies it — so the same key stays readable and
/// reusable in its natural case.
nonisolated enum LogFlowCopy {

    // MARK: - Chrome

    static var cancel: String {
        String(localized: "logFlow.cancel")
    }

    /// The control drawn as `✕ Cancel`. VoiceOver gets the word without the
    /// glyph, which it would otherwise read out as a character name.
    static var cancelLabel: String {
        String(localized: "logFlow.cancel.label")
    }

    static func tabName(_ tab: LogFlowTab) -> String {
        switch tab {
        case .camera: String(localized: "logFlow.tab.camera")
        case .text: String(localized: "logFlow.tab.text")
        case .recent: String(localized: "logFlow.tab.recent")
        }
    }

    // MARK: - Recent

    static var recentTitle: String {
        String(localized: "logFlow.recent.title")
    }

    static var recentHint: String {
        String(localized: "logFlow.recent.hint")
    }

    /// The `P 32 · C 48 · F 9` line under a meal's name.
    ///
    /// One format rather than three interpolated figures, so the separators and
    /// the letters stay in the catalog where a translator can reach them.
    static func macroSummary(_ macros: MacroTotals) -> String {
        String(format: String(localized: "logFlow.recent.macros"), macros.protein, macros.carbs, macros.fat)
    }

    static var addGlyph: String {
        String(localized: "logFlow.recent.add.glyph")
    }

    /// What the row is worth, for VoiceOver. The drawn `420` says nothing on
    /// its own once it is read out away from the column it sits in.
    static func kilocaloriesValue(_ kilocalories: Int) -> String {
        String(format: String(localized: "logFlow.recent.kilocalories.value"), kilocalories)
    }

    static var logHint: String {
        String(localized: "logFlow.recent.add.hint")
    }
}

// MARK: - Figures

/// The number format the Recent rows draw, which is not copy and so is not in
/// the catalog.
nonisolated enum LogFlowFormat {

    /// A bare figure. Grouping is off because the export draws `680`, not
    /// `1,680`, and a separator appearing past a thousand kilocalories would
    /// change the width of the column the `+` glyphs line up against.
    static func figure(_ value: Int) -> String {
        value.formatted(.number.grouping(.never))
    }
}
