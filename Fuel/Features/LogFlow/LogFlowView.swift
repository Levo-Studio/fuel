import PhotosUI
import SwiftUI

// MARK: - Log flow

/// The log flow: the chrome from screen 07 around whichever of the three modes
/// is selected, and — above it — the screens a scan goes through.
///
/// Camera and Recent are built. The text tab selects and draws its empty body,
/// so the bar is honest about how many modes there are while the one that still
/// needs a field and an `Analyse` button is to come — see `LogFlowPlaceholder`.
///
/// The analysis states and the result cover the whole flow rather than sitting
/// inside the scaffold, because the export draws them that way: screens 08 to
/// 11 and 14 carry no tab bar and no cancel row of their own.
struct LogFlowView: View {

    @Bindable var model: LogFlowModel

    @Bindable var camera: CameraLogModel

    /// Leaves the flow without logging anything — the `✕ Cancel` control.
    let onCancel: () -> Void

    /// A meal was logged and the flow is done. Recent returns to Today on the
    /// tap itself; a scan returns once the result screen's `Add` is tapped.
    let onLogged: () -> Void

    /// The image the gallery picker handed back, held only until it is loaded.
    @State private var pickedPhoto: PhotosPickerItem?

    var body: some View {
        ZStack {
            flow

            switch camera.stage {
            case .analysing(let step):
                AnalysisView(step: step, backdrop: .photo(camera.photo), onCancel: camera.cancelScan)
            case .failed(let failure):
                AnalysisFailureView(
                    failure: failure,
                    backdrop: .photo(camera.photo),
                    onRetry: camera.retry,
                    onDismiss: camera.discard
                )
            case .result:
                if let draft = camera.draft {
                    PhotoResultView(
                        draft: draft,
                        photo: camera.photo,
                        onBack: camera.discard,
                        onCycleLabel: camera.cycleLabel,
                        onToggleFavourite: camera.toggleFavourite,
                        onAdjustCalories: camera.adjustKilocalories,
                        onNew: camera.discard,
                        onAdd: add
                    )
                }
            case .viewfinder, .noKey:
                EmptyView()
            }
        }
        .fuelAnimation(FuelMotion.emphasised, value: camera.stage)
        .task(id: pickedPhoto) { await loadPickedPhoto() }
        .onAppear {
            model.reload()
            camera.refreshAvailability()
        }
    }

    // MARK: - The flow itself

    private var flow: some View {
        LogFlowScaffold(
            selection: $model.selectedTab,
            onCancel: onCancel,
            headerAccessory: { tab in
                // Only the camera tab carries one, and only while a scan is
                // possible at all — a picker that opened onto a keyless flow
                // would end at the same notice the tab is already showing.
                if tab == .camera, camera.stage == .viewfinder {
                    CameraGalleryButton(selection: $pickedPhoto)
                }
            },
            content: { tab in
                switch tab {
                case .camera:
                    CameraTabView(
                        preview: camera.camera.preview,
                        isScanAvailable: camera.stage != .noKey,
                        onShutter: { Task { await camera.capture() } }
                    )
                case .text:
                    LogFlowPlaceholder()
                case .recent:
                    RecentMealsView(meals: model.recentMeals, onLog: log)
                }
            }
        )
        .task(id: model.selectedTab) { await startCameraIfShowing() }
    }

    // MARK: - Actions

    private func log(_ meal: RecentMeal) {
        guard model.log(meal) else { return }
        onLogged()
    }

    private func add() {
        guard camera.commit() else { return }
        onLogged()
    }

    /// The session runs only while its own tab is showing. Leaving it running
    /// behind the Text and Recent tabs would hold the camera — and its
    /// indicator — for a mode that is not using it.
    private func startCameraIfShowing() async {
        if model.selectedTab == .camera {
            await camera.camera.start()
        } else {
            camera.camera.stop()
        }
    }

    /// Turns the picked item into a frame and starts the scan.
    ///
    /// The bytes are decoded straight into a `UIImage` and the item is dropped;
    /// nothing is copied to a temporary file on the way.
    private func loadPickedPhoto() async {
        guard let pickedPhoto else { return }
        defer { self.pickedPhoto = nil }
        guard
            let data = try? await pickedPhoto.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            return
        }
        camera.analyse(image)
    }
}

// MARK: - Placeholder

/// What the text tab draws until it is built.
///
/// Deliberately empty rather than a message: the text mode's body is the entry
/// field and its `Analyse` button (screen 12), which has no designed loading or
/// unavailable state that this could stand in for. An invented placeholder
/// would be a screen the export does not contain.
///
/// The text agent replaces the `.text` arm above. It needs no change to the
/// scaffold, the tab bar or this file's neighbours.
private struct LogFlowPlaceholder: View {

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Recent") {
    if let model = LogFlowPreviewData.model(showing: .recent),
       let camera = CameraPreviewData.model(hasKey: true) {
        LogFlowView(
            model: model,
            camera: camera,
            onCancel: {},
            onLogged: {}
        )
        .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
    }
}

#Preview("Camera") {
    if let model = LogFlowPreviewData.model(showing: .camera),
       let camera = CameraPreviewData.model(hasKey: true) {
        LogFlowView(
            model: model,
            camera: camera,
            onCancel: {},
            onLogged: {}
        )
        .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .green))
    }
}

#Preview("Camera without a key") {
    if let model = LogFlowPreviewData.model(showing: .camera),
       let camera = CameraPreviewData.model(hasKey: false) {
        LogFlowView(
            model: model,
            camera: camera,
            onCancel: {},
            onLogged: {}
        )
        .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
    }
}
