import AVFoundation
import Combine
import Kingfisher
import Network
import SwiftUI
import UIKit

// MARK: - View model (business logic unchanged, capture/export/permission paths untouched)

@MainActor
final class CameraViewModel: ObservableObject {
    /// Prototype `pose-opacity-slider` default (`value="0.5"` in `camera-live.html`).
    @Published var guideOpacity = 0.5
    @Published var guideFlipped = false
    @Published var isGridVisible = false
    /// `camera-live.html:87` — `<span id="flash-value">Auto</span>`: the prototype's shipped default
    /// is `Auto`, and AC4's cycle `Off -> Auto -> On -> Off` does not pin the entry point.
    @Published var flashSetting: CameraFlashSetting = .auto
    /// `.nb-camera-tools-menu` — anchored popup, not a bottom sheet.
    @Published var showCameraTools = false
    /// `.nb-pose-picker-sheet` — camera-local bottom sheet, not a pushed route.
    @Published var showPosePicker = false
    /// `pose-visibility-row`: Shown / Hidden for the selected pose reference.
    @Published var isPoseGuideVisible = true
    /// `pose-line-color-black` / `pose-line-color-white`.
    @Published var guideLineColor: GuideLineColor = .black
    /// Pinch / rotate / drag placement of the pose reference, committed when a gesture ends.
    @Published var guideTransform = GuideTransform()
    /// Transient capture feedback; cleared by `statusClearTask`.
    @Published var statusMessage: String?
    @Published var zoomLevel: CameraZoomLevel = .one
    /// URL of the newest capture, drawn as a 48pt thumbnail in the shutter rail.
    @Published private(set) var latestThumbnailURL: URL?

    var cameraControlsEnabled: Bool {
        coordinator.state.permission == .authorized
            && !coordinator.state.isCaptureInFlight
    }

    let camera: any CameraSessionControlling
    let coordinator: CameraCoordinator
    let imageStorage: CaptureImageStorage
    private var timeoutTask: Task<Void, Never>?
    private var statusClearTask: Task<Void, Never>?

    // MARK: Persistence (FEAT-012)

    private let settingsStore: any CameraSettingsStore
    private let settingsWriter: CameraSettingsWriter
    private let saveDebounceNanoseconds: UInt64
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    /// The settings revision the next write will carry. Always above the revision read from disk, so
    /// a relaunch keeps counting up instead of restarting the row's history.
    private var settingsRevision: Int64 = 0
    private var hasUnsavedSettings = false
    /// True once the stored snapshot (or its absence) has been merged into the published state.
    /// Nothing is written before that, so defaults can never overwrite what is on disk.
    private(set) var initialMergeDone = false
    /// Settings the user already changed — a late restore must not overwrite them.
    private var touchedSettings: Set<PersistedSetting> = []
    private var isApplyingRestore = false
    /// C3-Q1 (a): the restored placement waits for the first guide after launch. Kept here instead
    /// of being written straight into `guideTransform`, because the pose-change reset would wipe it.
    private var pendingRestoredTransform: GuideTransform?
    /// The same placement as it was stored, in degrees. `GuideTransform` holds an `Angle` (radians),
    /// so re-deriving the JSON from it moves the degrees by one ulp (`12` → `12.000000000000002`).
    /// While the user has not touched the placement, the row keeps this exact value, so an unrelated
    /// edit never rewrites the placement the user left behind.
    private var restoredTransformValue: CameraSettings.Transform?
    private var hasGuide = false
    private var lastAppliedFlash: CameraFlashSetting?
    private var lastAppliedZoom: CGFloat?

    init(
        guide: NativePose? = nil,
        camera: any CameraSessionControlling = NativeCameraController(),
        photoRepository: PhotoRepository? = nil,
        photoMetadata: CapturePhotoMetadata? = nil,
        settingsStore: any CameraSettingsStore = DeferredCameraSettingsStore(),
        saveDebounceNanoseconds: UInt64 = 300_000_000
    ) {
        self.camera = camera
        self.settingsStore = settingsStore
        self.settingsWriter = CameraSettingsWriter(store: settingsStore)
        self.saveDebounceNanoseconds = saveDebounceNanoseconds
        let storage = CaptureImageStorage()
        self.imageStorage = storage
        // The database used to be opened + migrated right here. `CameraViewModel` is built on the
        // main thread while the tab switch is being resolved, so that open cost was paid before the
        // camera screen could appear. `DeferredCapturePhotoMetadata` opens it on first use instead,
        // off the main thread.
        let metadata: CapturePhotoMetadata
        if let photoMetadata {
            metadata = photoMetadata
        } else if let photoRepository {
            metadata = PhotoRepositoryMetadataAdapter(repository: photoRepository)
        } else {
            metadata = DeferredCapturePhotoMetadata()
        }
        coordinator = CameraCoordinator(
            controller: camera,
            imageStorage: storage,
            photoMetadata: metadata,
            poseId: guide?.id,
            poseName: guide?.name ?? ""
        )
        observeSettings()
        loadTask = Task { [weak self] in await self?.loadSettings() }
    }

    func onAppear() async {
        let start = Date()
        coordinator.onLaunch()
        if coordinator.state.permission == .authorized {
            // `AVCaptureSession.startRunning()` is a blocking, hardware-bound call: it cannot be
            // moved off the main thread from here (the controller is `@MainActor`), so the log below
            // separates how much of "camera is slow" is the session and how much is app work.
            try? await camera.start()
            reconcileHardware()
        }
        let sessionStartMs = Int(Date().timeIntervalSince(start) * 1000)
        await coordinator.refreshLatestThumbnail()
        reloadThumbnail()
        let totalMs = Int(Date().timeIntervalSince(start) * 1000)
        #if DEBUG
        NSLog("%@", "AIPOSE_PERF camera_open session_start_ms=\(sessionStartMs) total_ms=\(totalMs)")
        #endif
    }

    func onDisappear() {
        timeoutTask?.cancel()
        statusClearTask?.cancel()
        camera.stop()
    }

