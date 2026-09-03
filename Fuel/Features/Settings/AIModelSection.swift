import SwiftUI

// MARK: - AI model section

/// The first section of screen 16: the provider control, the key field, and the
/// key test.
///
/// There is no networking in this file and none in this folder. `model` asks a
/// `KeyValidating` for an outcome and draws it; where that outcome comes from
/// is `Core/AI/`'s business.
struct AIModelSection: View {

    @Environment(\.fuelPalette) private var palette

    @Bindable var preferences: SettingsPreferences
    @Bindable var model: APIKeySettingsModel

    var body: some View {
        SettingsSection(
            titleKey: "settings.section.aiModel",
            topSpacing: FuelMetrics.Space.s22
        ) {
            SettingsSegmentedControl(
                options: AIProvider.allCases,
                titleKey: \.settingsSegmentTitle,
                selection: $preferences.provider,
                padding: FuelMetrics.Space.s11
            )
            .padding(.top, FuelMetrics.Space.s14)
            .onChange(of: preferences.provider) {
                model.providerChanged()
            }

            keyRow

            testRow
        }
    }

    // MARK: - Key row

    /// The stored key is never read back into this field.
    ///
    /// The export draws a filled-in `sk-ant-a1b2…` because it is a render of a
    /// form, not of a stored secret. Reading a key out of the Keychain to show
    /// a truncated version of it would put the start of the real key on screen,
    /// which is exactly the sort of "only a prefix" leak the BYOK rules rule
    /// out. So the row draws the design's own placeholder whether or not a key
    /// is stored, and typing replaces it.
    private var keyRow: some View {
        SettingsRow(
            topPadding: FuelMetrics.Space.s14,
            bottomPadding: FuelMetrics.Space.s10
        ) {
            Text("settings.apiKey.label")
                .fuelStyle(FuelTypography.itemTitle)
                .foregroundStyle(palette.ink)

            Spacer(minLength: FuelMetrics.Space.s12)

            SecureField(
                text: $model.draft,
                prompt: Text(preferences.provider.settingsKeyPlaceholder)
                    .foregroundStyle(palette.muted)
            ) {
                Text("settings.apiKey.label")
            }
            .labelsHidden()
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .multilineTextAlignment(.trailing)
            .fuelStyle(FuelTypography.listValueSmall)
            .foregroundStyle(palette.ink)
            .onSubmit {
                Task { await model.submitDraft(for: preferences.provider) }
            }
        }
    }

    // MARK: - Test row

    private var testRow: some View {
        SettingsRow(
            topPadding: FuelMetrics.Space.s10,
            bottomPadding: FuelMetrics.Space.s10,
            showsHairline: false
        ) {
            if let noteKey = model.note.titleKey(for: preferences.provider) {
                Text(noteKey)
                    .fuelStyle(FuelTypography.meta)
                    .foregroundStyle(noteColor)
            }

            if model.note.showsBillingLink {
                billingLink
            }

            Spacer(minLength: FuelMetrics.Space.s12)

            Button {
                Task { await model.recheck(for: preferences.provider) }
            } label: {
                Text("settings.keyTest.recheck")
                    .fuelStyle(FuelTypography.inlineAction)
                    .foregroundStyle(palette.ink)
            }
            .buttonStyle(FuelPressButtonStyle())
            .disabled(model.isChecking)
        }
        .fuelAnimation(FuelMotion.standard, value: model.note)
    }

    /// The way out of a no-credit account, and the only link in Settings.
    ///
    /// It sits beside the note it explains rather than out on the right, so the
    /// drawn row keeps its shape: a left-hand note and `Re-check` on the right,
    /// exactly where the export puts them. The style is `inlineAction` — the
    /// one `Re-check` already uses in this row — so a second action here is a
    /// drawn treatment applied twice rather than a new control.
    ///
    /// The 8pt gap is the gap between the two provider segments above it, and
    /// is a borrowed neighbour rather than an export value: the export draws no
    /// row with two actions in it. It is 8 on screen because `SettingsRow`
    /// stacks at spacing zero; under SwiftUI's default spacing this padding
    /// would have been one contribution to a gap of about sixteen, which is
    /// not a number anything in the design asked for.
    private var billingLink: some View {
        Link(destination: AIError.billingPage(for: preferences.provider)) {
            Text(KeyTestNote.billingActionTitle)
                .fuelStyle(FuelTypography.inlineAction)
                .foregroundStyle(palette.ink)
        }
        .padding(.leading, FuelMetrics.Space.s8)
    }

    /// The failure notes are the only place the error colour is used, and it
    /// does not follow the accent — an error that changes colour with a
    /// preference stops reading as an error.
    private var noteColor: Color {
        switch model.note {
        case .none, .passed: palette.muted
        case .notAccepted, .noCredit: palette.error
        }
    }
}
