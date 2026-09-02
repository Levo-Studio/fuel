import SwiftUI

// MARK: - Screen 01

/// `01 · API key · model and key`.
///
/// There is no skip control, and its absence is a decision rather than an
/// omission: Fuel asks for a key at first launch, and the export draws no way
/// past this screen other than answering it.
struct APIKeyScreen: View {

    @Environment(\.fuelPalette) private var palette

    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingScreen(topPadding: FuelMetrics.Screen.onboardingTopPadding) {
            OnboardingEyebrow(text: "onboarding.step1")

            Text("onboarding.key.headline")
                .fuelStyle(FuelTypography.display)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FuelMetrics.Space.s16)

            Text("onboarding.key.lead")
                .fuelStyle(FuelTypography.lead)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FuelMetrics.Space.s12)

            providerSegments
                .padding(.top, FuelMetrics.Space.s38)

            keyField
                .padding(.top, FuelMetrics.Space.s30)
        } footer: {
            OnboardingFootnote(text: "onboarding.key.footnote")
            OnboardingButton(title: "onboarding.continue") {
                model.submitKey()
            }
        }
    }

    // MARK: - Provider

    private var providerSegments: some View {
        HStack(spacing: FuelMetrics.Space.s8) {
            ForEach(AIProvider.allCases, id: \.self) { provider in
                segment(for: provider)
            }
        }
        .fuelAnimation(FuelMotion.standard, value: model.provider)
    }

    private func segment(for provider: AIProvider) -> some View {
        let isSelected = model.provider == provider
        return Button {
            model.selectProvider(provider)
        } label: {
            Text(provider.segmentTitle)
                .fuelStyle(FuelTypography.segmentLabel)
                .foregroundStyle(isSelected ? palette.onAccent : palette.ink)
                .frame(maxWidth: .infinity)
                .padding(FuelMetrics.Space.s12)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                            .fill(isSelected ? palette.accentColor : Color.clear)
                        RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                            .strokeBorder(
                                isSelected ? palette.accentColor : palette.hair,
                                lineWidth: FuelMetrics.Line.hairline
                            )
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Key

    /// The field is secure in every state.
    ///
    /// The export draws a filled-in key as readable mono text, which is how a
    /// still render shows that a field has something in it — it is not a
    /// licence to put a credential on screen in plain text over the user's
    /// shoulder. Autocorrection, autocapitalisation and AutoFill are all off:
    /// the first two would mangle a pasted key, and a content type would offer
    /// to file it in iCloud Keychain, which is precisely the cloud round-trip
    /// this app exists without.
    private var keyField: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("onboarding.key.fieldLabel")
                .fuelStyle(FuelTypography.sectionLabel)
                .foregroundStyle(palette.muted)

            SecureField(
                "",
                text: $model.keyDraft,
                prompt: Text(model.provider.keyPlaceholder).foregroundStyle(palette.muted)
            )
            .fuelStyle(FuelTypography.monoValue)
            .foregroundStyle(palette.ink)
            .tint(palette.accentColor)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { model.submitKey() }
            .padding(.top, FuelMetrics.Space.s14)
            .padding(.bottom, FuelMetrics.Space.s12)

            OnboardingHairline()

            Text(model.provider.modelLabel)
                .fuelStyle(FuelTypography.meta)
                .foregroundStyle(palette.muted)
                .padding(.top, FuelMetrics.Space.s12)
        }
    }
}

// MARK: - Provider copy

/// The provider's user-facing strings.
///
/// They live here rather than on `AIProvider` because they are interface copy,
/// and `Core/AI` has no business knowing which string catalog key a segment
/// label sits under.
extension AIProvider {

    var segmentTitle: LocalizedStringKey {
        switch self {
        case .claude: "onboarding.provider.claude"
        case .mistral: "onboarding.provider.mistral"
        }
    }

    /// The placeholder shown in the empty key field. It tells the user which
    /// field they are in and is not a validation rule — `APIKeyFormat` says so
    /// at length for the Mistral case.
    var keyPlaceholder: LocalizedStringKey {
        switch self {
        case .claude: "onboarding.key.placeholder.claude"
        case .mistral: "onboarding.key.placeholder.mistral"
        }
    }

    /// `Model: Claude Sonnet 5`, under the key field on screen 01.
    var modelLabel: LocalizedStringKey {
        switch self {
        case .claude: "onboarding.model.claude"
        case .mistral: "onboarding.model.mistral"
        }
    }

    /// The bare model name, used as the eyebrow on the key-test screens.
    var modelName: LocalizedStringKey {
        switch self {
        case .claude: "onboarding.modelName.claude"
        case .mistral: "onboarding.modelName.mistral"
        }
    }
}