    func requestPermission() {
        camera.requestPermission { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.coordinator.onPermissionResult(result)
                if result == .authorized {
                    try? await self.camera.start()
                    self.reconcileHardware()
                }
            }
        }
    }

    func capture() {
        guard coordinator.onCaptureRequested() else { return }
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            self?.coordinator.onCaptureTimeoutTick()
        }
        observeCaptureCompletion()
    }

    func switchCamera() {
        guard cameraControlsEnabled else { return }
        camera.switchCamera()
    }

    func openCameraTools() {
        guard cameraControlsEnabled else { return }
        showCameraTools = true
    }

    /// `modal.js:26-28` — the More control toggles (`setSettingsOpen(settingsMenu.hidden)`), so the
    /// same control that opens the popup closes it. Before this, the More action always opened,
    /// which broke AC4's dismissal on the control itself (`02` and `03` measured byte-identical).
    func toggleCameraTools() {
        guard cameraControlsEnabled else { return }
        showCameraTools.toggle()
    }

    func closeCameraTools() {
        showCameraTools = false
    }

    func openPosePicker() {
        guard cameraControlsEnabled else { return }
        showPosePicker = true
    }

    func closePosePicker() {
        showPosePicker = false
    }

    func cycleFlash() {
        guard cameraControlsEnabled else { return }
        flashSetting = flashSetting.cameraToolsNext()
        reconcileHardware()
    }

    func toggleGrid() {
        guard cameraControlsEnabled else { return }
        isGridVisible.toggle()
    }

    func togglePoseGuideVisibility() {
        guard cameraControlsEnabled else { return }
        isPoseGuideVisible.toggle()
    }

    func setGuideLineColor(_ color: GuideLineColor) {
        guard cameraControlsEnabled else { return }
        guideLineColor = color
    }

    func setGuideOpacity(_ value: Double) {
        guard cameraControlsEnabled else { return }
        guideOpacity = value
    }

    func commitGuideGesture(_ delta: GuideTransform.Delta) {
        guideTransform = guideTransform.applying(delta)
    }

    func resetGuideTransform() {
        guideTransform = GuideTransform()
    }

    func cycleZoom() {
        guard cameraControlsEnabled else { return }
        applyZoom(zoomLevel.next())
    }

    func applyZoom(_ level: CameraZoomLevel) {
        zoomLevel = level
        reconcileHardware()
    }

    // MARK: - Settings persistence (FEAT-012)

    /// The eight settings that survive a relaunch. `CameraSnapshot` carries them in one JSON blob;
    /// the selected pose is deliberately not among them (D8).
    private enum PersistedSetting: Hashable {
        case opacity, flipped, grid, flash, guideVisibility, lineColor, transform, zoom
    }

    /// `@Published` sinks rather than setter bodies, because the guided gestures and a few tests
    /// assign the properties directly. Two details matter here:
    /// - `dropFirst()`: the publisher replays its current value on subscribe, and that replay is not
    ///   a user edit — without it every setting would look "touched" before the restore lands and the
    ///   whole restore would be skipped.
    /// - the sink fires on `willSet`, so nothing here may read the property: it only marks what the
    ///   user touched and schedules a write, and the write reads the state when it actually runs.
    private func observeSettings() {
        $guideOpacity.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.opacity) }.store(in: &cancellables)
        $guideFlipped.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.flipped) }.store(in: &cancellables)
        $isGridVisible.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.grid) }.store(in: &cancellables)
        $flashSetting.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.flash) }.store(in: &cancellables)
        $isPoseGuideVisible.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.guideVisibility) }
            .store(in: &cancellables)
        $guideLineColor.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.lineColor) }.store(in: &cancellables)
        $guideTransform.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.transform) }.store(in: &cancellables)
        $zoomLevel.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.zoom) }.store(in: &cancellables)
    }

    private func settingsDidChange(_ setting: PersistedSetting) {
        // The restore assigns the published properties too; those are not user edits.
        guard !isApplyingRestore else { return }
        touchedSettings.insert(setting)
        hasUnsavedSettings = true
        // Held until the merge: writing the defaults now would overwrite the stored row.
        guard initialMergeDone else { return }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let debounce = saveDebounceNanoseconds
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled else { return }
            await self?.persistSettings()
        }
    }

    /// Writes the current state under the current revision. Idempotent: a write that carries a
    /// revision the row already holds is dropped by the store, so the debounce firing after a flush
    /// costs nothing.
    private func persistSettings() async {
        guard initialMergeDone, hasUnsavedSettings else { return }
        // One revision per write, always above what the row already holds.
        settingsRevision += 1
        let revision = settingsRevision
        hasUnsavedSettings = false
        await settingsWriter.write(currentSettings(revision: revision))
    }

    /// Scene going to the background: write now instead of waiting for the debounce. Deliberately
    /// does not cancel the pending debounce — the revision guard makes the extra write a no-op.
    func flushSettings() async {
        await persistSettings()
    }

    private func currentSettings(revision: Int64) -> CameraSettings {
        CameraSettings(
            revision: revision,
            guideOpacity: guideOpacity,
            guideFlipped: guideFlipped,
            isGridVisible: isGridVisible,
            flash: flashSetting,
            isPoseGuideVisible: isPoseGuideVisible,
            lineColor: guideLineColor,
            transform: persistedTransform,
            zoom: zoomLevel
        )
    }

    /// The placement the row has to keep. Two cases:
    /// - the user has not touched the placement: hand back the exact value that came off the row,
    ///   whether it is still waiting for its first guide (`pendingRestoredTransform`) or already
    ///   applied. Writing `guideTransform` here would turn `12°` into `12.000000000000002°` on every
    ///   unrelated edit (degrees → `Angle`'s radians → degrees), i.e. the row would change while the
    ///   screen did not.
    /// - the user has placed the reference (pinch or double-tap): `guideTransform` is the truth.
    private var persistedTransform: CameraSettings.Transform {
        guard !touchedSettings.contains(.transform), let restored = restoredTransformValue else {
            return .init(guideTransform)
        }
        return restored
    }

    private func loadSettings() async {
        let restored = (try? await settingsStore.load()) ?? nil
        merge(restored: restored)
    }

    /// Folds the stored snapshot into the published state **directly**: the guarded setters would
    /// silently drop a restore that arrives before the camera permission resolves, which is exactly
    /// the case at launch. A setting the user already changed wins over the stored one.
    private func merge(restored: CameraSettings?) {
        let stored = restored ?? CameraSettings()
        isApplyingRestore = true
        if !touchedSettings.contains(.opacity) { guideOpacity = stored.guideOpacity }
        if !touchedSettings.contains(.flipped) { guideFlipped = stored.guideFlipped }
        if !touchedSettings.contains(.grid) { isGridVisible = stored.isGridVisible }
        if !touchedSettings.contains(.flash) { flashSetting = stored.flash }
        if !touchedSettings.contains(.guideVisibility) { isPoseGuideVisible = stored.isPoseGuideVisible }
        if !touchedSettings.contains(.lineColor) { guideLineColor = stored.lineColor }
        if !touchedSettings.contains(.zoom) { zoomLevel = stored.zoom }
        if !touchedSettings.contains(.transform) {
            pendingRestoredTransform = restored.map { $0.transform.placement }
            restoredTransformValue = restored?.transform
        }
        isApplyingRestore = false

        // The next write has to be above the stored revision, so a relaunch keeps the row
        // forward-only instead of restarting its history.
        settingsRevision = max(settingsRevision, stored.revision)
        initialMergeDone = true
        reconcileHardware()
        applyRestoredTransformIfUntouched()
        // Edits made while the load was in flight were held back; they are safe to write now.
        if hasUnsavedSettings { scheduleSave() }
    }

    /// Pushes the settings that live on the capture hardware. Idempotent and order-independent:
    /// whichever of "snapshot restored" and "session running" finishes last performs the apply.
    /// This is also what fixes the launch mismatch where the UI said `Auto` while the device sat at
    /// `Off` — nothing re-applied the flash after the session came up.
    func reconcileHardware() {
        guard initialMergeDone,
              coordinator.state.permission == .authorized,
              camera.isSessionRunning else { return }
        if lastAppliedFlash != flashSetting {
            lastAppliedFlash = flashSetting
            camera.setFlashMode(flashSetting)
        }
        if lastAppliedZoom != zoomLevel.factor {
            lastAppliedZoom = zoomLevel.factor
            camera.setZoomFactor(zoomLevel.factor)
        }
    }

    /// The pose reference changed. Keeps today's reset-on-change behaviour, except for the **first**
    /// guide after a launch that restored a placement (C3-Q1 option a) — the only place that rule
    /// lives.
    func guideDidChange(hasGuide: Bool) {
        self.hasGuide = hasGuide
        guard hasGuide else {
            pendingRestoredTransform = nil
            resetPlacementForPoseChange()
            return
        }
        if applyRestoredTransformIfUntouched() { return }
        resetPlacementForPoseChange()
    }

    /// `.onAppear` form of the same hook: `.onChange` never fires for the initial value, so a guide
    /// that is already selected at launch gets the restored placement here. Does nothing when there
    /// is nothing pending, so re-appearing never resets a placement the user made.
    func guideAppeared(hasGuide: Bool) {
        self.hasGuide = hasGuide
        applyRestoredTransformIfUntouched()
    }

    @discardableResult
    private func applyRestoredTransformIfUntouched() -> Bool {
        guard hasGuide, let pending = pendingRestoredTransform else { return false }
        pendingRestoredTransform = nil
        guard !touchedSettings.contains(.transform) else { return false }
        // The value came off the row a moment ago, so this is not a change worth writing back.
        setTransformProgrammatically(pending, notifyPersistence: false)
        return true
    }

    /// Resetting on a pose change is what the user sees, so once the launch restore is over the row
    /// has to follow it — otherwise the old placement comes back on the next launch even though the
    /// screen shows the reference reset. Before the merge it is not a user edit: a guide chosen while
    /// the load was in flight must not swallow the restored placement (`C3-Q1` a).
    private func resetPlacementForPoseChange() {
        setTransformProgrammatically(GuideTransform(), notifyPersistence: initialMergeDone)
    }

    private func setTransformProgrammatically(_ transform: GuideTransform, notifyPersistence: Bool) {
        let wasApplying = isApplyingRestore
        isApplyingRestore = !notifyPersistence
        guideTransform = transform
        isApplyingRestore = wasApplying
    }

    /// Only resolves the file URL: decoding the capture here (a 12MP file straight into a 48pt
    /// thumbnail) was main-thread work in the camera open path. Kingfisher does the bounded decode.
    private func reloadThumbnail() {
        guard let path = coordinator.state.thumbnailPathValue(),
              let full = imageStorage.fullPath(for: path) else {
            latestThumbnailURL = nil
            return
        }
        latestThumbnailURL = URL(fileURLWithPath: full)
    }

    /// A finished capture is already in the app gallery (the coordinator persisted it); this also
    /// copies it to the Photos library and returns the camera to `previewReady` so the shutter is
    /// usable again, without any intermediate screen.
    private func observeCaptureCompletion() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            while coordinator.state.isCaptureInFlight {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            timeoutTask?.cancel()
            reloadThumbnail()

            guard case .captureSucceeded(_, let photo) = coordinator.state.phase else {
                showStatus(coordinator.state.statusText())
                coordinator.dismissResult()
                return
            }
            coordinator.dismissResult()
            guard let path = imageStorage.fullPath(for: photo.imagePath) else {
                showStatus(CaptureFailure.writeFailed.userMessage)
                return
            }
            let savedToPhotos = await PhotosExporter.saveImage(at: URL(fileURLWithPath: path))
            showStatus(savedToPhotos ? "Saved" : "Saved to gallery. Allow Photos access to also save to your library.")
        }
    }

    private func showStatus(_ message: String?) {
        statusClearTask?.cancel()
        statusMessage = message
        guard message != nil else { return }
        statusClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }
}

