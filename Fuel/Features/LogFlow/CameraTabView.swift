import PhotosUI
import SwiftUI

// MARK: - Camera tab

/// Screen 07: the viewfinder, the context line, and the shutter under them.
///
/// Presentation only — it is handed a preview source and a binding and hands
/// back a tap, so it renders without a capture session and without a Keychain.
/// The chrome around it (the cancel control, the gallery button, the three
/// tabs) belongs to `LogFlowScaffold`; this is the body between them.
struct CameraTabView: View {

    let preview: MealCameraPreview

    /// `false` when no key is stored. The scan is the only thing a key buys,
    /// so the shutter goes with it and the tab says why.
    let isScanAvailable: Bool

    /// What the user has typed under the viewfinder. Optional in the plainest
    /// sense — see `contextField`.
    @Binding var context: String

    /// Which field in the flow is holding the keyboard. See
    /// `LogFlowChrome.canHoldPhotoContextFocus`.
    @FocusState.Binding var writing: LogFlowField?

    let onShutter: () -> Void

    var body: some View {
        if isScanAvailable {
            VStack(alignment: .center, spacing: .zero) {
                viewfinder
                contextField
                shutter
            }
        } else {
            keylessNotice
        }
    }

    // MARK: - Viewfinder

    /// Full-bleed, unlike every other body in the flow: the export gives it no
    /// horizontal inset at all, only the `20px` drop from the header.
    private var viewfinder: some View {
        Group {
            switch preview {
            case .live(let session):
                CameraPreviewLayer(session: session)
            case .unavailable:
                PhotoHatch(
                    base: FuelPalette.Camera.placeholderBase,
                    stripe: FuelPalette.Camera.placeholderStripe
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .padding(.top, FuelMetrics.Space.s20)
        .accessibilityHidden(true)
    }

    // MARK: - Context

    /// Detail the photograph cannot carry — the oil something was fried in,
    /// what is in a sauce — sent to the model alongside the frame.
    ///
    /// **The export draws no field on screen 07.** What it draws between the
    /// viewfinder and the shutter is nothing at all: `flex:1` on the
    /// viewfinder, then `padding:22px 0 18px` around a 70px ring. What stands
    /// here instead is this field, on the owner's instruction after testing a
    /// build. That is a deviation from the design and is recorded as one; it is
    /// the owner's call and not a reading of the export.
    ///
    /// Nothing drawn moves for it. The viewfinder is the flexible element on
    /// this screen — the export gives it a height only through `flex:1` — so it
    /// is what gives the field its room, exactly as it gives room to a taller
    /// device. The shutter keeps its drawn ring, fill and its `22`/`18` bands,
    /// and the tab bar under it is untouched. The field's own `s20` above it is
    /// the drop the export already puts over the viewfinder, and its inset is
    /// the flow's own `logFlowHorizontalPadding`; both are drawn values, used
    /// where the design does not draw one.
    ///
    /// It never asks for the keyboard by itself. A camera screen that opened
    /// with a keyboard over the viewfinder would be a camera screen you cannot
    /// see through, so focus arrives only from a tap, and the shutter takes it
    /// away again through the stage change — see
    /// `LogFlowChrome.canHoldPhotoContextFocus`.
    private var contextField: some View {
        MealTextField(
            text: $context,
            field: .photoContext,
            examples: CameraCopy.contextExamples,
            line: CameraCopy.contextLine,
            accessibilityLabel: CameraCopy.contextLabel,
            writing: $writing
        )
        .padding(.top, FuelMetrics.Space.s20)
        .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
    }

    // MARK: - Shutter

    /// A `56pt` fill inside a `70pt` ring, and nothing inside either.
    private var shutter: some View {
        Button(action: onShutter) {
            Circle()
                .fill(FuelPalette.Camera.ink)
                .frame(width: FuelMetrics.Control.shutterFill, height: FuelMetrics.Control.shutterFill)
                .frame(width: FuelMetrics.Control.shutterRing, height: FuelMetrics.Control.shutterRing)
                .overlay {
                    Circle()
                        .strokeBorder(FuelPalette.Camera.ring, lineWidth: FuelMetrics.Line.hairline)
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(CameraCopy.shutterLabel))
        .accessibilityHint(Text(CameraCopy.shutterHint))
        .padding(.top, FuelMetrics.Space.s22)
        .padding(.bottom, FuelMetrics.Space.s18)
    }

    // MARK: - No key

    /// What the tab draws with no key stored.
    ///
    /// Not in the export, which draws no disabled state — so it is built from
    /// the pieces screen 13 already uses, a title over a hint at the flow's own
    /// inset, and it says which log mode still works rather than only what does
    /// not.
    private var keylessNotice: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(CameraCopy.noKeyTitle)
                .fuelStyle(FuelTypography.sheetTitle)
                .foregroundStyle(FuelPalette.Camera.ink)

            Text(CameraCopy.noKeyHint)
                .fuelStyle(FuelTypography.hintWrapping)
                .foregroundStyle(FuelPalette.Camera.muted)
                .padding(.top, FuelMetrics.Space.s8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FuelMetrics.Space.s34)
        .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
    }
}

// MARK: - Gallery

/// The circle top right on screen 07, which opens the photo picker.
///
/// `PhotosPicker` rather than a permission prompt and a library read: the
/// picker runs outside the app and hands back one image, so Fuel never
/// enumerates the library and never holds it. The picked image goes the same
/// way a captured one does — compressed, sent, released, never written down.
///
/// This deliberately makes no claim about whether the `photoLibrary:` form
/// needs `NSPhotoLibraryUsageDescription`; an earlier version of this comment
/// asserted it does not, which could not be confirmed from Apple's own pages.
/// `Fuel/Info.plist` declares the description either way, which is the safe
/// side of a question the documentation does not settle, and its wording is
/// what the user actually sees.
struct CameraGalleryButton: View {

    @Binding var selection: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            Glyph()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(CameraCopy.galleryLabel))
    }

    /// A view rather than an inline closure: `PhotosPicker`'s label builder is
    /// not main-actor isolated, and the design layer's `fuelStyle` is.
    private struct Glyph: View {

        var body: some View {
            // A symbol stands in for a character the bundled face cannot
            // draw. The export sets this control's glyph as the text `\u{25A3}`
            // and the browser satisfied it from a fallback font; neither Plus
            // Jakarta Sans nor DM Mono carries that codepoint, so the drawn
            // markup renders as tofu on the device. `photo.on.rectangle` is
            // the platform's own mark for taking an existing image out of the
            // library, which is what this control does, and its two nested
            // rectangles are the nearest silhouette SF has to the drawn
            // square-inside-a-square. `FuelMetrics.Line.Glyph`'s stroke weights
            // do not apply to a symbol either — SF draws its own. The drawn
            // 14pt size, the 34pt circle, its hairline and its colour are
            // unchanged.
            Image(systemName: "photo.on.rectangle")
                .fuelStyle(FuelTypography.iconGlyph)
                .foregroundStyle(FuelPalette.Camera.ink)
                .frame(width: FuelMetrics.Control.circleButton, height: FuelMetrics.Control.circleButton)
                .overlay {
                    Circle()
                        .strokeBorder(FuelPalette.Camera.hair, lineWidth: FuelMetrics.Line.hairline)
                }
                // The drawn circle is 34 and a finger is 44 — the same
                // arithmetic Today's gear does, and for the same reason. The
                // larger frame grows the region that answers around it, and
                // the negative padding gives the layout its 34 back, so the
                // circle keeps the size and the position the export puts it in
                // and the header row is laid out as though nothing here were
                // bigger than what is drawn.
                .frame(
                    width: FuelMetrics.Control.minimumHitTarget,
                    height: FuelMetrics.Control.minimumHitTarget
                )
                .contentShape(Rectangle())
                .padding(
                    -FuelMetrics.Control.hitTargetOverhang(
                        around: FuelMetrics.Control.circleButton
                    )
                )
        }
    }
}

// MARK: - Previews

#Preview("Camera") {
    @Previewable @State var context = ""
    @Previewable @FocusState var writing: LogFlowField?

    ZStack {
        FuelPalette(theme: .dark, accent: .mono).camera
            .ignoresSafeArea()

        CameraTabView(
            preview: .unavailable,
            isScanAvailable: true,
            context: $context,
            writing: $writing,
            onShutter: {}
        )
    }
}

#Preview("Camera, context written in") {
    @Previewable @State var context = "Fried in butter, not oil"
    @Previewable @FocusState var writing: LogFlowField?

    ZStack {
        FuelPalette(theme: .dark, accent: .mono).camera
            .ignoresSafeArea()

        CameraTabView(
            preview: .unavailable,
            isScanAvailable: true,
            context: $context,
            writing: $writing,
            onShutter: {}
        )
    }
}

#Preview("Camera without a key") {
    @Previewable @State var context = ""
    @Previewable @FocusState var writing: LogFlowField?

    ZStack {
        FuelPalette(theme: .light, accent: .mono).camera
            .ignoresSafeArea()

        CameraTabView(
            preview: .unavailable,
            isScanAvailable: false,
            context: $context,
            writing: $writing,
            onShutter: {}
        )
    }
}
