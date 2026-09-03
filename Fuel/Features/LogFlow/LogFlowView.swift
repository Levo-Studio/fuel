import PhotosUI
import SwiftUI

// MARK: - Log flow

/// The log flow: the chrome from screen 07 around whichever of the three modes
/// is selected, and — above it — the screens an estimate goes through.
///
/// The analysis states and the results cover the whole flow rather than sitting
/// inside the scaffold, because the export draws them that way: screens 08 to
/// 11, 14 and 15 carry no tab bar and no cancel row of their own. That is also
/// why the two AI modes cannot both have an overlay up — while one of them
/// does, the tab bar it would be switched from is not on screen.
struct LogFlowView: View {

    @Bindable var model: LogFlowModel

    @Bindable var camera: CameraLogModel

    @Bindable var text: TextLogModel

    /// Leaves the flow without logging anything — the `✕ Cancel` control.
    let onCancel: () -> Void

    /// A meal was logged and the flow is done. Recent returns to Today on the
    /// tap itself; an estimate returns once the result screen's `Add` is
    /// tapped.
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
                        onRemoveItem: camera.removeItem,
                        onEditItem: camera.editItem,
                        onAddItem: camera.addItem,
                        onNew: camera.discard,
                        onAdd: add
                    )
                }
            case .viewfinder, .noKey:
                EmptyView()
            }

            switch text.stage {
            case .analysing(let step):
                AnalysisView(step: step, backdrop: .text, onCancel: text.cancelEstimate)
            case .failed(let failure):
                AnalysisFailureView(
                    failure: failure,
                    backdrop: .text,
                    onRetry: text.retry,
                    onDismiss: text.returnToEntry
                )
            case .result:
                if let draft = text.draft {
                    TextResultView(
                        draft: draft,
                        typedText: text.typedText,
                        // `Back` keeps the sentence and `New` clears it, which
                        // is the one thing the text mode can offer that the
                        // camera mode cannot: a photograph is not editable on
                        // the way back, so the export had no version of this
                        // to draw.
                        onBack: text.returnToEntry,
                        onCycleLabel: text.cycleLabel,
                        onToggleFavourite: text.toggleFavourite,
                        onRemoveItem: text.removeItem,
                        onEditItem: text.editItem,
                        onAddItem: text.addItem,
                        onNew: text.discard,
                        onAdd: addTypedMeal
                    )
                }
            case .entry, .noKey:
                EmptyView()
            }
        }
        .fuelAnimation(FuelMotion.emphasised, value: camera.stage)
        .fuelAnimation(FuelMotion.emphasised, value: text.stage)
        .task(id: pickedPhoto) { await loadPickedPhoto() }
        .onAppear {
            model.reload()
            camera.refreshAvailability()
            text.refreshAvailability()
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
                    TextTabView(
                        typedText: $text.typedText,
                        isEstimateAvailable: text.stage != .noKey,
                        onAnalyse: text.analyse
                    )
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

    private func addTypedMeal() {
        guard text.commit() else { return }
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

// MARK: - Previews

#Preview("Recent") {
    if let model = LogFlowPreviewData.model(showing: .recent),
       let camera = CameraPreviewData.model(hasKey: true),
       let text = TextPreviewData.model(hasKey: true) {
        LogFlowView(
            model: model,
            camera: camera,
            text: text,
            onCancel: {},
            onLogged: {}
        )
        .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
    }
}

#Preview("Camera") {
    if let model = LogFlowPreviewData.model(showing: .camera),
       let camera = CameraPreviewData.model(hasKey: true),
       let text = TextPreviewData.model(hasKey: true) {
        LogFlowView(
            model: model,
            camera: camera,
            text: text,
            onCancel: {},
            onLogged: {}
        )
        .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .green))
    }
}

#Preview("Text") {
    if let model = LogFlowPreviewData.model(showing: .text),
       let camera = CameraPreviewData.model(hasKey: true),
       let text = TextPreviewData.model(hasKey: true) {
        LogFlowView(
            model: model,
            camera: camera,
            text: text,
            onCancel: {},
            onLogged: {}
        )
        .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
    }
}

#Preview("Text without a key") {
    if let model = LogFlowPreviewData.model(showing: .text),
       let camera = CameraPreviewData.model(hasKey: false),
       let text = TextPreviewData.model(hasKey: false) {
        LogFlowView(
            model: model,
            camera: camera,
            text: text,
            onCancel: {},
            onLogged: {}
        )
        .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .mono))
    }
}