/// Opens the database the first time captured-photo metadata is needed, so building a
/// `CameraViewModel` during a tab switch no longer opens + migrates the database on the main thread.
/// Actor isolation also guarantees the file work runs off the main thread and happens once.
actor DeferredCapturePhotoMetadata: CapturePhotoMetadata {
    private var resolved: (any CapturePhotoMetadata)?

    private func backend() -> any CapturePhotoMetadata {
        if let resolved { return resolved }
        let backend: any CapturePhotoMetadata
        if let database = try? AppDatabase() {
            backend = PhotoRepositoryMetadataAdapter(repository: PhotoRepository(database: database))
        } else {
            backend = InMemoryCapturePhotoMetadata()
        }
        resolved = backend
        return backend
    }

    func insertCapturedPhoto(imagePath: String, poseId: String?, poseName: String) async throws -> Int64 {
        try await backend().insertCapturedPhoto(imagePath: imagePath, poseId: poseId, poseName: poseName)
    }

    func getLatestPhotoPath() async throws -> String? {
        try await backend().getLatestPhotoPath()
    }
}

/// Prototype scale-factor stops (`nb-camera-zoom-slider`, values 0…2 → 1x…3x).
enum CameraZoomLevel: Int, CaseIterable, Equatable {
    case one = 1, two = 2, three = 3

    var label: String { "\(rawValue)x" }
    var factor: CGFloat { CGFloat(rawValue) }

    func next() -> CameraZoomLevel {
        let all = CameraZoomLevel.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

/// Prototype flash rotation (`toggle.js`: `Off → Auto → On → Off`). Deliberately local to the
/// camera tools surface — `CameraFlashSetting.next()` in `Core/Camera` keeps its capture-path order.
extension CameraFlashSetting {
    func cameraToolsNext() -> CameraFlashSetting {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }

    /// `toggle.js` row label: yellow for Auto, white for On, grey for Off.
    var toolsDisplayName: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .auto: return "Auto"
        }
    }
}

/// `pose-line-color-black` / `pose-line-color-white` (`camera-live.html`). The colour is the stroke
/// of the pose reference: the stick-figure fallback and the tinted extracted line art.
enum GuideLineColor: String, CaseIterable {
    case black, white

    var label: String { rawValue.capitalized }
    var color: Color { self == .black ? AIPoseColor.border : .white }
}

/// Placement of the pose reference over the preview. Scale and rotation pivot on the reference's
/// centre; the offset is in screen space.
struct GuideTransform: Equatable {
    static let scaleRange: ClosedRange<CGFloat> = 0.4...3

    var scale: CGFloat = 1
    var rotation: Angle = .zero
    var offset: CGSize = .zero

    /// One in-flight (or just-ended) gesture, relative to the committed transform.
    struct Delta: Equatable {
        static let identity = Delta(scale: 1, rotation: .zero, translation: .zero)

        var scale: CGFloat
        var rotation: Angle
        var translation: CGSize
    }

    func applying(_ delta: Delta) -> GuideTransform {
        GuideTransform(
            scale: min(max(scale * delta.scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound),
            rotation: rotation + delta.rotation,
            offset: CGSize(width: offset.width + delta.translation.width,
                           height: offset.height + delta.translation.height)
        )
    }
}

extension NativePose {
    /// The asset the camera draws as the pose reference: the extracted line art only.
    ///
    /// `imageURL` is the source photo (card / hero art). Drawing it over a live preview would put a
    /// photo on the camera, so a pose whose extraction never landed falls back to the stick figure
    /// (`guideFallback`) instead of reaching for `imageURL`.
    var cameraGuideURL: URL? { guideURL }
}

// MARK: - Camera screen

struct CameraScreen: View {
    @Binding var guide: NativePose?
    let poseService: any PoseServing
    /// Dismisses the camera back to the Poses tab. Owned by `AppFeatureRoot`.
    let onClose: () -> Void
    /// Opens the Gallery tab from the shutter-rail thumbnail.
    let onOpenGallery: () -> Void
    @StateObject private var model: CameraViewModel
    @StateObject private var posePickerModel: PosePickerViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Focus returns to the More control when the Camera Tools popup is dismissed
    /// (outside tap / Escape / VoiceOver escape).
    @FocusState private var isToolsButtonFocused: Bool
    /// In-flight pinch / twist / drag, folded into `model.guideTransform` when the gesture ends.
    @GestureState private var guideGestureDelta = GuideTransform.Delta.identity

    init(
        guide: Binding<NativePose?>,
        poseService: any PoseServing,
        onClose: @escaping () -> Void = {},
        onOpenGallery: @escaping () -> Void = {},
        model: @autoclosure @escaping () -> CameraViewModel = CameraViewModel()
    ) {
        _guide = guide
        self.poseService = poseService
        self.onClose = onClose
        self.onOpenGallery = onOpenGallery
        _model = StateObject(wrappedValue: model())
        _posePickerModel = StateObject(wrappedValue: PosePickerViewModel(service: poseService))
    }

    /// Legacy UIKit host and previews without an injected pose service.
    init() {
        self.init(guide: .constant(nil), poseService: PreviewPoseService())
    }

    private var isAuthorized: Bool { model.coordinator.state.permission == .authorized }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                viewport
                CameraShutterRail(
                    thumbnailURL: model.latestThumbnailURL,
                    isBusy: model.coordinator.state.isCaptureInFlight,
                    controlsEnabled: model.coordinator.state.captureEnabled,
                    onOpenGallery: onOpenGallery,
                    onCapture: { model.capture() },
                    onSwitchCamera: { model.switchCamera() }
                )
            }

