import SwiftUI

// MARK: - Counting section

/// The first section of screen 17: the two-segment counting control, and in
/// goal mode the four target rows under it.
///
/// The rows are hidden in count-only mode rather than emptied. The design draws
/// the section only in goal mode — count-only has nothing to show against — and
/// the numbers behind them stay exactly as the user left them, so switching
/// back returns their goal instead of the defaults.
struct CountingSection: View {

    @Bindable var model: CountingSettingsModel

    var body: some View {
        SettingsSection(titleKey: "settings.section.counting") {
            SettingsSegmentedControl(
                options: CountingChoice.allCases,
                titleKey: \.settingsSegmentTitle,
                selection: $model.choice
            )
            .padding(.top, FuelMetrics.Space.s16)

            if model.choice == .withGoal {
                ForEach(GoalTarget.allCases, id: \.self) { target in
                    GoalTargetRow(model: model, target: target)
                }
            }
        }
        .fuelAnimation(FuelMotion.standard, value: model.choice)
    }
}

// MARK: - Target row

/// A target's name on the left and its value, right-aligned, on the right.
private struct GoalTargetRow: View {

    @Environment(\.fuelPalette) private var palette

    let model: CountingSettingsModel
    let target: GoalTarget

    /// What is in the field.
    ///
    /// A `String` rather than a binding to the number, for the reason the
    /// onboarding field states: an `Int` binding cannot hold an empty field, so
    /// clearing one to retype it would either snap back to the old number under
    /// the user's hands or be stored as a goal of zero.
    @State private var draft: String = ""

    @FocusState private var isEditing: Bool

    var body: some View {
        SettingsRow(
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            showsHairline: target != GoalTarget.allCases.last
        ) {
            Text(target.settingsRowTitle)
                .fuelStyle(FuelTypography.itemTitle)
                .foregroundStyle(palette.ink)

            Spacer(minLength: FuelMetrics.Space.s12)

            // The title is empty and the field is named for VoiceOver
            // separately: `TextField(_:text:)` draws its title as the
            // placeholder whenever the field is empty, and the export draws no
            // placeholder on these rows — it draws a number.
            TextField("", text: $draft)
                .accessibilityLabel(Text(target.settingsRowTitle))
                .fixedSize()
                .focused($isEditing)
                .keyboardType(.numberPad)
                .fuelStyle(FuelTypography.settingsValue)
                .foregroundStyle(palette.ink)
                .tint(palette.accentColor)
                .onChange(of: draft) { _, typed in
                    let digits = GoalFieldInput.digits(in: typed)
                    if digits != typed { draft = digits }
                    model.setValue(from: digits, for: target)
                }
        }
        // The field keeps its intrinsic width so the number sits where the
        // export draws it, which leaves the row as the thing that takes the
        // tap — the same arrangement the onboarding goal field uses. Without
        // it the only target is the digits themselves, and a field the user
        // cleared has no target at all.
        .contentShape(Rectangle())
        .onTapGesture { isEditing = true }
        .onAppear { draft = String(model.value(for: target)) }
        .onChange(of: isEditing) { _, editing in
            // Every one of these rows draws a number in the export, so a field
            // left empty is put back to what it stands for. The model kept the
            // value while the field was blank, so this is the user's own
            // figure returning rather than a default overwriting an edit.
            if !editing && draft.isEmpty {
                draft = String(model.value(for: target))
            }
        }
    }

    /// The export draws the calorie row with more room above it than the three
    /// under it, because it is the first row after the control rather than one
    /// of a run.
    private var topPadding: CGFloat {
        target == .calories ? FuelMetrics.Space.s14 : FuelMetrics.Space.s12
    }

    private var bottomPadding: CGFloat {
        target == .calories ? FuelMetrics.Space.s10 : FuelMetrics.Space.s12
    }
}