            // `.nb-pose-picker-sheet` — an in-place overlay on Camera, never a pushed route, so
            // selecting a pose returns directly with no picker entry left on the navigation stack.
            if model.showPosePicker {
                PosePickerSheet(
                    model: posePickerModel,
                    onClose: { model.closePosePicker() },
                    onSelect: { pose in
                        guide = pose
                        model.closePosePicker()
                    }
                )
                .zIndex(2)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.showPosePicker)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: model.showCameraTools)
        .ignoresSafeArea(.container, edges: .top)
        .neoHiddenNavigationBar()
        .preferredColorScheme(.dark)
        .task { await model.onAppear() }
        .onAppear { model.guideAppeared(hasGuide: guide != nil) }
        .onDisappear { model.onDisappear() }
        .task(id: model.showPosePicker) {
            if model.showPosePicker {
                // R7: monitor only while the sheet is presented.
                posePickerModel.startMonitoring()
                // R6: reopen always retries unless a grid is already in hand, so a dismissed failure
                // (or a load that failed after dismissal) cannot strand the sheet.
                if case .loaded = posePickerModel.state { return }
                await posePickerModel.load()
            } else {
                posePickerModel.prepareForDismissal()
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: model.coordinator.onForeground()
            case .background:
                model.coordinator.onBackground()
                Task { await model.flushSettings() }
            default: break
            }
        }
        .onChange(of: model.cameraControlsEnabled) { enabled in
            if !enabled { model.closeCameraTools() }
        }
        .onChange(of: guide?.id) { _ in model.guideDidChange(hasGuide: guide != nil) }
    }

    // MARK: Viewport — full-bleed `.nb-camera-viewport--immersive`

    private var viewport: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .bottomTrailing) {
                cameraCanvas(size: size)

                // `.nb-camera-tools-menu` — anchored popup at `right: 16pt, bottom: 120pt`
                // (16 + 44 + 8 + 44 + 8: above the Choose pose control), transform-origin bottom
                // right. No scrim, no handle, no app-bar Close.
                if model.showCameraTools {
                    // Outside tap dismisses without a visible scrim.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissCameraTools() }
                        .accessibilityHidden(true)

                    CameraToolsPopup(
                        flashSetting: model.flashSetting,
                        isGridVisible: model.isGridVisible,
                        controlsEnabled: model.cameraControlsEnabled,
                        hasPose: guide != nil,
                        isPoseGuideVisible: model.isPoseGuideVisible,
                        guideOpacity: model.guideOpacity,
                        guideLineColor: model.guideLineColor,
                        popupWidth: min(CameraProto.popupWidth, size.width - CameraProto.spaceMD * 2),
                        popupMaxHeight: min(size.height * 0.62, CameraProto.popupMaxHeight),
                        onFlashTap: { model.cycleFlash() },
                        onGridToggle: { model.toggleGrid() },
                        onPoseGuideVisibilityToggle: { model.togglePoseGuideVisibility() },
                        onGuideOpacityChange: { model.setGuideOpacity($0) },
                        onGuideLineColorChange: { model.setGuideLineColor($0) },
                        onDismiss: { dismissCameraTools() }
                    )
                    .padding(.trailing, CameraProto.controlInset)
                    .padding(.bottom, CameraProto.popupBottomOffset)
                    .transition(.opacity
                        .combined(with: .offset(y: CameraProto.spaceSM))
                        .combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
                }
            }
        }
        .overlay(alignment: .top) {
            topControls
                .padding(.horizontal, CameraProto.controlInset)
                .padding(.top, CameraProto.topControlsTop)
        }
        .overlay(alignment: .bottom) {
            viewportFooter
                .padding(.horizontal, CameraProto.controlInset)
                .padding(.bottom, CameraProto.controlInset)
        }
    }

    private func dismissCameraTools() {
        guard model.showCameraTools else { return }
        model.closeCameraTools()
        // Focus returns to the More control (`guide-picker.js` `setOpen(false)` → `openButton.focus()`).
        isToolsButtonFocused = true
    }

    private func cameraCanvas(size: CGSize) -> some View {
        ZStack {
            CameraProto.dark

            if isAuthorized {
                CameraPreview(session: model.camera.session)
            }

            verticalScrims

            // `.nb-camera-pose-reference` — `top:16%; right:18%; bottom:14%; left:18%`.
            // The static four-corner framing overlay is gone (report §3.2).
            if let guide, model.isPoseGuideVisible {
                guideOverlay(for: guide)
                    .frame(
                        width: size.width * (1 - CameraProto.poseReferenceHorizontalInset * 2),
                        height: size.height * (1 - CameraProto.poseReferenceTopInset - CameraProto.poseReferenceBottomInset)
                    )
                    .position(
                        x: size.width / 2,
                        y: size.height * CameraProto.poseReferenceTopInset
                            + size.height * (1 - CameraProto.poseReferenceTopInset - CameraProto.poseReferenceBottomInset) / 2
                    )
            }

            if model.isGridVisible {
                CameraFramingGrid()
            }

            // Pinch / twist / drag anywhere on the preview places the pose reference; the reference
            // itself stays non-interactive so a thin skeleton is never a hard touch target.
            if guide != nil, model.isPoseGuideVisible, isAuthorized {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.resetGuideTransform() }
                    .gesture(guidePlacementGesture)
                    .accessibilityHidden(true)
            }

            // `.nb-camera-status` — capture feedback only (saved / failed). It is anchored
            // `left: 16 / right: 16` at `bottom: 112` (`--nb-space-md` + `--nb-touch-min` +
            // `--nb-space-sm` + `--nb-touch-min`) — just above the More + Choose-pose cluster. Picking
            // a pose shows no chip: the reference itself is the feedback.
            if let status = model.statusMessage {
                statusBanner(status)
                    .position(x: size.width / 2,
                              y: size.height - CameraProto.statusBottomInset - 18)
            }

            if !isAuthorized {
                permissionGate
            }
        }
        .clipped()
    }

    /// `.nb-camera-viewport__top-scrim` (190px) / `__bottom-scrim` (170px).
    private var verticalScrims: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [CameraProto.dark.opacity(0.68), CameraProto.dark.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 190)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [CameraProto.dark.opacity(0), CameraProto.dark.opacity(0.54)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 170)
        }
        .allowsHitTesting(false)
    }

    /// `.nb-camera-viewport__top-controls` — only Close remains; More moved to the lower right.
    private var topControls: some View {
        HStack(spacing: 0) {
            CameraActionControl(
                systemImage: "xmark",
                accessibilityLabel: "Close camera",
                action: onClose
            )
            Spacer(minLength: 0)
        }
    }

    /// Lower-right control column: More (`.nb-camera-viewport__tools-btn`, bottom: 68pt) directly
    /// above Choose pose (`.nb-camera-viewport__profile-btn`, bottom: 16pt).
    private var viewportFooter: some View {
        ZStack {
            CameraZoomPill(level: model.zoomLevel) { model.cycleZoom() }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: CameraProto.spaceSM) {
                    CameraActionControl(
                        systemImage: "ellipsis",
                        rotatesIcon: true,
                        accessibilityLabel: "Open camera tools",
                        identifier: "camera.tools",
                        action: { model.toggleCameraTools() }
                    )
                    .focused($isToolsButtonFocused)

                    Button {
                        model.openPosePicker()
                    } label: {
                        Image(systemName: "photo")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AIPoseColor.foreground)
                            .frame(width: CameraProto.surface, height: CameraProto.surface)
                    }
                    .buttonStyle(NeoSurfaceStyle(fill: AIPoseColor.accentBlue))
                    .frame(width: CameraProto.touch, height: CameraProto.touch, alignment: .bottom)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Choose a pose")
                    .accessibilityIdentifier("camera.choosePose")
                }
            }
        }
    }

    private var guidePlacementGesture: some Gesture {
        SimultaneousGesture(
            SimultaneousGesture(MagnificationGesture(), RotationGesture()),
            DragGesture()
        )
        .updating($guideGestureDelta) { value, state, _ in
            state = Self.delta(from: value)
        }
        .onEnded { value in
            model.commitGuideGesture(Self.delta(from: value))
        }
    }

    private static func delta(
        from value: SimultaneousGesture<SimultaneousGesture<MagnificationGesture, RotationGesture>, DragGesture>.Value
    ) -> GuideTransform.Delta {
        GuideTransform.Delta(
            scale: value.first?.first ?? 1,
            rotation: value.first?.second ?? .zero,
            translation: value.second?.translation ?? .zero
        )
    }

    @ViewBuilder
    private func guideOverlay(for guide: NativePose) -> some View {
        let placement = model.guideTransform.applying(guideGestureDelta)
        Group {
            if let url = guide.cameraGuideURL {
                // The guide image covers most of the viewport, so it is decoded at screen size
                // instead of at whatever the source asset happens to be.
                KFImage(url)
                    .setProcessor(AppImage.downsample(points: FullScreenImageTarget.drawSize, contentMode: .fit))
                    .placeholder { guideFallback(for: guide) }
                    .onFailureView { guideFallback(for: guide) }
                    .loadDiskFileSynchronously(false)
                    // The extracted pose is line art on a transparent background, so it is drawn as
                    // a template and the Line colour setting becomes its stroke colour.
                    .contentConfigure { image, _ in
                        image.renderingMode(.template).resizable().scaledToFit()
                    }
                    .foregroundColor(model.guideLineColor.color)
            } else {
                guideFallback(for: guide)
            }
        }
        .opacity(model.guideOpacity)
        .scaleEffect(x: model.guideFlipped ? -1 : 1, y: 1)
        .scaleEffect(placement.scale)
        .rotationEffect(placement.rotation)
        .offset(placement.offset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Same stand-in the `AsyncImage` placeholder used before the guide asset loads. The stroke
    /// follows the tools popup Line colour (`--nb-camera-pose-line-color`).
    private func guideFallback(for guide: NativePose) -> StickFigureView {
        StickFigureView(kind: .resolve(name: guide.name, category: guide.category, index: 0),
                        lineColor: model.guideLineColor.color)
    }

    private func statusBanner(_ status: String) -> some View {
        Text(status)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(AIPoseColor.foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(statusTone)
            .clipShape(RoundedRectangle(cornerRadius: CameraProto.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: CameraProto.radiusSmall)
                .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth))
            .shadow(color: AIPoseColor.border, radius: 0,
                    x: CameraProto.shadowSmall, y: CameraProto.shadowSmall)
            .padding(.horizontal, CameraProto.controlInset)
    }

    private var statusTone: Color {
        switch model.coordinator.state.phase {
        case .captureError:
            return AIPoseColor.primary
        case .captureSucceeded:
            return AIPoseColor.success
        default:
            return model.coordinator.state.lastFailure == nil ? AIPoseColor.success : AIPoseColor.primary
        }
    }

    /// `.nb-camera-permission` — dark scrim, accent-yellow camera tile, white copy.
    private var permissionGate: some View {
        ZStack {
            CameraProto.dark.opacity(0.9)

            VStack(spacing: 0) {
                Image(systemName: "camera")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AIPoseColor.foreground)
                    .frame(width: 56, height: 56)
                    .background(AIPoseColor.accentYellow)
                    .clipShape(RoundedRectangle(cornerRadius: CameraProto.radiusMedium))
                    .overlay(RoundedRectangle(cornerRadius: CameraProto.radiusMedium)
                        .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth))
                    .shadow(color: AIPoseColor.border, radius: 0,
                            x: CameraProto.shadow, y: CameraProto.shadow)
                    .padding(.bottom, 16)

                Text("Camera access is off")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)

                Text("Allow camera access in Settings to line up and capture your pose.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 270)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                if model.coordinator.state.permission == .denied
                    || model.coordinator.state.permission == .restricted {
                    PermissionActionButton(title: "Open Settings", fill: AIPoseColor.surface) {
                        openSystemSettings()
                    }
                } else {
                    PermissionActionButton(title: "Allow Camera", fill: AIPoseColor.accentYellow) {
                        model.requestPermission()
                    }
                }
            }
            .padding(CameraProto.spaceXL)
        }
        .accessibilityElement(children: .contain)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct PermissionActionButton: View {
    let title: String
    var fill: Color = AIPoseColor.surface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .padding(.horizontal, CameraProto.spaceMD)
                .frame(minHeight: CameraProto.touch)
        }
        .buttonStyle(NeoSurfaceStyle(fill: fill, shadowOffset: CameraProto.shadow))
    }
}

// MARK: - Prototype metrics & palette
//
// Numbers are absolute point values taken from `docs/prototype/styles/tokens.css`,
// `components/camera-viewport.css` and `components/camera-guide.css`. They are deliberately
// *not* `AIPoseSpacing.*` because the prototype spacing scale differs from the native one
// (proto `md` = 16 while `AIPoseSpacing.md` = 12).

enum CameraProto {
    static let dark = AIPoseColor.foreground          // --nb-color-dark #121212
    static let borderWidth: CGFloat = 2               // --nb-border-width-thick
    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 10             // --nb-radius-medium
    static let radiusLarge: CGFloat = 14              // --nb-radius-large
    static let pickerTopRadius: CGFloat = 22          // `.nb-pose-picker-panel` 22px 22px 0 0
    static let shadow: CGFloat = 3                    // --nb-shadow-offset
    static let shadowSmall: CGFloat = 1.5             // --nb-shadow-offset-small
    static let shadowLarge: CGFloat = 5               // --nb-shadow-offset-large
    static let touch: CGFloat = 44                    // --nb-touch-min
    static let surface: CGFloat = 32                  // .nb-btn__compact-surface
    static let spaceXS: CGFloat = 4
    static let spaceSM: CGFloat = 8
    static let spaceCompact: CGFloat = 12             // --nb-space-compact
    static let spaceMD: CGFloat = 16
    static let spaceLG: CGFloat = 24
    static let spaceXL: CGFloat = 32

    // `.nb-camera-viewport__top-controls`
    static let topControlsTop: CGFloat = 62
    static let controlInset: CGFloat = 16

    // `.nb-camera-pose-reference`
    static let poseReferenceTopInset: CGFloat = 0.16
    static let poseReferenceBottomInset: CGFloat = 0.14
    static let poseReferenceHorizontalInset: CGFloat = 0.18

    // `.nb-camera-tools-menu`
    static let popupWidth: CGFloat = 264
    static let popupMaxHeight: CGFloat = 420
    /// `bottom: calc(16 + 44 + 8 + 44 + 8)` — above the Choose pose control.
    static let popupBottomOffset: CGFloat = spaceMD + touch + spaceSM + touch + spaceSM

    // `.nb-pose-picker-panel`
    static let pickerHandleWidth: CGFloat = 42
    static let pickerHandleHeight: CGFloat = 4
    static let pickerMaxHeight: CGFloat = 700
    static let pickerMinHeight: CGFloat = 420
    static let pickerHeightFraction: CGFloat = 0.82

    // `.nb-shutter-bar--redesign`
    static let railHeight: CGFloat = 124
    static let railInset: CGFloat = 24
    static let railControl: CGFloat = 48
    static let shutterSize: CGFloat = 72
    static let zoomToggle: CGFloat = 36

    // `.nb-camera-status`
    static let statusBottomInset: CGFloat = 112
}

// MARK: - Neo-brutalist primitives (private to the camera feature)
//
// `NeoSquareIconButton` (36pt, 1.5pt border, 2pt shadow) and `NeoCardModifier` (12pt radius,
// 4pt shadow) do not match the camera prototype, so the camera screen carries its own
// screen-local primitives instead of changing the shared design system.

private struct NeoSurfaceStyle: ButtonStyle {
    var fill: Color = AIPoseColor.surface
    var radius: CGFloat = CameraProto.radiusMedium
    var shadowOffset: CGFloat = CameraProto.shadowSmall
    var circle: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        // `box-shadow: Npx Npx 0 #000` is drawn as a hard offset shape rather than a
        // `View.shadow` so the silhouette is always solid (SwiftUI renders a shadow of a
        // `.background`-filled circle as a ring instead of a disc).
        let depth = pressed ? 0 : shadowOffset
        let shift = pressed ? shadowOffset : 0

        return Group {
            if circle {
                configuration.label
                    .background(fill)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth))
                    .background(Capsule().fill(AIPoseColor.border).offset(x: depth, y: depth))
                    .offset(x: shift, y: shift)
            } else {
                configuration.label
                    .background(fill)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                    .overlay(RoundedRectangle(cornerRadius: radius)
                        .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth))
                    .background(RoundedRectangle(cornerRadius: radius)
                        .fill(AIPoseColor.border)
                        .offset(x: depth, y: depth))
                    .offset(x: shift, y: shift)
            }
        }
    }
}

/// `44x44` transparent hit area wrapping a `32x32` neo surface (`.nb-btn--compact-action`).
private struct CameraActionControl: View {
    let systemImage: String
    var rotatesIcon: Bool = false
    let accessibilityLabel: String
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .rotationEffect(.degrees(rotatesIcon ? 90 : 0))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(width: CameraProto.surface, height: CameraProto.surface)
        }
        .buttonStyle(NeoSurfaceStyle())
        .frame(width: CameraProto.touch, height: CameraProto.touch, alignment: .center)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// `.nb-camera-viewport__zoom-btn` + `.nb-camera-zoom-toggle` (36pt circle, centred).
private struct CameraZoomPill: View {
    let level: CameraZoomLevel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(level.label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(width: CameraProto.zoomToggle, height: CameraProto.zoomToggle)
        }
        .buttonStyle(NeoSurfaceStyle(circle: true))
        .frame(width: CameraProto.touch, height: CameraProto.touch, alignment: .bottom)
        .contentShape(Rectangle())
        .accessibilityLabel("Zoom \(level.label)")
    }
}

/// `.nb-camera-viewport__grid-overlay` — hairline thirds at 30% white.
private struct CameraFramingGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for step in 1...2 {
                    let x = proxy.size.width * CGFloat(step) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))

                    let y = proxy.size.height * CGFloat(step) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Camera Tools popup (`.nb-camera-tools-menu`)

/// Anchored popup, not a bottom sheet: absolutely positioned bottom-right with
/// `transform-origin: bottom right`, dark panel, `3px 3px 0 #000` shadow, no scrim, no handle,
/// no app-bar Close (`camera-viewport.css` `.nb-camera-tools-menu`).
///
/// The popup hugs its content up to `max-height: min(62vh, 420px)` with `overflow-y: auto`, so the
/// content height is measured once through a preference and the scroll view is bounded to it.
private struct CameraToolsPopup: View {
    let flashSetting: CameraFlashSetting
    let isGridVisible: Bool
    let controlsEnabled: Bool
    let hasPose: Bool
    let isPoseGuideVisible: Bool
    let guideOpacity: Double
    let guideLineColor: GuideLineColor
    let popupWidth: CGFloat
    let popupMaxHeight: CGFloat
    let onFlashTap: () -> Void
    let onGridToggle: () -> Void
    let onPoseGuideVisibilityToggle: () -> Void
    let onGuideOpacityChange: (Double) -> Void
    let onGuideLineColorChange: (GuideLineColor) -> Void
    let onDismiss: () -> Void

    @State private var naturalContentHeight: CGFloat?

    var body: some View {
        ScrollView {
            content
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CameraToolsContentHeightKey.self,
                            value: geo.size.height
                        )
                    }
                )
        }
        .onPreferenceChange(CameraToolsContentHeightKey.self) { naturalContentHeight = $0 }
        .frame(maxWidth: popupWidth, alignment: .leading)
        .modifier(CameraToolsPopupHeight(naturalHeight: naturalContentHeight, maxHeight: popupMaxHeight))
        .background(
            RoundedRectangle(cornerRadius: CameraProto.radiusMedium)
                .fill(AIPoseColor.border)
                .offset(x: CameraProto.shadow, y: CameraProto.shadow)
        )
        .background(CameraProto.dark)
        .overlay(
            RoundedRectangle(cornerRadius: CameraProto.radiusMedium)
                .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: CameraProto.radiusMedium))
        .accessibilityElement(children: .contain)
        // VoiceOver's local Back (two-finger Z scrub) — the native equivalent of Escape.
        .accessibilityAction(.escape) { onDismiss() }
    }

    private var content: some View {
        VStack(spacing: CameraProto.spaceSM) {
            row(
                systemImage: flashSetting.symbolName,
                title: "Flash",
                value: flashSetting.toolsDisplayName,
                accessibilityLabel: "Flash \(flashSetting.toolsDisplayName), tap to change",
                identifier: "camera.tools.flash",
                action: onFlashTap
            )
            gridRow

            if hasPose {
                // `.nb-camera-tools-divider` + `.nb-camera-tools-section h3 "Pose guide"`.
                Rectangle()
                    .fill(Color.white.opacity(0.26))
                    .frame(height: 1)
                    .padding(.vertical, 2)

                Text("Pose guide")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)

                row(
                    systemImage: nil,
                    title: "Pose guide",
                    value: isPoseGuideVisible ? "Shown" : "Hidden",
                    accessibilityLabel: isPoseGuideVisible ? "Hide pose guide" : "Show pose guide",
                    identifier: "camera.tools.poseGuide",
                    action: onPoseGuideVisibilityToggle
                )
                opacityRow
                lineColorRow
            }
        }
        .padding(CameraProto.spaceSM)
    }

    /// `.nb-camera-setting-row` — white fill, 2pt black border, radius 10, min-height 44pt,
    /// 12pt horizontal padding, bold 14pt, pressed translate 1.5pt with pressed shadow.
    private func row(
        systemImage: String?,
        title: String,
        value: String?,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: CameraProto.spaceSM) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                Text(title)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .foregroundStyle(AIPoseColor.accentYellow)
                }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AIPoseColor.foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: CameraProto.touch, alignment: .leading)
        }
        .buttonStyle(NeoSurfaceStyle(fill: AIPoseColor.surface))
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

    private var gridRow: some View {
        HStack(spacing: CameraProto.spaceSM) {
            Image(systemName: "grid")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 18, height: 18)
            Text("Grid")
            Spacer(minLength: 0)
            gridSwitch
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(AIPoseColor.foreground)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: CameraProto.touch, alignment: .leading)
        .background(AIPoseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: CameraProto.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: CameraProto.radiusMedium)
            .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth))
        .background(RoundedRectangle(cornerRadius: CameraProto.radiusMedium)
            .fill(AIPoseColor.border)
            .offset(x: CameraProto.shadowSmall, y: CameraProto.shadowSmall))
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel("Show camera grid")
        .accessibilityIdentifier("camera.tools.grid")
    }

    /// `.nb-switch` / `.nb-switch__slider` / `::before` (`styles/components/toggle.css`), mapped by
    /// value. `base.css:18` sets `box-sizing: border-box`, so every figure below is the OUTER box and
    /// the borders are drawn inside it (`strokeBorder`, not `stroke`):
    ///   track  48x26, fill `--nb-color-white` #FFFFFF, border `--nb-border-thin` 1.5pt #000000,
    ///          radius `--nb-radius-large` 14pt (wider than half the 26pt track, so it reads as a capsule)
    ///   knob   16x16, fill #FFFFFF, border 1.5pt #000000, `left: 3px` inset
    ///   checked track fill `--nb-color-accent-blue` #7FBBE6, knob `translateX(20px)`
    ///   transition `--nb-transition-fast` 0.1s cubic-bezier(0.16, 1, 0.3, 1)
    private var gridSwitch: some View {
        Button(action: onGridToggle) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isGridVisible ? AIPoseColor.accentBlue : AIPoseColor.surface)
                    .overlay(Capsule().strokeBorder(AIPoseColor.border, lineWidth: 1.5))
                    .frame(width: 48, height: 26)
                Circle()
                    .fill(AIPoseColor.surface)
                    .overlay(Circle().strokeBorder(AIPoseColor.border, lineWidth: 1.5))
                    .frame(width: 16, height: 16)
                    .padding(.leading, 3)
                    .offset(x: isGridVisible ? 20 : 0)
            }
            .animation(.easeOut(duration: 0.1), value: isGridVisible)
        }
        .buttonStyle(.plain)
        .disabled(!controlsEnabled)
        .accessibilityLabel("Show camera grid")
        .accessibilityIdentifier("camera.tools.grid")
        .accessibilityAddTraits(isGridVisible ? [.isSelected] : [])
    }

    /// `.nb-camera-tool-slider-row` — plain white copy on the dark panel (not a white card),
    /// `min 10% – max 100%`, value output in accent yellow.
    private var opacityRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Opacity")
                Spacer(minLength: 0)
                Text("\(Int((guideOpacity * 100).rounded()))%")
                    .foregroundStyle(AIPoseColor.accentYellow)
            }
            Slider(value: Binding(
                get: { guideOpacity },
                set: { onGuideOpacityChange($0) }
            ), in: 0.1...1)
            .disabled(!controlsEnabled)
            .accessibilityLabel("Pose guide opacity \(Int((guideOpacity * 100).rounded())) percent")
            .accessibilityIdentifier("camera.tools.opacity")
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.white)
        .padding(2)
    }

    /// `.nb-camera-tool-choice-row` — "Line color" heading + Black | White choices
    /// (selected choice fills `--nb-color-accent-blue`).
    private var lineColorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Line color")
            HStack(spacing: CameraProto.spaceSM) {
                choiceButton(.black, identifier: "camera.tools.lineColor.black")
                choiceButton(.white, identifier: "camera.tools.lineColor.white")
            }
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.white)
        .padding(2)
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
    }

    private func choiceButton(_ color: GuideLineColor, identifier: String) -> some View {
        Button {
            onGuideLineColorChange(color)
        } label: {
            Text(color.label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(NeoSurfaceStyle(
            fill: guideLineColor == color ? AIPoseColor.accentBlue : AIPoseColor.surface,
            radius: CameraProto.radiusSmall
        ))
        .accessibilityLabel("\(color.label) pose line color")
        .accessibilityAddTraits(guideLineColor == color ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

private struct CameraToolsContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// `max-height: min(62vh, 420px)` + `overflow-y: auto`, while hugging the content when it is
/// shorter than the cap (the prototype menu is not a fixed-height panel).
private struct CameraToolsPopupHeight: ViewModifier {
    let naturalHeight: CGFloat?
    let maxHeight: CGFloat

    func body(content: Content) -> some View {
        if let naturalHeight, naturalHeight > 0 {
            content.frame(height: min(naturalHeight, maxHeight))
        } else {
            content.frame(maxHeight: maxHeight)
        }
    }
}

// MARK: - Shutter rail

private struct CameraShutterRail: View {
    let thumbnailURL: URL?
    let isBusy: Bool
    let controlsEnabled: Bool
    let onOpenGallery: () -> Void
    let onCapture: () -> Void
    let onSwitchCamera: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            thumbnailButton
            Spacer(minLength: 0)
            shutterButton
            Spacer(minLength: 0)
            flipButton
        }
        .padding(.horizontal, CameraProto.railInset)
        .frame(maxWidth: .infinity)
        .frame(height: CameraProto.railHeight)
        // Cream covers the 124pt rail only; the dark canvas behind it is a `ShapeStyle`
        // background, which SwiftUI extends into the home-indicator inset below the rail
        // (matching `.nb-camera-phone { background-color: dark }` + transparent footer).
        .background(AIPoseColor.background, ignoresSafeAreaEdges: [])
        .background(CameraProto.dark)
        .overlay(alignment: .top) {
            AIPoseColor.border.frame(height: CameraProto.borderWidth)
        }
    }

    private var thumbnailButton: some View {
        Button(action: onOpenGallery) {
            Group {
                if let thumbnailURL {
                    // 48pt control: decode a 48pt thumbnail, not the full-resolution capture the
                    // previous `UIImage(contentsOfFile:)` path pulled in synchronously.
                    KFImage(thumbnailURL)
                        .setProcessor(AppImage.downsample(squarePoints: CameraProto.railControl))
                        .placeholder { AIPoseColor.surface }
                        .onFailureView { AIPoseColor.surface }
                        .loadDiskFileSynchronously(false)
                        .contentConfigure { image, _ in
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                } else {
                    AIPoseColor.surface
                }
            }
            .frame(width: CameraProto.railControl, height: CameraProto.railControl)
            .clipShape(RoundedRectangle(cornerRadius: CameraProto.radiusMedium))
        }
        .buttonStyle(NeoSurfaceStyle(
            fill: AIPoseColor.surface,
            radius: CameraProto.radiusMedium,
            shadowOffset: CameraProto.shadowSmall
        ))
        .accessibilityLabel("Open gallery")
    }

    private var shutterButton: some View {
        Button(action: onCapture) {
            CameraShutterSpinner()
                .opacity(isBusy ? 1 : 0)
                .frame(width: CameraProto.shutterSize, height: CameraProto.shutterSize)
        }
        .buttonStyle(NeoSurfaceStyle(
            fill: AIPoseColor.primary,
            shadowOffset: CameraProto.shadowLarge,
            circle: true
        ))
        .opacity(controlsEnabled || isBusy ? 1 : 0.45)
        .disabled(!controlsEnabled || isBusy)
        .accessibilityLabel("Capture photo")
        .accessibilityIdentifier("camera.shutter")
    }

    private var flipButton: some View {
        Button(action: onSwitchCamera) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(width: CameraProto.railControl, height: CameraProto.railControl)
        }
        .buttonStyle(NeoSurfaceStyle(
            fill: AIPoseColor.surface,
            radius: CameraProto.radiusMedium,
            shadowOffset: CameraProto.shadow
        ))
        .opacity(controlsEnabled ? 1 : 0.45)
        .disabled(!controlsEnabled)
        .accessibilityLabel("Switch to front camera")
    }
}

private struct CameraShutterSpinner: View {
    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(AIPoseColor.foreground.opacity(0.22), lineWidth: 3)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(AIPoseColor.foreground, style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                .rotationEffect(.degrees(angle - 90))
        }
        .frame(width: 24, height: 24)
        .onAppear {
            withAnimation(.linear(duration: 0.75).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
    }
}

// MARK: - Pose picker (camera-local bottom sheet, `.nb-pose-picker-*`)

/// Camera-local pose picker (`camera-guide.css` + `guide-picker.js`). It filters the loaded
/// catalogue locally — the prototype's `render()` re-renders from `getAvailablePoses()` on every
/// keystroke and only hits the "network" fixture once.
@MainActor
final class PosePickerViewModel: ObservableObject {
    @Published var state: Loadable<[NativePose]> = .idle
    @Published var query: String = ""
    /// `forcedState === 'offline'`: the sheet keeps showing results with an offline notice.
    @Published private(set) var isOffline = false
    private let service: any PoseServing
    /// R7: reachability is created on presentation and torn down on dismissal — `NWPathMonitor`
    /// `cancel()` is terminal, so each presentation gets a fresh monitor rather than one running for
    /// the whole lifetime of the camera screen.
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "aipose.pose-picker.path")

    init(service: any PoseServing) {
        self.service = service
    }

    deinit {
        pathMonitor?.cancel()
    }

    /// Start reachability monitoring while the sheet is on screen (R7).
    func startMonitoring() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor [weak self] in
                self?.isOffline = offline
            }
        }
        pathMonitor = monitor
        monitor.start(queue: monitorQueue)
    }

    /// Stop monitoring and forget the last reading, so a stale "offline" cannot outlive the sheet.
    func stopMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
        isOffline = false
    }

    /// Sheet dismissal (R6). The prototype's offline card carries no retry action, so a failed fetch
    /// while offline would strand the sheet permanently; dropping the result means reopening always
    /// retries. Also stops reachability monitoring (R7).
    func prepareForDismissal() {
        state = .idle
        query = ""
        stopMonitoring()
    }

    func load() async {
        state = .loading
        do {
            let poses = try await service.poses(query: nil)
            state = poses.isEmpty ? .empty : .loaded(poses)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Local title filter over the loaded catalogue (`guide-picker.js` `render()`).
    var filteredPoses: [NativePose] {
        guard case .loaded(let poses) = state else { return [] }
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return poses }
        return poses.filter { $0.name.lowercased().contains(term) }
    }

    /// Shared-card tone the picker renders, or `nil` when it draws the grid.
    ///
    /// Base tones come from the pure `Loadable.stateTone` mapper; the two overlays mirror
    /// `guide-picker.js` exactly: `forcedState === 'offline'` swaps a failed load to `.offline` and
    /// adds a notice above an already-loaded grid, while an empty *catalogue* keeps `.empty`
    /// regardless of connectivity. This is the only reachable producer of `.offline` in the app, so
    /// the mapping is load-bearing evidence for the tone that cannot be screenshotted.
    var stateTone: FeatureStateTone? {
        switch state {
        case .idle, .loading, .empty:
            return state.stateTone
        case .failed:
            return isOffline ? .offline : state.stateTone
        case .loaded:
            // R4: `guide-picker.js:130-140` returns early on an empty result set *before* the offline
            // notice is reached, so a non-matching query keeps the "No poses match …" card even while
            // offline. Checking `isOffline` first (as this did) inverted the prototype's precedence.
            if filteredPoses.isEmpty { return .empty }
            return nil
        }
    }

    /// R5: `guide-picker.js:145-148` populates the grid first and only then renders the offline
    /// notice, and that call never hides the grid — so offline is a notice *above* an already
    /// populated grid, not a card replacing it. Matches the card's own copy, "Showing your last
    /// available poses."
    var showsOfflineNotice: Bool {
        guard isOffline, !filteredPoses.isEmpty else { return false }
        if case .loaded = state { return true }
        return false
    }

    /// Distinguishes the `.empty` card's two copies: a no-match query versus an empty catalogue.
    var emptyIsNoMatch: Bool {
        if case .empty = state { return false }
        return !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    #if DEBUG
    /// Test seam: reachability is process-wide and cannot be driven from a unit test, but the
    /// `.offline` card has no other producer in the app and no screenshot path either.
    func setOfflineForTesting(_ offline: Bool) { isOffline = offline }
    #endif

    /// `pose-picker-search__clear`: resets to the full grid without refetching.
    func clearSearch() {
        query = ""
    }
}

/// `.nb-pose-picker-sheet` — camera-local bottom sheet: Camera stays visible behind it as the
/// parent context; panel `height: min(82%, 700px)`, `min-height: 420px`, cream background, 2pt
/// border with **no bottom border**, radius `22 22 0 0`, `0 -4px 0 #000` shadow, handle, app-bar
/// Close and **no Back button**.
private struct PosePickerSheet: View {
    @ObservedObject var model: PosePickerViewModel
    @ObservedObject private var aspectRatioCache = PoseAspectRatioCache.shared
    let onClose: () -> Void
    let onSelect: (NativePose) -> Void
    @State private var columnByPoseID: [String: Int] = [:]

    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct PickerItem: Identifiable {
        let index: Int
        let pose: NativePose
        var id: String { pose.id }
    }

    var body: some View {
        GeometryReader { proxy in
            let panelHeight = max(
                min(proxy.size.height * CameraProto.pickerHeightFraction, CameraProto.pickerMaxHeight),
                CameraProto.pickerMinHeight
            )
            ZStack(alignment: .bottom) {
                backdrop
                panel(height: panelHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .ignoresSafeArea()
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 18)))
        // R18 probe: `.isModal` was applied here, on the GeometryReader root. Applied to a container
        // that is not itself an accessibility element, SwiftUI collapses the subtree it wraps — the
        // panel's header and search field vanished from the tree while only the ScrollView's contents
        // stayed. Moving it onto the panel (a real container, declared with `children: .contain`)
        // keeps the modal trait and preserves the descendants.
    }

    /// `.nb-pose-picker-sheet__backdrop` — `rgba(18, 18, 18, 0.48)`.
    private var backdrop: some View {
        CameraProto.dark
            .opacity(0.48)
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
    }

    private func panel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            handle
            header
            searchField
            scrollContent
        }
        .padding(EdgeInsets(
            top: 10,
            leading: CameraProto.spaceMD,
            bottom: CameraProto.spaceMD,
            trailing: CameraProto.spaceMD
        ))
        .frame(maxHeight: height, alignment: .top)
        .frame(maxWidth: .infinity)
        // `.nb-pose-picker-panel` is opaque `--nb-color-bg` (#FBF6EF). A later `.background` renders
        // BEHIND an earlier one, so the cream fill must be the FIRST (innermost) background and the
        // hard `box-shadow: 0 -4px 0 var(--nb-color-border)` shape the SECOND. Inverted, the
        // full-size black shape painted over the panel and left only a 4pt cream sliver at the
        // bottom — dark text on black, and on a real device over the live camera feed.
        .background(
            RoundedTopShape(radius: CameraProto.pickerTopRadius)
                .fill(AIPoseColor.background)
        )
        .background(
            RoundedTopShape(radius: CameraProto.pickerTopRadius)
                .fill(AIPoseColor.border)
                .offset(y: -CameraProto.shadow)
        )
        .overlay(
            TopEdgeBorderShape(radius: CameraProto.pickerTopRadius)
                .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth)
        )
        // The sheet content is light (cream panel) while Camera stays dark behind it; without this
        // the dark scheme would render the search TextField's text white-on-white.
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 18)))
    }

    /// `.nb-pose-picker-panel__handle` — 42x4 dark, centred.
    private var handle: some View {
        Capsule()
            .fill(AIPoseColor.foreground)
            .frame(width: CameraProto.pickerHandleWidth, height: CameraProto.pickerHandleHeight)
            .padding(.bottom, CameraProto.spaceMD)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// `.nb-pose-picker-panel__header` — nav-title 20pt bold + app-bar Close. No Back button.
    private var header: some View {
        HStack(alignment: .top, spacing: CameraProto.spaceSM) {
            Text("Choose a pose")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            CameraActionControl(
                systemImage: "xmark",
                accessibilityLabel: "Close pose picker",
                identifier: "posePicker.close",
                action: onClose
            )
        }
        .padding(.bottom, CameraProto.spaceCompact)
    }

    /// `.nb-pose-picker-search__field` — white, 2pt black border, radius 10, min-height 50pt,
    /// 20pt search glyph, 44pt clear button. Focus shifts the field -1.5pt with the large shadow
    /// (`:focus-within { transform: translate(-1.5px, -1.5px); box-shadow: var(--nb-shadow) }`).
    private var searchField: some View {
        let focusOffset: CGFloat = isSearchFocused ? -CameraProto.shadowSmall : 0
        let shadowDepth: CGFloat = isSearchFocused ? CameraProto.shadow : CameraProto.shadowSmall

        return HStack(spacing: CameraProto.spaceSM) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            TextField("Search poses", text: $model.query)
                .font(.system(size: 16))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
                .accessibilityIdentifier("posePicker.search")

            if !model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    model.clearSearch()
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AIPoseColor.foreground)
                        .frame(width: 17, height: 17)
                        .frame(width: CameraProto.touch, height: CameraProto.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("posePicker.searchClear")
            }
        }
        .padding(EdgeInsets(
            top: CameraProto.spaceXS,
            leading: CameraProto.spaceCompact,
            bottom: CameraProto.spaceXS,
            trailing: CameraProto.spaceXS
        ))
        .frame(minHeight: 50)
        .background(AIPoseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: CameraProto.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: CameraProto.radiusMedium)
            .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth))
        .background(RoundedRectangle(cornerRadius: CameraProto.radiusMedium)
            .fill(AIPoseColor.border)
            .offset(x: shadowDepth, y: shadowDepth))
        .offset(x: focusOffset, y: focusOffset)
        .padding(.bottom, CameraProto.spaceCompact)
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // R5: the notice sits above a populated grid instead of replacing it.
                if model.showsOfflineNotice { offlineNotice }
                stateSurface
                poseGrid
            }
            // `.nb-pose-picker-scroll { padding: 2px 2px calc(40px + safe-area) }`.
            .padding(.top, 2)
            .padding(.horizontal, 2)
            .padding(.bottom, 40)
        }
    }

    /// `.nb-camera-status`-style offline notice (frozen card, `.offline` tone).
    private var offlineNotice: some View {
        FeatureStateView(tone: .offline, title: "You're offline", message: "Showing your last available poses.")
    }

    /// States render through the shared (frozen, icon-less) `FeatureStateView`; the card is
    /// leading-aligned and top-anchored inside the sheet's scroll area — never centred.
    @ViewBuilder
    private var stateSurface: some View {
        // Branch on the pure tone so the card that renders is the mapped one, not a restated literal.
        switch model.stateTone {
        case .some(.loading):
            FeatureStateView(tone: .loading, title: "Loading poses", message: "Getting your pose library ready.")
        case .some(.error):
            FeatureStateView(tone: .error, title: "Couldn't load poses", message: "Check your connection and try again.", actionTitle: "Try again") {
                Task { await model.load() }
            }
        case .some(.offline):
            offlineNotice
        case .some(.empty):
            if model.emptyIsNoMatch {
                let term = model.query.trimmingCharacters(in: .whitespaces)
                FeatureStateView(tone: .empty, title: "No poses match “\(term)”", message: "Try a different pose name.")
            } else {
                FeatureStateView(tone: .empty, title: "No poses yet", message: "Create or save a pose to use it here.")
            }
        case .some(.success), .some(.warning), .none:
            // `.success`/`.warning` have no producer on this surface; `nil` means the grid is shown.
            EmptyView()
        }
    }

    /// `.nb-pose-picker-grid` — two-column staggered cards reusing the Poses visual language
    /// (`PoseCard` + `PoseGridMetrics`, `.nb-grid--masonry`).
    @ViewBuilder
    private var poseGrid: some View {
        let poses = model.filteredPoses
        if !poses.isEmpty {
            let columns = itemsByColumn
            HStack(alignment: .top, spacing: PoseGridMetrics.columnSpacing) {
                ForEach(0..<2, id: \.self) { columnIndex in
                    LazyVStack(alignment: .leading, spacing: PoseGridMetrics.rowSpacing) {
                        ForEach(columns[columnIndex]) { item in
                            Button {
                                onSelect(item.pose)
                            } label: {
                                PoseCard(
                                    pose: item.pose,
                                    aspectRatio: aspectRatioCache.ratio(for: item.pose.id)
                                )
                            }
                            .buttonStyle(GuideCardPressStyle())
                            .accessibilityLabel("Use \(item.pose.name) pose")
                            .accessibilitySortPriority(Double(poses.count - item.index))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear(perform: rebuildAssignments)
            .onChange(of: poses.map(\.id)) { _ in rebuildAssignments() }
            .onReceive(
                aspectRatioCache.$ratios
                    .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
                    .removeDuplicates()
            ) { _ in
                rebuildAssignments()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("posePicker.grid")
        }
    }

    private var itemsByColumn: [[PickerItem]] {
        var columns = Array(repeating: [PickerItem](), count: 2)
        for (index, pose) in model.filteredPoses.enumerated() {
            let column = columnByPoseID[pose.id] ?? (index % 2)
            columns[column].append(PickerItem(index: index, pose: pose))
        }
        return columns
    }

    private func rebuildAssignments() {
        let poses = model.filteredPoses
        let columns = PoseGridMetrics.columnAssignments(
            for: poses.map { aspectRatioCache.ratio(for: $0.id) },
            columnWidth: PoseGridMetrics.columnWidth
        )
        let updated = Dictionary(uniqueKeysWithValues: zip(poses.map(\.id), columns))
        guard updated != columnByPoseID else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            columnByPoseID = updated
        }
    }
}

/// `.nb-pose-picker-panel` — rounded top corners, square bottom (radius `22px 22px 0 0`).
private struct RoundedTopShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}

/// The panel border has **no bottom border** (`border-bottom: 0`): the path runs down the sides
/// and over the top edge only.
private struct TopEdgeBorderShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// `.nb-pose-grid .nb-card--pose-grid:active` — the flat surface just translates 1.5pt
/// (no shadow to drop).
private struct GuideCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? CameraProto.shadowSmall : 0,
                    y: configuration.isPressed ? CameraProto.shadowSmall : 0)
    }
}

// MARK: - Stick figures (prototype inline SVGs, 24x24 viewBox, 2pt round stroke)

enum StickFigurePose: String, CaseIterable {
    case standing, jumping, armsUp, dancing

    var lines: [(CGPoint, CGPoint)] {
        switch self {
        case .standing:
            return [
                (CGPoint(x: 12, y: 10), CGPoint(x: 12, y: 17)),
                (CGPoint(x: 12, y: 12), CGPoint(x: 7, y: 15)),
                (CGPoint(x: 12, y: 12), CGPoint(x: 17, y: 15)),
                (CGPoint(x: 12, y: 17), CGPoint(x: 8, y: 22)),
                (CGPoint(x: 12, y: 17), CGPoint(x: 16, y: 22)),
            ]
        case .jumping:
            return [
                (CGPoint(x: 12, y: 8), CGPoint(x: 12, y: 14)),
                (CGPoint(x: 12, y: 10), CGPoint(x: 6, y: 7)),
                (CGPoint(x: 12, y: 10), CGPoint(x: 18, y: 7)),
                (CGPoint(x: 12, y: 14), CGPoint(x: 8, y: 19)),
                (CGPoint(x: 12, y: 14), CGPoint(x: 16, y: 19)),
            ]
        case .armsUp:
            return [
                (CGPoint(x: 12, y: 11), CGPoint(x: 12, y: 18)),
                (CGPoint(x: 12, y: 13), CGPoint(x: 7, y: 8)),
                (CGPoint(x: 12, y: 13), CGPoint(x: 17, y: 8)),
                (CGPoint(x: 12, y: 18), CGPoint(x: 8, y: 23)),
                (CGPoint(x: 12, y: 18), CGPoint(x: 16, y: 23)),
            ]
        case .dancing:
            return [
                (CGPoint(x: 12, y: 9), CGPoint(x: 11, y: 15)),
                (CGPoint(x: 11, y: 11), CGPoint(x: 6, y: 8)),
                (CGPoint(x: 11, y: 11), CGPoint(x: 17, y: 13)),
                (CGPoint(x: 11, y: 15), CGPoint(x: 7, y: 21)),
                (CGPoint(x: 11, y: 15), CGPoint(x: 16, y: 17)),
                (CGPoint(x: 16, y: 17), CGPoint(x: 19, y: 21)),
            ]
        }
    }

    var head: (center: CGPoint, radius: CGFloat) {
        switch self {
        case .standing: return (CGPoint(x: 12, y: 7), 3)
        case .jumping: return (CGPoint(x: 12, y: 5), 3)
        case .armsUp: return (CGPoint(x: 12, y: 8), 3)
        case .dancing: return (CGPoint(x: 12, y: 6), 3)
        }
    }

    /// Matches the pose name when it names a known figure, otherwise rotates through the
    /// catalogue so neighbouring cards never look identical.
    static func resolve(name: String, category: String, index: Int) -> StickFigurePose {
        let haystack = "\(name) \(category)".lowercased()
        if haystack.contains("jump") { return .jumping }
        if haystack.contains("arms up") || haystack.contains("arm up") || haystack.contains("hands up") {
            return .armsUp
        }
        if haystack.contains("danc") { return .dancing }
        if haystack.contains("stand") || haystack.contains("sitting") || haystack.contains("sit") {
            return .standing
        }
        let all = StickFigurePose.allCases
        return all[((index % all.count) + all.count) % all.count]
    }
}

struct StickFigureShape: Shape {
    let kind: StickFigurePose

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let originX = rect.midX - 12 * scale
        let originY = rect.midY - 12 * scale
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: originX + p.x * scale, y: originY + p.y * scale)
        }

        var path = Path()
        let head = kind.head
        let radius = head.radius * scale
        let center = point(head.center)
        path.addEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        for (start, end) in kind.lines {
            path.move(to: point(start))
            path.addLine(to: point(end))
        }
        return path
    }
}

private struct StickFigureView: View {
    let kind: StickFigurePose
    var lineColor: Color = AIPoseColor.border

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.78
            ZStack {
                StickFigureShape(kind: kind)
                    .stroke(
                        lineColor,
                        style: StrokeStyle(lineWidth: 2 * side / 24, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: side, height: side)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}
