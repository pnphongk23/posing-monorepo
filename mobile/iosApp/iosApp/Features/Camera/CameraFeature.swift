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
    /// Visible countdown (`nil` when idle): the number and its Cancel above the shutter.
    @Published private(set) var timerCountdown: Int?
    /// Shutter timer setting (`Off` / `3 s` / `10 s`), persisted like the other settings.
    @Published var timerSetting: CameraTimerSetting = .off
    /// Saved capture aspect, persisted like the other settings.
    @Published var aspectRatio: CameraAspectRatio = .threeFour
    /// `pose-visibility-row`: Shown / Hidden for the selected pose reference.
    @Published var isPoseGuideVisible = true
    /// `pose-line-color-black` / `pose-line-color-white`.
    @Published var guideLineColor: GuideLineColor = .black
    /// Pinch / rotate / drag placement of the pose reference, committed when a gesture ends.
    @Published var guideTransform = GuideTransform()
    /// Transient capture feedback; cleared by `statusClearTask`.
    @Published var statusMessage: String?
    /// Tone of that feedback. Status is never carried by colour alone: the snackbar pairs the tone's
    /// glyph and word with the message (`APStateTone`).
    @Published private(set) var statusTone: APStateTone = .success
    @Published var zoomLevel: CameraZoomLevel = .one
    /// The exact zoom the lens is at (presets write through here: `0.5` is not a `CameraZoomLevel`).
    @Published private(set) var zoomFactor: CGFloat = 1
    /// URL of the newest capture, drawn as a 48pt thumbnail in the shutter rail.
    @Published private(set) var latestThumbnailURL: URL?

    var cameraControlsEnabled: Bool {
        coordinator.state.permission == .authorized
            && !coordinator.state.isCaptureInFlight
    }

    /// Whether the shutter accepts a press.
    ///
    /// The gate may want the paywall on a press the camera could not have served at all (no
    /// permission, no hardware, a simulator), so readiness can no longer be the only input — the
    /// press has to reach the gate. For every outcome that would capture, readiness still decides,
    /// exactly as it did before the paid gate existed.
    var isShutterEnabled: Bool {
        PremiumGate.shutterAcceptsPress(
            outcome: premiumGate.captureOutcome(cameraReady: coordinator.state.captureEnabled),
            isBusy: coordinator.state.isCaptureInFlight
        )
    }

    let camera: any CameraSessionControlling
    let coordinator: CameraCoordinator
    let imageStorage: CaptureImageStorage
    /// The paid-action gate (`FEAT-011` M1). A port, so the capture path is testable without a
    /// store, a session or a network.
    private let premiumGate: any PremiumGateProviding
    /// Presentation seam for the paywall, owned by the app root (one presenter, no event bus).
    private let onPremiumRequired: (Bool) -> Void
    private var timeoutTask: Task<Void, Never>?
    private var statusClearTask: Task<Void, Never>?
    private var timerMachine = CameraTimerMachine()
    private var countdownTask: Task<Void, Never>?

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
        saveDebounceNanoseconds: UInt64 = 300_000_000,
        premiumGate: any PremiumGateProviding = PremiumGateModel(),
        onPremiumRequired: @escaping (Bool) -> Void = { _ in }
    ) {
        self.premiumGate = premiumGate
        self.onPremiumRequired = onPremiumRequired
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
        observePremiumGate()
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
        countdownTask?.cancel()
        countdownTask = nil
        timerCountdown = nil
        timerMachine.cancel()
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

    /// The shutter.
    ///
    /// The paid-action gate is the **first** thing here, ahead of camera readiness and therefore
    /// ahead of every `captureError` the coordinator can produce. An unentitled press opens the
    /// paywall even when the camera could not have taken the photo — which is what makes the flow
    /// verifiable on a simulator, where `isPhotoCaptureReady` is always false. Only a press the gate
    /// allows reaches the capture path, and that path is untouched: readiness still decides between
    /// capturing and doing nothing.
    func capture() {
        // The paid-action gate is still the first thing a press meets, before the timer: an unentitled
        // press opens the paywall and no countdown starts.
        switch premiumGate.captureOutcome(cameraReady: coordinator.state.captureEnabled) {
        case .paywall(let signIn):
            onPremiumRequired(signIn)
            return
        case .unchanged:
            return
        case .capture:
            break
        }
        switch timerMachine.shutterPressed(isReady: coordinator.state.captureEnabled) {
        case .captureNow:
            performCapture()
        case .countdownStarted(let remaining):
            timerCountdown = remaining
            startCountdownTicks()
        case .countdownAdvanced, .cancelled, .ignored:
            break
        }
    }

    /// The (possibly delayed) capture. Only the timer machine reaches this, so an immediate and a
    /// counted-down capture cannot diverge.
    private func performCapture() {
        guard coordinator.onCaptureRequested() else {
            timerMachine.captureFinished()
            timerCountdown = nil
            return
        }
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            self?.coordinator.onCaptureTimeoutTick()
        }
        observeCaptureCompletion()
    }

    /// The countdown's Cancel control: back to ready, no photo, no queued capture.
    func cancelTimer() {
        guard timerMachine.cancel() else { return }
        countdownTask?.cancel()
        countdownTask = nil
        timerCountdown = nil
    }

    /// The adjust-guide Scale control: writes the same placement value the pinch gesture writes.
    func setGuideScale(_ scale: CGFloat) {
        guard cameraControlsEnabled else { return }
        var transform = guideTransform
        transform.scale = CameraGuideScale.stepped(scale)
        guideTransform = transform
    }

    /// The zoom range this camera can serve, which is what the slider spans and what its ticks come from.
    var zoomRange: ClosedRange<CGFloat> { CameraZoomScale.range(lower: lensZoomRange.lowerBound, upper: lensZoomRange.upperBound) }

    /// The slider's own value: clamped to the lens before it reaches the hardware, so a drag past the end
    /// stops at the end instead of being quietly clipped later.
    func setZoomFactor(_ factor: CGFloat) {
        guard cameraControlsEnabled else { return }
        applyZoom(factor: factor)
    }

    func applyZoom(factor: CGFloat) {
        zoomFactor = CameraZoomScale.deviceFactor(forDisplay: factor, in: zoomRange)
        zoomLevel = CameraZoomLevel.nearest(to: zoomFactor)
        reconcileHardware()
    }

    /// The active lens's own zoom range, best effort: the simulator has no capture device, so the shipped
    /// presets (1x/2x) are the fallback.
    private var lensZoomRange: ClosedRange<CGFloat> {
        let position: AVCaptureDevice.Position = camera.facing == .front ? .front : .back
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video)
        guard let device else { return 1...2 }
        return device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor
    }

    func setAspectRatio(_ ratio: CameraAspectRatio) {
        guard cameraControlsEnabled else { return }
        aspectRatio = ratio
    }

    /// Setting the timer while a countdown runs cancels it: the new value applies to the next press.
    func setTimerSetting(_ setting: CameraTimerSetting) {
        guard cameraControlsEnabled else { return }
        if timerMachine.isCountingDown { cancelTimer() }
        timerSetting = setting
        timerMachine.setting = setting
    }

    private func startCountdownTicks() {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                switch self.timerMachine.tick() {
                case .countdownAdvanced(let remaining):
                    self.timerCountdown = remaining
                case .captureNow:
                    self.timerCountdown = nil
                    self.performCapture()
                    return
                case .cancelled, .countdownStarted, .ignored:
                    self.timerCountdown = nil
                    return
                }
            }
        }
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

    // MARK: - Pose picker

    /// The one way into the picker: the Poses control on the scale row always opens the sheet (search +
    /// All/Saved scopes). There is no inline strip any more — it duplicated the sheet's rows in a bar
    /// that ate the viewport, and it was a second, weaker way to reach the same collection.
    func openPosePicker() {
        guard cameraControlsEnabled else { return }
        showPosePicker = true
    }

    func closePosePicker() {
        showPosePicker = false
    }

    /// The Flash row's three chips apply the chosen mode directly; nothing cycles behind the user's back.
    func setFlash(_ setting: CameraFlashSetting) {
        guard cameraControlsEnabled else { return }
        flashSetting = setting
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

    /// Mirror: flips the pose reference horizontally. The reference is what the user lines up against,
    /// so this mirrors the guide (the `guideFlipped` setting persisted since FEAT-012), never the photo.
    func toggleGuideMirror() {
        guard cameraControlsEnabled else { return }
        guideFlipped.toggle()
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

    // MARK: - Settings persistence (FEAT-012)

    /// The eight settings that survive a relaunch. `CameraSnapshot` carries them in one JSON blob;
    /// the selected pose is deliberately not among them (D8).
    private enum PersistedSetting: Hashable {
        case opacity, flipped, grid, flash, guideVisibility, lineColor, transform, zoom, timer, aspectRatio
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
        // The slider is continuous: a factor between two levels is still a setting the user chose.
        $zoomFactor.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.zoom) }.store(in: &cancellables)
        $timerSetting.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.timer) }.store(in: &cancellables)
        $aspectRatio.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.aspectRatio) }.store(in: &cancellables)
    }

    /// Gate moves are not camera settings, but the shutter's enabled state reads them: without this
    /// the control would stay disabled after a purchase or a restored session, and the paywall could
    /// not be reopened after a dismissal.
    private func observePremiumGate() {
        premiumGate.gateUpdates
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
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
            zoom: zoomLevel,
            zoomFactor: Double(zoomFactor),
            timer: timerSetting,
            aspectRatio: aspectRatio
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
        if !touchedSettings.contains(.zoom) {
            zoomLevel = stored.zoom
            zoomFactor = stored.zoomFactor
        }
        if !touchedSettings.contains(.aspectRatio) { aspectRatio = stored.aspectRatio }
        if !touchedSettings.contains(.timer) {
            timerSetting = stored.timer
            timerMachine.setting = stored.timer
        }
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
        if lastAppliedZoom != zoomFactor {
            lastAppliedZoom = zoomFactor
            camera.setZoomFactor(zoomFactor)
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
            timerMachine.captureFinished()
            timerCountdown = nil
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
            // The saved file follows the reserved framing; a failed rewrite keeps the capture (the
            // photo still exists, only its aspect would differ from the preview).
            CameraImagePostProcess.cropFileInPlace(at: path, ratio: aspectRatio)
            let savedToPhotos = await PhotosExporter.saveImage(at: URL(fileURLWithPath: path))
            showStatus(savedToPhotos ? "Saved" : "Saved to gallery. Allow Photos access to also save to your library.")
        }
    }

    private func showStatus(_ message: String?) {
        showStatus(message, tone: statusToneForCurrentPhase())
    }

    /// Status is never colour alone: the snackbar draws the tone's glyph **and** word beside the
    /// message, so a failed capture reads as a failure without relying on the tint.
    private func statusToneForCurrentPhase() -> APStateTone {
        switch coordinator.state.phase {
        case .captureError:
            return .error
        case .captureSucceeded:
            return .success
        default:
            return coordinator.state.lastFailure == nil ? .success : .error
        }
    }

    private func showStatus(_ message: String?, tone: APStateTone) {
        statusClearTask?.cancel()
        statusMessage = message
        statusTone = tone
        guard message != nil else { return }
        statusClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    /// The snackbar was tapped away (F5: a snackbar never parks on screen).
    func dismissStatusMessage() {
        statusClearTask?.cancel()
        statusMessage = nil
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

/// The pose reference's size, as the adjust-guide sheet exposes it: the value the pinch gesture
/// writes, clamped to the documented range, stepped for a slider and reset by one control.
enum CameraGuideScale {
    static let range: ClosedRange<CGFloat> = GuideTransform.scaleRange
    static let step: CGFloat = 0.05

    static func clamped(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(max(scale, range.lowerBound), range.upperBound)
    }

    static func stepped(_ scale: CGFloat) -> CGFloat {
        let steps = ((clamped(scale) - range.lowerBound) / step).rounded()
        return clamped(range.lowerBound + steps * step)
    }

    /// The value beside the slider: scale as a percentage (1.0 → "100%").
    static func label(_ scale: CGFloat) -> String {
        "\(Int((clamped(scale) * 100).rounded()))%"
    }
}

/// Capture aspect (`05-camera-tools-sheet` Ratio row: 3:4 / 1:1 / 9:16). 3:4 is the camera's portrait
/// default, so it is also the "no crop" answer for a 3:4 capture.
enum CameraAspectRatio: String, CaseIterable, Identifiable, Sendable {
    case threeFour = "3:4"
    case oneOne = "1:1"
    case nineSixteen = "9:16"

    var id: String { rawValue }
    var widthOverHeight: CGFloat {
        switch self {
        case .threeFour: return 3.0 / 4.0
        case .oneOne: return 1
        case .nineSixteen: return 9.0 / 16.0
        }
    }
    var accessibilityIdentifier: String {
        switch self {
        case .threeFour: return "camera.tools.ratio.3x4"
        case .oneOne: return "camera.tools.ratio.1x1"
        case .nineSixteen: return "camera.tools.ratio.9x16"
        }
    }
}

/// The crop that makes a capture match a ratio: centred, largest area of that ratio. Pure, so the
/// saved dimensions are a unit test instead of something only a device can show.
enum CameraAspectCrop {
    static let matchTolerance: CGFloat = 0.005

    static func rect(for ratio: CameraAspectRatio, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let target = ratio.widthOverHeight
        let current = imageSize.width / imageSize.height
        if abs(current - target) <= matchTolerance {
            return CGRect(origin: .zero, size: imageSize)
        }
        if current > target {
            let width = imageSize.height * target
            return CGRect(x: (imageSize.width - width) / 2, y: 0, width: width, height: imageSize.height)
        }
        let height = imageSize.width / target
        return CGRect(x: 0, y: (imageSize.height - height) / 2, width: imageSize.width, height: height)
    }

    static func needsCrop(ratio: CameraAspectRatio, imageSize: CGSize) -> Bool {
        rect(for: ratio, imageSize: imageSize) != CGRect(origin: .zero, size: imageSize)
    }
}

/// Where the pose reference sits inside the photo frame: the prototype's four inset fractions of the frame.
enum CameraViewportFrame {
    /// The pose reference's placement inside the photo frame. The four insets are the prototype's
    /// `.nb-camera-pose-reference` fractions, taken of the **frame**, never of the screen: a 9:16 frame runs
    /// under the bottom controls, and a guide measured against the screen would spill out of the photo it is
    /// supposed to line up with.
    static func guideRect(in frame: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        let horizontalInset = CameraProto.poseReferenceHorizontalInset
        let topInset = CameraProto.poseReferenceTopInset
        let bottomInset = CameraProto.poseReferenceBottomInset
        return CGRect(
            x: frame.minX + frame.width * horizontalInset,
            y: frame.minY + frame.height * topInset,
            width: frame.width * (1 - horizontalInset * 2),
            height: frame.height * (1 - topInset - bottomInset)
        )
    }
}

/// Saved-photo post-processing for the ratio: the file behind the gallery row is cropped to the aspect
/// the user framed with, so the saved dimensions match the preview (and are asserted in tests).
enum CameraImagePostProcess {
    /// The size the photo **displays** at, in pixels.
    ///
    /// The camera writes a landscape pixel buffer and records the rotation as an EXIF tag, so a portrait
    /// capture is 4032×3024 pixels tagged `.right` that displays as 3024×4032. Every ratio in this file
    /// describes what the user *sees*, so `cgImage.width/height` is the wrong space to measure: 3:4 read
    /// off a 4:3 buffer crops a vertical strip and saves a 4:3 *landscape* photo — the inverse aspect of
    /// the frame the viewport showed.
    static func displayedPixelSize(of image: UIImage) -> CGSize {
        guard let cgImage = image.cgImage else { return image.size }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        switch image.imageOrientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }

    /// The photo's pixels with the orientation applied (`orientation == .up`), so a crop rect expressed
    /// in display space is literally the rect to crop. `nil` when the image has no bitmap backing.
    static func uprightPixelBuffer(of image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        guard image.imageOrientation != .up else { return cgImage }
        let size = displayedPixelSize(of: image)
        guard size.width >= 1, size.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        // Point-for-pixel: the renderer's default scale would resample a 12 MP capture at 2–3×.
        format.scale = 1
        format.opaque = true
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            // `UIImage.draw` applies the EXIF orientation, so the buffer comes out as the picture.
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return upright.cgImage
    }

    @discardableResult
    static func cropFileInPlace(at path: String, ratio: CameraAspectRatio) -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let image = UIImage(data: data) else { return false }
        // Cheap early-out in display space: a 3:4 capture of a 3:4 picture is not re-encoded at all.
        guard CameraAspectCrop.needsCrop(ratio: ratio, imageSize: displayedPixelSize(of: image)) else {
            return false
        }
        guard let upright = uprightPixelBuffer(of: image) else { return false }
        let bufferSize = CGSize(width: upright.width, height: upright.height)
        let rect = CameraAspectCrop.rect(for: ratio, imageSize: bufferSize)
            .integral
            .intersection(CGRect(origin: .zero, size: bufferSize))
        guard !rect.isEmpty, let cropped = upright.cropping(to: rect) else { return false }
        // The buffer is upright, so the file carries no orientation tag: the crop *is* the picture.
        let output = UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
        guard let encoded = output.jpegData(compressionQuality: 0.92) else { return false }
        return (try? encoded.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }
}

/// Shutter timer (`05-camera-tools-sheet`: Off / 3 s / 10 s).
enum CameraTimerSetting: String, CaseIterable, Identifiable, Sendable {
    case off = "Off"
    case threeSeconds = "3 s"
    case tenSeconds = "10 s"

    var id: String { rawValue }
    var seconds: Int {
        switch self {
        case .off: return 0
        case .threeSeconds: return 3
        case .tenSeconds: return 10
        }
    }
    var accessibilityIdentifier: String {
        switch self {
        case .off: return "camera.tools.timer.off"
        case .threeSeconds: return "camera.tools.timer.3s"
        case .tenSeconds: return "camera.tools.timer.10s"
        }
    }
}

/// The shutter countdown as a state machine with no clock of its own: the view model feeds it presses
/// and one-second ticks, so start / advance / fire / cancel / a second press are all deterministic.
struct CameraTimerMachine: Equatable {
    enum Phase: Equatable {
        case ready
        case counting(remaining: Int)
        /// A capture is in flight: no press or tick may start another one.
        case capturing
    }

    enum Effect: Equatable {
        case captureNow
        case countdownStarted(remaining: Int)
        case countdownAdvanced(remaining: Int)
        case cancelled
        case ignored
    }

    private(set) var phase: Phase = .ready
    var setting: CameraTimerSetting = .off

    var isCountingDown: Bool {
        if case .counting = phase { return true }
        return false
    }

    var remainingSeconds: Int? {
        if case .counting(let remaining) = phase { return remaining }
        return nil
    }

    mutating func shutterPressed(isReady: Bool) -> Effect {
        guard phase == .ready else { return .ignored }
        guard setting.seconds > 0 else {
            guard isReady else { return .ignored }
            phase = .capturing
            return .captureNow
        }
        // A timed press starts the countdown even before the session is ready; readiness is decided
        // when the countdown fires, so a slow camera still gets the full warning.
        phase = .counting(remaining: setting.seconds)
        return .countdownStarted(remaining: setting.seconds)
    }

    mutating func tick() -> Effect {
        guard case .counting(let remaining) = phase else { return .ignored }
        guard remaining > 1 else {
            phase = .capturing
            return .captureNow
        }
        phase = .counting(remaining: remaining - 1)
        return .countdownAdvanced(remaining: remaining - 1)
    }

    mutating func cancel() -> Bool {
        guard isCountingDown else { return false }
        phase = .ready
        return true
    }

    mutating func captureFinished() {
        phase = .ready
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
    var color: Color { self == .black ? AP.Color.background : AP.Color.primaryText }
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
    @StateObject private var savedPosesModel: CameraSavedPosesModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Focus returns to the More control when the Camera Tools popup is dismissed
    /// (outside tap / Escape / VoiceOver escape).
    @FocusState private var isToolsButtonFocused: Bool
    /// Height of the top control bar, measured so the popover anchors *under* it at every Dynamic Type size
    /// instead of at a hard-coded offset.
    @State private var topBarHeight: CGFloat = AP.HitTarget.minimum
    /// The window's insets. The camera draws edge to edge, so this is what the chrome and the photo frame are
    /// positioned from — never a hard-coded phone.
    @State private var safeAreaInsets = CameraSafeArea.Insets()

    init(
        guide: Binding<NativePose?>,
        poseService: any PoseServing,
        onClose: @escaping () -> Void = {},
        onOpenGallery: @escaping () -> Void = {},
        premiumGate: any PremiumGateProviding = PremiumGateModel(),
        onPremiumRequired: @escaping (Bool) -> Void = { _ in },
        savedPoses: any CameraSavedPosesProviding = CatalogueSavedPosesService(),
        model: @autoclosure @escaping () -> CameraViewModel? = nil
    ) {
        _guide = guide
        self.poseService = poseService
        self.onClose = onClose
        self.onOpenGallery = onOpenGallery
        // An injected model already carries its own gate (tests/previews); otherwise the screen wires
        // the one the app root owns, so the camera and the paywall read the same premium state.
        _model = StateObject(wrappedValue: model() ?? CameraViewModel(
            premiumGate: premiumGate,
            onPremiumRequired: onPremiumRequired
        ))
        _posePickerModel = StateObject(wrappedValue: PosePickerViewModel(service: poseService))
        _savedPosesModel = StateObject(wrappedValue: CameraSavedPosesModel(provider: savedPoses))
    }

    /// Legacy UIKit host and previews without an injected pose service.
    init() {
        self.init(guide: .constant(nil), poseService: PreviewPoseService())
    }

    private var isAuthorized: Bool { model.coordinator.state.permission == .authorized }

    var body: some View {
        ZStack {
            // The camera stage: the preview fills the screen, and the ratio frames the part the shutter keeps.
            GeometryReader { proxy in
                CameraCanvas(
                    model: model,
                    guide: guide,
                    isAuthorized: isAuthorized,
                    stage: CameraStageFrame.make(
                        ratio: model.aspectRatio,
                        screen: proxy.size,
                        safeTop: safeAreaInsets.top
                    ),
                    onClose: onClose
                )
            }

            VStack(spacing: 0) {
                topControls
                    .padding(.horizontal, CameraProto.controlInset)
                    .padding(.top, safeAreaInsets.top)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: CameraTopBarHeightKey.self, value: geo.size.height)
                        }
                    )
                Spacer(minLength: 0)
                bottomChrome
            }

            // `.nb-pose-picker-sheet` — an in-place overlay on Camera, never a pushed route, so
            // selecting a pose returns directly with no picker entry left on the navigation stack.
            if model.showPosePicker {
                PosePickerSheet(
                    model: posePickerModel,
                    savedPoses: savedPosesModel,
                    onClose: { model.closePosePicker() },
                    onSelect: { pose in
                        CameraPickerSelection.select(pose, guide: $guide, camera: model)
                    }
                )
                .zIndex(2)
            }

            cameraToolsPopup
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.showPosePicker)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: model.showCameraTools)
        .background(AP.Color.background.ignoresSafeArea())
        // The camera is a dark surface, and every AP token inside it has to resolve that way even when
        // the screen is hosted outside a dark presentation (UIKit host, preview, snapshot): the canvas,
        // the chrome and the pose reference's white line colour are all read from the dark values.
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .neoHiddenNavigationBar()
        .preferredColorScheme(.dark)
        .task { await model.onAppear() }
        .onAppear {
            model.guideAppeared(hasGuide: guide != nil)
            safeAreaInsets = CameraSafeArea.read()
        }
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
                // Nothing draws the catalogue while the sheet is closed, so the dismissal drops the
                // result: reopening always retries instead of painting a stale (or failed) grid.
                posePickerModel.prepareForDismissal()
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                model.coordinator.onForeground()
                safeAreaInsets = CameraSafeArea.read()
            case .background:
                model.coordinator.onBackground()
                Task { await model.flushSettings() }
            default: break
            }
        }
        .onPreferenceChange(CameraTopBarHeightKey.self) { height in
            guard height > 0 else { return }
            topBarHeight = height
        }
        .onChange(of: model.cameraControlsEnabled) { enabled in
            if !enabled { model.closeCameraTools() }
        }
        .onChange(of: guide?.id) { _ in model.guideDidChange(hasGuide: guide != nil) }
    }

    // MARK: Stage

    /// The canvas for one container size. The screen's entry point, so a rendered test mounts exactly what the
    /// screen mounts.
    func cameraCanvas(size: CGSize, safeTop: CGFloat = 0) -> some View {
        CameraCanvas(
            model: model,
            guide: guide,
            isAuthorized: isAuthorized,
            stage: CameraStageFrame.make(ratio: model.aspectRatio, screen: size, safeTop: safeTop),
            onClose: onClose
        )
    }

    /// The bottom control surface — snackbar, zoom row, shutter rail. One view, so a rendered test can
    /// prove what is on screen. It floats over the preview: the photo is not shortened to make room for it.
    private var bottomChrome: some View {
        CameraBottomBar(
            thumbnailURL: model.latestThumbnailURL,
            isBusy: model.coordinator.state.isCaptureInFlight,
            canCapture: model.isShutterEnabled,
            controlsEnabled: model.cameraControlsEnabled,
            status: model.statusMessage,
            statusTone: model.statusTone,
            timerCountdown: model.timerCountdown,
            selectedPoseID: guide?.id,
            selectedPoseName: guide?.name,
            showsPicker: isAuthorized,
            zoomFactor: model.zoomFactor,
            zoomRange: model.zoomRange,
            onOpenPosePicker: { model.openPosePicker() },
            onZoomChange: { factor in model.setZoomFactor(factor) },
            onOpenGallery: onOpenGallery,
            onCapture: { model.capture() },
            onSwitchCamera: { model.switchCamera() },
            onDismissStatus: { model.dismissStatusMessage() },
            onCancelTimer: { model.cancelTimer() },
            safeBottom: safeAreaInsets.bottom
        )
    }

    private func dismissCameraTools() {
        guard model.showCameraTools else { return }
        model.closeCameraTools()
        // Focus returns to the More control (`guide-picker.js` `setOpen(false)` → `openButton.focus()`).
        isToolsButtonFocused = true
    }

    /// The tools popover, anchored under the tools control: its caret points up at the button and its right edge
    /// sits on the button's. There is no scrim — only an outside-tap catcher.
    @ViewBuilder private var cameraToolsPopup: some View {
        if model.showCameraTools {
            ZStack(alignment: .topTrailing) {
                // Outside tap dismisses without a visible scrim.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissCameraTools() }
                    .accessibilityHidden(true)

                CameraToolsPopup(
                    flashSetting: model.flashSetting,
                    isGridVisible: model.isGridVisible,
                    controlsEnabled: model.cameraControlsEnabled,
                    timerSetting: model.timerSetting,
                    aspectRatio: model.aspectRatio,
                    onFlashChange: { model.setFlash($0) },
                    onGridToggle: { model.toggleGrid() },
                    onTimerChange: { model.setTimerSetting($0) },
                    onAspectRatioChange: { model.setAspectRatio($0) },
                    onDismiss: { dismissCameraTools() }
                )
                .padding(.top, CameraToolsLayout.cardTop(belowTopBar: topBarHeight))
                .padding(.trailing, CameraProto.controlInset)
                .transition(.opacity
                    .combined(with: .offset(y: -AP.Space.space8))
                    .combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
            }
        }
    }

    /// The camera's top chrome: Close on the left, the guide's eye when a reference is up, tools on the
    /// right. The old "Choose a pose" dropdown pill is gone (owner device feedback): picking a pose is
    /// the Poses control in the scale row, which opens the strip and its Browse entry.
    private var topControls: some View {
        HStack(alignment: .center, spacing: AP.Space.space8) {
            CameraSurfaceControl(
                systemImage: "xmark",
                accessibilityLabel: "Close camera",
                identifier: "camera.close",
                action: onClose
            )

            Spacer(minLength: 0)

            if guide != nil {
                CameraSurfaceControl(
                    systemImage: model.isPoseGuideVisible ? "eye" : "eye.slash",
                    isSelected: !model.isPoseGuideVisible,
                    accessibilityLabel: model.isPoseGuideVisible ? "Hide pose guide" : "Show pose guide",
                    identifier: "camera.guideToggle",
                    action: { model.togglePoseGuideVisibility() }
                )
                .accessibilityValue(model.isPoseGuideVisible ? "Shown" : "Hidden")
            }

            CameraSurfaceControl(
                systemImage: "slider.horizontal.3",
                accessibilityLabel: "Camera settings",
                identifier: "camera.tools",
                action: { model.toggleCameraTools() }
            )
            .focused($isToolsButtonFocused)
        }
    }

}

// MARK: - Camera metrics
//
// Only the layout numbers that have no token (absolute prototype geometry: the immersive top inset,
// the pose-reference insets, the popup and sheet caps) live here. Colours, radii, spacing, type and
// elevation come from `AP`.

enum CameraProto {
    static let controlInset: CGFloat = 16

    // `.nb-camera-pose-reference`
    static let poseReferenceTopInset: CGFloat = 0.16
    static let poseReferenceBottomInset: CGFloat = 0.14
    static let poseReferenceHorizontalInset: CGFloat = 0.18

    // `.nb-camera-tools-menu`
    static let popupWidth: CGFloat = 264

    // `.nb-pose-picker-panel`
    static let pickerMaxHeight: CGFloat = 700
    static let pickerMinHeight: CGFloat = 420
    static let pickerHeightFraction: CGFloat = 0.82

    // `.nb-shutter-bar--redesign`
    static let railInset: CGFloat = 24
    static let railControl: CGFloat = 48
    static let shutterSize: CGFloat = 72
}

// MARK: - Camera chrome (AP tokens, forced dark)

/// Pressed = one fill step plus `scale 0.97`; Reduce Motion keeps the fill and drops the scale.
/// One style for every camera pill, so a press reads the same on the top bar, the strip and the rail.
private struct CameraPressStyle: ButtonStyle {
    var isSelected: Bool = false
    var shape: CameraPillShape = .rounded16
    /// `nil` keeps the surface fill; a chip that sits on the bar's panel passes `controlFill`.
    var restingFill: SwiftUI.Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        CameraPressBody(
            configuration: configuration,
            isSelected: isSelected,
            shape: shape,
            restingFill: restingFill
        )
    }
}

private enum CameraPillShape { case rounded16, capsule }

private struct CameraPressBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let shape: CameraPillShape
    var restingFill: SwiftUI.Color? = nil

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .background(background)
            .scaleEffect(configuration.isPressed && !reduceMotion ? AP.Press.scale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: AP.Press.duration), value: configuration.isPressed)
            .apMinimumHitTarget()
    }

    private var fill: SwiftUI.Color {
        guard isEnabled else { return AP.Color.controlFill }
        guard configuration.isPressed else {
            if let restingFill { return restingFill }
            return isSelected ? AP.Color.selectedBackground : AP.Color.surface
        }
        return isSelected ? AP.Color.selectedBackground : AP.Color.controlFillPressed
    }

    @ViewBuilder private var background: some View {
        switch shape {
        case .rounded16:
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous).fill(fill)
        case .capsule:
            Capsule().fill(fill)
        }
    }
}

/// One 44 pt surface pill with no resting border — Close, the guide's eye and the tools.
private struct CameraSurfaceControl: View {
    let systemImage: String
    var isSelected = false
    let accessibilityLabel: String
    var identifier: String? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AP.Font.heading)
                .foregroundStyle(labelColor)
                .frame(width: AP.HitTarget.minimum, height: AP.HitTarget.minimum)
        }
        .buttonStyle(CameraPressStyle(isSelected: isSelected))
        .accessibilityLabel(accessibilityLabel)
        .apIdentifier(identifier)
    }

    private var labelColor: SwiftUI.Color {
        guard isEnabled else { return AP.Color.disabled }
        return isSelected ? AP.Color.selectedForeground : AP.Color.primaryText
    }
}

/// Measured height of the top control bar: the tools popup anchors under it at every type size.
private struct CameraTopBarHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Shared 72 pt state panels (F4)

/// Which shared state panel a camera surface draws.
///
/// F4: empty, error, permission and loading all render as ONE component — a 72 pt circle in the
/// subtle accent tint with the glyph centred, then title, copy and one action. The mapping is pure so
/// the selection per permission / picker state is a unit test, not something only a screenshot shows.
enum CameraStatePanel: Equatable {
    case permissionRequest
    case permissionDenied
    case pickerLoading
    case pickerFailed
    case pickerEmptyCatalogue
    case pickerNoMatch(String)
    case pickerOffline

    /// The camera's own gate: authorized draws no panel at all.
    static func permission(_ state: CameraPermissionState) -> CameraStatePanel? {
        switch state {
        case .authorized: return nil
        case .notDetermined: return .permissionRequest
        case .denied, .restricted: return .permissionDenied
        }
    }

    /// The pose picker card for a tone. `.success` / `.warning` have no producer here and `nil` means
    /// the grid draws, so both answer no panel.
    static func picker(
        tone: FeatureStateTone?,
        isNoMatch: Bool,
        term: String,
        isOffline: Bool
    ) -> CameraStatePanel? {
        switch tone {
        case .none, .some(.success), .some(.warning):
            return nil
        case .some(.loading):
            return .pickerLoading
        case .some(.error):
            return isOffline ? .pickerOffline : .pickerFailed
        case .some(.offline):
            return .pickerOffline
        case .some(.empty):
            return isNoMatch ? .pickerNoMatch(term) : .pickerEmptyCatalogue
        }
    }

    /// The no-match card's copy, taken from the Search screen's own strings (`SearchResultsCopy`) instead
    /// of a second phrasing: the sheet and the Search screen answer the same query with the same words.
    /// The picker's All scope is the whole library, which is the `.all` source there.
    static func noMatchCopy(term: String) -> (title: String, message: String) {
        (
            SearchResultsCopy.emptyTitle(query: term, filter: .all),
            SearchResultsCopy.emptyMessage(query: term, filter: .all)
        )
    }

    /// The permission copy, in one place so the panel and its tests cannot drift.
    var permissionCopy: (title: String, message: String, actionTitle: String) {
        ("Camera access is off",
         "AI Pose needs the camera to show the pose guide. Turn it on in Settings.",
         self == .permissionDenied ? "Open Settings" : "Allow Camera")
    }
}

/// The camera's permission gate: the shared 72 pt panel over the scrim.
struct CameraPermissionPanel: View {
    let permission: CameraPermissionState
    let onAllow: () -> Void
    let onOpenSettings: () -> Void
    /// "Not now": leaves the camera (the board's second action).
    var onDismiss: () -> Void = {}

    /// The board's copy and the handle QA targets (`05-camera-permission-denied`).
    static let notNowTitle = "Not now"
    static let notNowIdentifier = "camera.permission.notNow"

    var body: some View {
        let panel = CameraStatePanel.permission(permission) ?? .permissionDenied
        let copy = panel.permissionCopy
        VStack(spacing: AP.Space.space8) {
            APEmptyStateView(
                title: copy.title,
                message: copy.message,
                actionTitle: copy.actionTitle,
                action: panel == .permissionDenied ? onOpenSettings : onAllow,
                style: .plain,
                glyph: "camera"
            )
            // The board's second action: leave the camera without granting access. Nothing on this
            // screen is usable without the preview, so "Not now" closes it rather than parking the
            // user on a dead viewfinder.
            Button(Self.notNowTitle, action: onDismiss)
                .buttonStyle(.plain)
                .font(AP.Font.supporting.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
                .apMinimumHitTarget()
                .accessibilityIdentifier(Self.notNowIdentifier)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.permission")
    }
}

/// One picker state on the shared panel — used by the sheet, so a failed / empty / loading catalogue
/// can never fall back to a screen-local card.
struct CameraPickerStatePanel: View {
    let panel: CameraStatePanel
    var onRetry: (() -> Void)?

    var body: some View {
        switch panel {
        case .pickerLoading, .permissionRequest, .permissionDenied:
            APLoadingStateView(label: "Loading poses")
        case .pickerFailed:
            APErrorStateView(
                title: "Couldn't load poses",
                message: "The pose library didn't respond. Check your connection and try again.",
                retry: onRetry,
                style: .plain
            )
        case .pickerEmptyCatalogue:
            APEmptyStateView(
                title: "No poses yet",
                message: "Create or save a pose to use it here.",
                style: .plain,
                glyph: "tray"
            )
        case .pickerNoMatch(let term):
            let copy = CameraStatePanel.noMatchCopy(term: term)
            APEmptyStateView(
                title: copy.title,
                message: copy.message,
                style: .plain,
                glyph: "magnifyingglass"
            )
        case .pickerOffline:
            APOfflineBanner(message: "You're offline", retryTitle: "Retry", retry: onRetry)
        }
    }
}

// MARK: - Bottom control surface

/// The bottom surface's contract, pure so it is a unit test instead of something only a screenshot can
/// show: there is no inline pose strip any more, and the Poses control on the scale row is the one way
/// into the picker sheet.
enum CameraChromeLayout {
    /// The Poses control is drawn whenever the camera can place a pose — it is the sheet's only entry,
    /// so nothing may hide it.
    static func showsPosesControl(showsPicker: Bool) -> Bool { showsPicker }

    /// The Poses control's E2E handle. It is the handle the picker flows already tap to open the sheet,
    /// so the product change (strip → sheet) does not also rename the entry point.
    static let posesControlIdentifier = "camera.choosePose"
    static let posesControlLabel = "Poses"

    /// What the Poses control announces as its value: **the reference it holds**, by name.
    ///
    /// The strip that used to draw the chosen pose's name (and its `camera.poseStrip.card.<id>` handle) is
    /// gone, so the control is the only place left that can say which guide is up. It said "Selected",
    /// which tells a VoiceOver user nothing about *which* pose they are about to line up against.
    static func posesControlValue(selectedPoseName: String?) -> String {
        guard let name = selectedPoseName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return "None selected" }
        return name
    }

    /// The bottom surface's vertical order, top to bottom. F5 puts the snackbar first, directly above
    /// the control bar: `CameraBottomBar` renders its children in exactly this order.
    enum BottomSlot: Equatable {
        case snackbar
        case scaleRow
        case panel
    }

    static let bottomSurfaceOrder: [BottomSlot] = [.snackbar, .scaleRow, .panel]

    /// Identifiers the strip used to expose. Retired with it: a flow that still looks for one is
    /// describing a screen that no longer exists, and this list is what says so.
    static let retiredIdentifiers = [
        "camera.poseStrip",
        "camera.poseStrip.retry",
        "camera.pickerStripToggle",
    ] + CameraZoomScale.retiredIdentifiers

    /// Every picker state now lives in the sheet (`posePicker.*`), so the bar draws no catalogue at all.
    static let bottomBarDrawsCatalogue = false
}

/// What a pose chosen in the picker sheet does: it becomes the camera's reference and the sheet closes,
/// so the user lands back on the framing they were about to shoot. It takes the camera's own model, so the
/// closing half is the real dismissal (`closePosePicker` on the state the view draws from) rather than a
/// closure a test could satisfy with a flag.
@MainActor
enum CameraPickerSelection {
    static func select(_ pose: NativePose, guide: Binding<NativePose?>, camera: CameraViewModel) {
        guide.wrappedValue = pose
        camera.closePosePicker()
    }
}

/// Snackbar · zoom row · shutter rail.
///
/// The whole bottom surface is one view so the snackbar's placement above the control bar is provable
/// from a rendered bitmap (see `CameraChromeTests`).
struct CameraBottomBar: View {
    let thumbnailURL: URL?
    let isBusy: Bool
    let canCapture: Bool
    let controlsEnabled: Bool
    let status: String?
    let statusTone: APStateTone
    /// Shutter-timer countdown (`nil` when idle): a visible number and its own Cancel.
    let timerCountdown: Int?
    let selectedPoseID: String?
    /// The selected reference's name, announced by the Poses control (the strip that used to draw it is
    /// retired).
    let selectedPoseName: String?
    let showsPicker: Bool
    /// The zoom the lens is at, and the range it can serve: one control, continuous.
    let zoomFactor: CGFloat
    let zoomRange: ClosedRange<CGFloat>
    let onOpenPosePicker: () -> Void
    let onZoomChange: (CGFloat) -> Void
    let onOpenGallery: () -> Void
    let onCapture: () -> Void
    let onSwitchCamera: () -> Void
    let onDismissStatus: () -> Void
    let onCancelTimer: () -> Void
    /// The home indicator's inset: the rail sits above it, while the preview keeps running underneath.
    let safeBottom: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if let status, !status.isEmpty {
                // F5: the snackbar sits at the bottom, directly above the control bar.
                APSnackbar(
                    tone: statusTone,
                    message: status,
                    actionTitle: statusTone == .success ? "View" : nil,
                    action: statusTone == .success ? onOpenGallery : nil,
                    onDismiss: onDismissStatus
                )
                .padding(.horizontal, AP.Space.space16)
                .padding(.bottom, AP.Space.space12)
                .accessibilityIdentifier("camera.status")
            }

            if let timerCountdown {
                countdownBadge(timerCountdown)
                    .padding(.bottom, AP.Space.space8)
            }

            scaleRow
                .padding(.bottom, AP.Space.space8)

            panel
        }
        .frame(maxWidth: .infinity)
        // The surface floats over the preview: a gradient fades the photo into the controls instead of an
        // opaque bar cutting the viewfinder in half. On 9:16 the frame runs under this band, which is exactly
        // where the gradient earns its keep.
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.45), Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .padding(.bottom, safeBottom)
    }

    /// The countdown: seconds left plus its own Cancel. Cancelling returns to ready with no photo;
    /// the shutter is not the cancel control, so a second press can never read as one.
    private func countdownBadge(_ seconds: Int) -> some View {
        HStack(spacing: AP.Space.space12) {
            Text("\(seconds)")
                .font(AP.Font.data)
                .foregroundStyle(AP.Color.primaryText)
                .accessibilityHidden(true)
            Text("Get ready")
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.secondaryText)
            Button("Cancel", action: onCancelTimer)
                .buttonStyle(.plain)
                .font(AP.Font.supporting.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
                .apMinimumHitTarget()
                .accessibilityIdentifier("camera.timer.cancel")
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.vertical, AP.Space.space8)
        .background(Capsule().fill(AP.Color.surface))
        .apElevation(.e1, cornerRadius: AP.Space.space24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timer \(seconds) seconds. Cancel the timer.")
        .accessibilityIdentifier("camera.timer.countdown")
    }

    // MARK: Panel

    private var panel: some View {
        rail
            .padding(.top, AP.Space.space12)
            .padding(.bottom, AP.Space.space8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedTopShape(radius: AP.Radius.radius24)
                    .fill(Color.black.opacity(0.5))
            )
            .accessibilityElement(children: .contain)
    }

    /// The Poses control at the right end of the scale row: it opens the picker sheet (search + All /
    /// Saved scopes), always, in one tap. The selected pose's name is its value, so the bar still says
    /// which reference is up without drawing a row of thumbnails.
    private var posesControl: some View {
        Button(action: onOpenPosePicker) {
            HStack(spacing: AP.Space.space4) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(AP.Font.caption.weight(.semibold))
                Text(CameraChromeLayout.posesControlLabel)
                    .font(AP.Font.supporting)
            }
            .foregroundStyle(AP.Color.primaryText)
            .padding(.horizontal, AP.Space.space16)
            .frame(minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(CameraPressStyle(shape: .capsule, restingFill: AP.Color.controlFill))
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel(selectedPoseID == nil ? "Choose a pose" : "Change pose")
        .accessibilityValue(CameraChromeLayout.posesControlValue(selectedPoseName: selectedPoseName))
        .accessibilityIdentifier(CameraChromeLayout.posesControlIdentifier)
    }

    // MARK: Zoom

    /// The band under the photo: the continuous zoom slider takes the left of the row and the Poses control
    /// keeps its right end.
    private var scaleRow: some View {
        HStack(spacing: AP.Space.space12) {
            CameraZoomSlider(
                factor: zoomFactor,
                range: zoomRange,
                isEnabled: controlsEnabled,
                onChange: onZoomChange
            )
            .frame(maxWidth: .infinity)

            if CameraChromeLayout.showsPosesControl(showsPicker: showsPicker) {
                posesControl
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CameraProto.controlInset)
    }

    // MARK: Rail

    private var rail: some View {
        HStack(spacing: 0) {
            thumbnailButton
            Spacer(minLength: 0)
            shutterButton
            Spacer(minLength: 0)
            flipButton
        }
        .padding(.horizontal, CameraProto.railInset)
        .frame(maxWidth: .infinity)
        .padding(.vertical, AP.Space.space8)
    }

    private var thumbnailButton: some View {
        Button(action: onOpenGallery) {
            Group {
                if let thumbnailURL {
                    KFImage(thumbnailURL)
                        .setProcessor(AppImage.downsample(squarePoints: CameraProto.railControl))
                        .placeholder { AP.Color.controlFill }
                        .onFailureView { AP.Color.controlFill }
                        .loadDiskFileSynchronously(false)
                        .contentConfigure { image, _ in
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                } else {
                    AP.Color.controlFill
                }
            }
            .frame(width: CameraProto.railControl, height: CameraProto.railControl)
            .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous))
        }
        .buttonStyle(CameraPressStyle())
        .accessibilityLabel("Open gallery")
        .accessibilityIdentifier("camera.gallery")
    }

    private var shutterButton: some View {
        Button(action: onCapture) {
            ZStack {
                if isBusy {
                    CameraShutterSpinner()
                } else {
                    Circle()
                        .strokeBorder(AP.Color.onAccent.opacity(0.55), lineWidth: 2)
                        .padding(AP.Space.space8)
                }
            }
            .frame(width: CameraProto.shutterSize, height: CameraProto.shutterSize)
            .background(
                Circle().fill(isBusy ? AP.Color.controlFill : AP.Color.accent)
            )
            .apElevation(.e1, cornerRadius: CameraProto.shutterSize / 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(isBusy ? 1 : 1)
        .opacity(canCapture || isBusy ? 1 : 0.45)
        .disabled(!canCapture || isBusy)
        .accessibilityLabel("Take photo")
        .accessibilityIdentifier("camera.shutter")
    }

    private var flipButton: some View {
        Button(action: onSwitchCamera) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(AP.Font.heading)
                .foregroundStyle(controlsEnabled ? AP.Color.primaryText : AP.Color.disabled)
                .frame(width: CameraProto.railControl, height: CameraProto.railControl)
        }
        .buttonStyle(CameraPressStyle(restingFill: AP.Color.controlFill))
        .disabled(!controlsEnabled)
        .accessibilityLabel("Switch to front camera")
        .accessibilityIdentifier("camera.flip")
    }
}

/// Spinner drawn inside the shutter while a capture is in flight: a glyph on the controlFill disc,
/// so a busy shutter reads as busy without a second control appearing.
private struct CameraShutterSpinner: View {
    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(AP.Color.primaryText.opacity(0.22), lineWidth: 3)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(AP.Color.primaryText, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(angle - 90))
        }
        .frame(width: 24, height: 24)
        .onAppear {
            withAnimation(.linear(duration: 0.75).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Picker scope (All / Saved)

/// The picker's two scopes (`05-camera-picker-loaded` boards: an All chip and a Saved chip).
enum CameraPickerScope: String, CaseIterable, Identifiable {
    case all = "All"
    case saved = "Saved"

    var id: String { rawValue }
    var accessibilityIdentifier: String { "posePicker.scope.\(rawValue.lowercased())" }

    /// The rows this scope draws from what is already in memory.
    ///
    /// **Saved** is the answer: the Saved screen's own filter, through the one name matcher every pose search
    /// uses (`PoseAdapterMerge.matchesName`). **All** is the *fallback* since the sheet started asking the
    /// server the Search screen's question: `PosePickerViewModel` uses this rule for the first paint under a
    /// new query and for the whole answer offline, while the query-less catalogue is in hand.
    func rows(catalogue: [NativePose], saved: [NativePose], query: String) -> [NativePose] {
        switch self {
        case .all:
            return catalogue.filter { PoseAdapterMerge.matchesName($0.name, query: query) }
        case .saved:
            return PoseAdapterMerge.filterSavedLocally(saved, query: query)
        }
    }
}

/// The camera picker's Saved collection.
///
/// A port, so the camera never reaches into a store: the app wires it to the same catalogue service
/// family the Saved screen uses (`PoseServiceBootstrap`), on its **own** filter slot, so asking for
/// `.saved` here cannot move the Poses tab's route. No new store and no sample rows: the adapter's
/// cache is the shared `PoseCatalogCacheStore`.
protocol CameraSavedPosesProviding: Sendable {
    func savedPoses() async throws -> [NativePose]
}

struct CatalogueSavedPosesService: CameraSavedPosesProviding {
    private let service: any PoseServing

    init(bundle: PoseServiceBundle = PoseServiceBootstrap.make()) {
        bundle.filterState.filter = .saved
        service = bundle.service
    }

    func savedPoses() async throws -> [NativePose] {
        try await service.poses(query: nil)
    }
}

/// The Saved chip's rows and their load. Coalesced and generation-guarded like the catalogue load:
/// the chip can be tapped while a request is in flight, and a stale answer (or an abandoned one) must
/// never replace a newer collection.
@MainActor
final class CameraSavedPosesModel: ObservableObject {
    @Published private(set) var state: Loadable<[NativePose]> = .idle

    private let provider: any CameraSavedPosesProviding
    private var inFlightLoad: Task<Void, Never>?
    private var loadGeneration = 0

    init(provider: any CameraSavedPosesProviding = CatalogueSavedPosesService()) {
        self.provider = provider
    }

    var rows: [NativePose] { state.rows }

    func load() async {
        if let inFlightLoad {
            await inFlightLoad.value
            return
        }
        loadGeneration &+= 1
        let generation = loadGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .loading
            do {
                let poses = try await self.provider.savedPoses()
                guard generation == self.loadGeneration else { return }
                self.state = poses.isEmpty ? .empty : .loaded(poses)
            } catch {
                guard generation == self.loadGeneration else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
        inFlightLoad = task
        await task.value
        if loadGeneration == generation { inFlightLoad = nil }
    }

    /// The scope left Saved, or the account changed: the rows go, so a return re-reads the account.
    func reset() {
        inFlightLoad?.cancel()
        inFlightLoad = nil
        loadGeneration &+= 1
        state = .idle
    }
}

/// What the Saved chip draws, from the session stage and the load state. Pure, so the three branches
/// (signed out, nothing saved, rows) are unit-tested and the sheet cannot invent a fourth.
enum CameraSavedScopePresentation: Equatable {
    case resolvingSession
    case signInRequired
    case loading
    case failed
    case empty
    case rows([NativePose])

    static func resolve(
        stage: SavedSurfaceStage,
        state: Loadable<[NativePose]>,
        isOffline: Bool
    ) -> CameraSavedScopePresentation {
        switch stage {
        case .resolvingSession:
            return .resolvingSession
        case .signInRequired:
            // The account gate wins over any rows: a guest is never shown cached rows as current.
            return .signInRequired
        case .list:
            switch state {
            case .idle, .loading:
                return .loading
            case .failed:
                return .failed
            case .empty:
                return .empty
            case .loaded(let poses):
                return poses.isEmpty ? .empty : .rows(poses)
            }
        }
    }

    /// The Saved chip's no-match card: a query that filters the account's own collection down to nothing is
    /// the shared no-match card, never a silently blank area under the chips — while a sign-in / loading /
    /// failed / empty *collection* keeps its own panel (that is not "no match", it is "no answer yet").
    /// Pure, and the sheet reads it, so the card's condition is a unit test rather than a screenshot.
    static func savedHasNoMatch(
        presentation: CameraSavedScopePresentation,
        rows: [NativePose],
        query: String
    ) -> Bool {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, rows.isEmpty else {
            return false
        }
        if case .rows = presentation { return true }
        return false
    }
}

// MARK: - Pose picker (camera-local bottom sheet, `.nb-pose-picker-*`)

/// Camera-local pose picker (`camera-guide.css` + `guide-picker.js`). It filters the loaded
/// catalogue locally — the prototype's `render()` re-renders from `getAvailablePoses()` on every
/// keystroke and only hits the "network" fixture once.
@MainActor
final class PosePickerViewModel: ObservableObject {
    @Published var state: Loadable<[NativePose]> = .idle
    /// The search field's text. A change schedules the **server** search: the sheet asks the same question
    /// the Search screen asks (`PoseServing.posesPage`), debounced and cancellable, and paints what is in hand
    /// while the answer is out.
    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }
    /// `forcedState === 'offline'`: the sheet keeps showing results with an offline notice.
    @Published private(set) var isOffline = false
    /// Which collection the sheet lists (`05-camera-picker-loaded`: All / Saved). Saved is
    /// account-scoped and loaded by `CameraSavedPosesModel`, never by this model.
    @Published var scope: CameraPickerScope = .all
    private let service: any PoseServing
    /// Typing debounce for the search, in nanoseconds. The Search screen waits 350 ms
    /// (`PosesViewModel.debounceNanoseconds`); the sheet keeps the same cadence so a keystroke is not a
    /// request.
    private let searchDebounceNanoseconds: UInt64
    /// The query-less catalogue this presentation loaded. It is the search's first paint and the whole answer
    /// offline, so a query never costs a blank grid — and never a second request for rows already in hand.
    private var catalogue: Loadable<[NativePose]> = .idle
    /// The debounced search. Cancelled by the next keystroke, so only the last text is asked for.
    private var searchTask: Task<Void, Never>?
    /// Bumped for every query that starts a search, and by every dismissal. An answer carrying an older
    /// generation is inert: a slow response for "wa" can never replace the grid "warrior" already got.
    private var searchGeneration = 0
    /// R7: reachability is created on presentation and torn down on dismissal — `NWPathMonitor`
    /// `cancel()` is terminal, so each presentation gets a fresh monitor rather than one running for
    /// the whole lifetime of the camera screen.
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "aipose.pose-picker.path")

    init(service: any PoseServing, searchDebounceNanoseconds: UInt64 = 350_000_000) {
        self.service = service
        self.searchDebounceNanoseconds = searchDebounceNanoseconds
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
    /// retries. Also stops reachability monitoring (R7) and abandons the search in flight.
    func prepareForDismissal() {
        query = ""
        state = .idle
        catalogue = .idle
        cancelSearch()
        stopMonitoring()
        abandonInFlightLoad()
    }

    /// The catalogue request currently running, if any. Two camera surfaces need the catalogue (the
    /// F12 strip and the picker sheet), so a second caller **joins** the request in flight instead of
    /// starting a competing one — there is no pair of requests that can finish out of order.
    private var inFlightLoad: Task<Void, Never>?
    /// Bumped for every request that is actually started, and again when a request is abandoned. A
    /// completion carrying an older generation can never replace newer state (a dismissed load that
    /// failed late must not overwrite the catalogue a newer request already returned).
    private var loadGeneration = 0

    func load() async {
        if let inFlightLoad {
            await inFlightLoad.value
            return
        }
        loadGeneration &+= 1
        let generation = loadGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.state = .loading
            do {
                let poses = try await self.service.poses(query: nil)
                guard generation == self.loadGeneration else { return }
                self.catalogue = poses.isEmpty ? .empty : .loaded(poses)
                // A search already owns the grid (the user typed while the catalogue was loading): its
                // first paint and its answer both outrank the plain catalogue.
                if self.trimmedQuery.isEmpty { self.state = self.catalogue }
            } catch {
                guard generation == self.loadGeneration else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
        inFlightLoad = task
        await task.value
        if loadGeneration == generation { inFlightLoad = nil }
    }

    // MARK: Search — the Search screen's question, asked from the sheet

    /// The text every search surface trims, so the request and the copy cannot disagree.
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What is in hand to narrow while the server has not answered: the query-less catalogue when it loaded,
    /// otherwise whatever answer is on screen.
    private var rowsInHand: [NativePose] {
        if case .loaded(let poses) = catalogue { return poses }
        return state.rows
    }

    /// The search field changed: repaint from what is in hand, then ask the server once the typing settles.
    private func scheduleSearch() {
        cancelSearch()
        let term = trimmedQuery
        guard !term.isEmpty else {
            // No query is no search: the catalogue is the answer and no request is spent on it.
            state = catalogue
            return
        }
        let firstPaint = CameraPickerScope.all.rows(catalogue: rowsInHand, saved: [], query: term)
        // A spinner, not the no-match card, while the answer is out: "no poses match" is a claim only the
        // server can make.
        state = firstPaint.isEmpty ? .loading : .loaded(firstPaint)

        // The raw field text is what the request carries (the Search screen sends the field text, not the
        // trimmed term); the fallback above uses the trimmed one because it is the matcher's rule.
        let text = query
        let generation = searchGeneration
        let debounce = searchDebounceNanoseconds
        searchTask = Task { @MainActor [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: debounce)
            }
            guard !Task.isCancelled, let self, generation == self.searchGeneration else { return }
            await self.search(text, generation: generation)
        }
    }

    /// Cancels the debounced search and makes any request already in flight inert.
    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
    }

    /// The server's answer for `text`, painted only if it is still the answer someone is waiting for.
    private func search(_ text: String, generation: Int) async {
        do {
            let page = try await fetchAll(query: text)
            guard generation == searchGeneration else { return }
            state = page.poses.isEmpty ? .empty : .loaded(page.poses)
        } catch {
            guard generation == searchGeneration else { return }
            // Offline (or a failure): the local name filter over the catalogue is the fallback, so the sheet
            // narrows what it has instead of blanking. With nothing in hand the card says why.
            let fallback = CameraPickerScope.all.rows(catalogue: rowsInHand, saved: [], query: text)
            state = fallback.isEmpty ? .failed(error.localizedDescription) : .loaded(fallback)
        }
    }

    /// **The call site.** The Search screen reads its rows with
    /// `service.posesPage(query: normalizedQuery, offset: 0, limit: PosesViewModel.Paging.pageSize)` — the field text, `nil`
    /// when it is empty, and the first window of `Paging.pageSize` rows (`PosesViewModel.load()`). The sheet
    /// asks exactly that, so "the same query" means the same request, the same rows and the same order. When
    /// the route travels *in* the request, this one method changes and nothing else does.
    private func fetchAll(query text: String) async throws -> PosePage {
        try await service.posesPage(
            query: text.isEmpty ? nil : text,
            offset: 0,
            limit: PosesViewModel.Paging.pageSize
        )
    }

    /// Drops the request behind the catalogue: the collapsed camera's dismissal retries on reopen
    /// (R6), so a late answer must not paint the sheet again. Bumping the generation is what makes
    /// the abandoned completion inert.
    private func abandonInFlightLoad() {
        inFlightLoad?.cancel()
        inFlightLoad = nil
        loadGeneration &+= 1
    }

    /// The All scope's rows for the current query. `state` **is** the answer: the server's rows when it has
    /// answered (the same request the Search screen makes), the local name filter over the catalogue while the
    /// answer is out or when the sheet is offline. Filtering again here would hide rows the server matched by
    /// something other than the name — exactly the disagreement with the Search screen this removed.
    var filteredPoses: [NativePose] { state.rows }

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

    /// Distinguishes the `.empty` card's two copies: a query that matched nothing versus an empty catalogue.
    /// Both arrive as `.empty` — the server's empty page *is* an empty list — so the query is what tells them
    /// apart: with no query there was nothing to match, and the catalogue itself is empty.
    var emptyIsNoMatch: Bool { !trimmedQuery.isEmpty }

    #if DEBUG
    /// Test seam: reachability is process-wide and cannot be driven from a unit test, but the
    /// `.offline` card has no other producer in the app and no screenshot path either.
    func setOfflineForTesting(_ offline: Bool) { isOffline = offline }

    /// Test seam: runs the search for the current text now instead of waiting out the debounce, so a test
    /// drives the request without a clock.
    func searchNowForTesting() async {
        let text = query
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        cancelSearch()
        await search(text, generation: searchGeneration)
    }
    #endif

    /// The scope chip. One control switches the collection and **keeps** the query: search sits above the
    /// chips and the chips narrow what the query already matched, so a tap that emptied the field would
    /// undo the typing that came first. One matcher serves both scopes, so the query cannot mean two
    /// different things after the switch.
    func selectScope(_ scope: CameraPickerScope) {
        guard scope != self.scope else { return }
        self.scope = scope
    }

    /// `pose-picker-search__clear`: resets to the full grid. Dropping the query cancels the search in flight
    /// and puts the loaded catalogue back, so clearing never costs a request.
    func clearSearch() {
        query = ""
    }
}

/// The sheet's vertical order, top to bottom. Search is the sheet's primary verb — it is how a catalogue
/// of hundreds is made usable — so it sits directly under the title, above the All/Saved chips, and the
/// chips then narrow what the query already matched. Pure, so the order is a unit test instead of a
/// screenshot: `PosePickerSheet.panel` renders exactly these rows in exactly this order.
enum PosePickerLayout {
    enum Row: Hashable {
        case handle
        case header
        case search
        case scopes
        case results
    }

    static let order: [Row] = [.handle, .header, .search, .scopes, .results]

    /// The rows above the results. The panel renders these in a `ForEach` and mounts the results scroll
    /// content **directly** after them: a flexible child mounted inside a `ForEach` is proposed its height
    /// differently, and the scroll content is the one child that has to fill the rest of the panel.
    /// `fixedRows + [.results] == order`, which the layout test pins.
    static let fixedRows: [Row] = order.filter { $0 != .results }

    /// The search field's own handle, and the clear button inside it.
    static let searchIdentifier = "posePicker.search"
    static let searchClearIdentifier = "posePicker.searchClear"
    static let closeIdentifier = "posePicker.close"
    static let stateIdentifier = "posePicker.state"
    static let gridIdentifier = "posePicker.grid"

    /// The sheet's own surface. It sits on the panel — the container that already declares
    /// `children: .contain` and the modal trait — never on the `GeometryReader` root, which is not an
    /// accessibility element (applying the id there collapses the subtree it wraps; see the R18 probe).
    static let sheetIdentifier = "posePicker.sheet"

    /// One pose row in the grid. The row keeps its `Use <name> pose` label; the id adds the stable handle a
    /// flow needs to pick a *specific* pose instead of "whichever row matched first".
    static func rowIdentifier(poseID: String) -> String { "posePicker.row.\(poseID)" }

    /// The scrollable content's order, top to bottom. The offline banner is a **row of the scroll
    /// content**, not an overlay: it pushes the grid down instead of covering its rows, so a populated
    /// grid can never have a row hidden under the notice.
    enum ContentRow: Equatable {
        case offlineBanner
        case statePanel
        case grid
    }

    static let contentOrder: [ContentRow] = [.offlineBanner, .statePanel, .grid]
}

/// The pose picker sheet: Camera stays visible behind it as the parent context; panel
/// `height: min(82%, 700px)`, `min-height: 420px`, `surface` fill, radius 24 on the top corners,
/// E2 overlay (no border, no hand-drawn shadow), handle, a Done action and **no Back button**. It
/// renders the camera's dark appearance, so the sheet reads as the same surface as the chrome.
private struct PosePickerSheet: View {
    @ObservedObject var model: PosePickerViewModel
    @ObservedObject var savedPoses: CameraSavedPosesModel
    @ObservedObject private var aspectRatioCache = PoseAspectRatioCache.shared
    let onClose: () -> Void
    let onSelect: (NativePose) -> Void
    @State private var columnByPoseID: [String: Int] = [:]
    /// The Saved chip's account gate: the same `SavedSurfaceStage` the Saved screen uses, so a guest
    /// sees the sign-in panel instead of cached rows.
    @StateObject private var session = SessionPresenceModel()

    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var savedStage: SavedSurfaceStage {
        SavedSurfaceStage.resolve(isSessionResolved: session.isResolved, isSignedIn: session.isSignedIn)
    }

    /// Identity of "the Saved chip is showing for this session stage".
    private var savedScopeTaskKey: String {
        switch (model.scope, savedStage) {
        case (.saved, .list): return "saved-list"
        case (.saved, .signInRequired): return "saved-signed-out"
        case (.saved, .resolvingSession): return "saved-resolving"
        case (.all, _): return "all"
        }
    }

    private var savedPresentation: CameraSavedScopePresentation {
        CameraSavedScopePresentation.resolve(
            stage: savedStage,
            state: savedPoses.state,
            isOffline: model.isOffline
        )
    }

    /// Rows the grid draws for the current scope.
    ///
    /// **All** draws the model's rows as they are: they are already the answer for the current query (the
    /// server's rows when it answered, the local name filter over the catalogue while the answer is out or
    /// offline — see `PosePickerViewModel`). Filtering again here would hide a row the server matched by
    /// something other than its name, which is exactly how the sheet and the Search screen used to disagree.
    /// **Saved** is the Saved screen's own filter, through the one shared matcher.
    private var visiblePoses: [NativePose] {
        switch model.scope {
        case .all:
            return model.state.rows
        case .saved:
            return CameraPickerScope.saved.rows(
                catalogue: model.state.rows,
                saved: savedPoses.rows,
                query: model.query
            )
        }
    }

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
        .environment(\.colorScheme, pickerColorScheme)
        .task { session.start() }
        // The Saved chip loads when it is shown *and* the session has resolved to signed-in: the stage
        // is the task's identity, so a sign-in that lands after the sheet opened still runs the load
        // instead of leaving the chip on its loading panel.
        .task(id: savedScopeTaskKey) {
            guard model.scope == .saved, savedStage == .list else { return }
            if case .loaded = savedPoses.state { return }
            await savedPoses.load()
        }
        .onChange(of: session.isSignedIn) { _ in
            // Another Account's saved rows must not survive the switch (same rule as the Saved screen).
            savedPoses.reset()
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 18)))
        // R18 probe: `.isModal` was applied here, on the GeometryReader root. Applied to a container
        // that is not itself an accessibility element, SwiftUI collapses the subtree it wraps — the
        // panel's header and search field vanished from the tree while only the ScrollView's contents
        // stayed. Moving it onto the panel (a real container, declared with `children: .contain`)
        // keeps the modal trait and preserves the descendants.
    }

    /// The camera forces a dark scheme on itself, but this sheet is a browsing surface and follows the
    /// app's appearance setting (System / Light / Dark), falling back to the device's own style.
    private var pickerColorScheme: ColorScheme {
        if let chosen = APAppearance.load().colorScheme { return chosen }
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }

    /// The sheet's scrim (`scrim` token: 64% black in the camera's dark appearance).
    private var backdrop: some View {
        AP.Color.scrim
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
            .accessibilityHidden(true)
    }

    private func panel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Rendered from `PosePickerLayout.order`, so the order the tests assert is the order drawn —
            // with the results mounted as a direct child, not inside the `ForEach`.
            ForEach(PosePickerLayout.fixedRows, id: \.self) { row in
                panelRow(row)
            }
            scrollContent
                .frame(maxHeight: .infinity)
        }
        .padding(EdgeInsets(
            top: AP.Space.space12,
            leading: AP.Space.space16,
            bottom: AP.Space.space16,
            trailing: AP.Space.space16
        ))
        .frame(maxHeight: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(
            RoundedTopShape(radius: AP.Radius.radius24)
                .fill(AP.Color.surface)
        )
        .clipShape(RoundedTopShape(radius: AP.Radius.radius24))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier(PosePickerLayout.sheetIdentifier)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 18)))
    }

    @ViewBuilder
    private func panelRow(_ row: PosePickerLayout.Row) -> some View {
        switch row {
        case .handle: handle
        case .header: header
        case .search: searchField
        case .scopes: scopeChips
        case .results: scrollContent
        }
    }

    /// The grabber: `separator` fill, centred, decorative.
    private var handle: some View {
        Capsule()
            .fill(AP.Color.separator)
            .frame(width: AP.Space.space32, height: AP.Space.space4)
            .padding(.bottom, AP.Space.space16)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// Title + the sheet's Done action (accentText, 44 pt). No Back button.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: AP.Space.space8) {
            Text("Choose a pose")
                .font(AP.Font.title)
                .foregroundStyle(AP.Color.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Button("Done", action: onClose)
                .buttonStyle(.plain)
                .font(AP.Font.supporting.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
                .apMinimumHitTarget()
                .accessibilityLabel("Close pose picker")
                .accessibilityIdentifier(PosePickerLayout.closeIdentifier)
        }
        .padding(.bottom, AP.Space.space12)
    }

    /// The All / Saved scope chips (`05-camera-picker-loaded`). The selected chip carries a check glyph
    /// and its own word, so the chosen collection is never colour-only.
    private var scopeChips: some View {
        HStack(spacing: AP.Space.space8) {
            ForEach(CameraPickerScope.allCases) { scope in
                scopeChip(scope)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, AP.Space.space12)
        // A container, not a single element: each chip keeps its own identifier
        // (`posePicker.scope.all|saved`) while the row keeps `posePicker.scope`. Without this the row's id
        // is inherited by both chips and overwrites theirs, so they render but nothing can address them.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("posePicker.scope")
    }

    private func scopeChip(_ scope: CameraPickerScope) -> some View {
        let isSelected = model.scope == scope
        return Button {
            model.selectScope(scope)
        } label: {
            HStack(spacing: AP.Space.space4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AP.Font.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(scope.rawValue)
                    .font(AP.Font.supporting.weight(.semibold))
            }
            .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .padding(.horizontal, AP.Space.space16)
            .frame(minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(CameraPressStyle(isSelected: isSelected, shape: .capsule, restingFill: AP.Color.controlFill))
        .accessibilityLabel("\(scope.rawValue) poses")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier(scope.accessibilityIdentifier)
    }

    /// Search: `controlFill` field, radius 16, 48 pt tall, no resting border — focus is the only
    /// ring (the shared `outline` focus ring), never a border token.
    private var searchField: some View {
        HStack(spacing: AP.Space.space8) {
            Image(systemName: "magnifyingglass")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.secondaryText)
                .frame(width: 22)
                .accessibilityHidden(true)

            TextField("Search poses", text: $model.query)
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .tint(AP.Color.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
                .accessibilityIdentifier(PosePickerLayout.searchIdentifier)

            if !model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    model.clearSearch()
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(AP.Font.caption.weight(.bold))
                        .foregroundStyle(AP.Color.primaryText)
                        .frame(width: 17, height: 17)
                }
                .buttonStyle(.plain)
                .apMinimumHitTarget()
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier(PosePickerLayout.searchClearIdentifier)
            }
        }
        .padding(.horizontal, AP.Space.space12)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .apFocusRing(isFocused: isSearchFocused, cornerRadius: AP.Radius.radius16)
        .padding(.bottom, AP.Space.space12)
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // R5: the notice sits above a populated grid instead of replacing it.
                if model.showsOfflineNotice {
                    APOfflineBanner(message: "Showing your last available poses.", retryTitle: nil, retry: nil)
                        .padding(.bottom, AP.Space.space12)
                }
                stateSurface
                poseGrid
            }
            .padding(.bottom, AP.Space.space24)
        }
    }

    /// F4: the picker's loading / error / empty / no-match / offline states all render through the
    /// shared 72 pt state panel. `CameraStatePanel.picker` owns the selection, so the sheet cannot
    /// drift back to the old stacked-tile card.
    @ViewBuilder
    private var stateSurface: some View {
        switch model.scope {
        case .saved:
            if savedScopeHasNoMatch {
                // Same search, same answer: a query that filters the saved collection out is the shared
                // no-match card, never a silently blank area under the chips.
                pickerPanel(.pickerNoMatch(trimmedQuery)) {
                    Task { await savedPoses.load() }
                }
            } else {
                savedStateSurface
            }
        case .all:
            if let panel = CameraStatePanel.picker(
                tone: model.stateTone,
                isNoMatch: model.emptyIsNoMatch,
                term: trimmedQuery,
                isOffline: model.isOffline
            ) {
                pickerPanel(panel) {
                    Task { await model.load() }
                }
            }
        }
    }

    /// The trimmed query every surface reads, so the card's copy and the filter cannot disagree.
    private var trimmedQuery: String {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The Saved chip loaded a collection, and the query matched none of it.
    private var savedScopeHasNoMatch: Bool {
        CameraSavedScopePresentation.savedHasNoMatch(
            presentation: savedPresentation,
            rows: visiblePoses,
            query: trimmedQuery
        )
    }

    /// One state panel, one handle: the sheet's states are all `posePicker.state`.
    private func pickerPanel(_ panel: CameraStatePanel, onRetry: @escaping () -> Void) -> some View {
        CameraPickerStatePanel(panel: panel, onRetry: onRetry)
            // Same rule as the rows above: the panel owns `posePicker.state`, and the card's own controls
            // (the retry) stay separate elements instead of inheriting the panel's id.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(PosePickerLayout.stateIdentifier)
    }

    /// The Saved chip's panels. Copy is the Saved screen's own (`PoseResultsStateCopy`), so the two
    /// surfaces cannot describe the same collection differently, and the panels are the shared
    /// `FeatureStateView` call API — another surface owner may restyle its internals without touching
    /// this call site.
    @ViewBuilder
    private var savedStateSurface: some View {
        switch savedPresentation {
        case .resolvingSession:
            FeatureStateView(
                tone: .loading,
                title: PoseResultsStateCopy.savedLoadingTitle,
                message: PoseResultsStateCopy.savedLoadingMessage
            )
            .accessibilityIdentifier("posePicker.saved.loading")
        case .signInRequired:
            FeatureStateView(
                tone: .empty,
                title: PoseResultsStateCopy.savedSignInTitle,
                message: PoseResultsStateCopy.savedSignInMessage
            )
            .accessibilityIdentifier("posePicker.saved.signIn")
        case .loading:
            FeatureStateView(
                tone: .loading,
                title: PoseResultsStateCopy.savedLoadingTitle,
                message: PoseResultsStateCopy.savedLoadingMessage
            )
            .accessibilityIdentifier("posePicker.saved.loading")
        case .failed:
            FeatureStateView(
                tone: model.isOffline ? .offline : .error,
                title: model.isOffline ? "You're offline" : PoseResultsStateCopy.savedErrorTitle,
                message: model.isOffline ? "Saved poses appear here again when you're back online." : PoseResultsStateCopy.savedErrorMessage,
                actionTitle: model.isOffline ? nil : PoseResultsStateCopy.retryActionTitle
            ) {
                Task { await savedPoses.load() }
            }
            .accessibilityIdentifier("posePicker.saved.error")
        case .empty:
            FeatureStateView(
                tone: .empty,
                title: PoseResultsStateCopy.savedEmptyTitle,
                message: PoseResultsStateCopy.savedEmptyMessage
            )
            .accessibilityIdentifier("posePicker.saved.empty")
        case .rows:
            EmptyView()
        }
    }

    /// `.nb-pose-picker-grid` — two-column staggered cards reusing the Poses visual language
    /// (`PoseCard` + `PoseGridMetrics`, `.nb-grid--masonry`).
    @ViewBuilder
    private var poseGrid: some View {
        let poses = visiblePoses
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
                            .accessibilityIdentifier(PosePickerLayout.rowIdentifier(poseID: item.pose.id))
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
            .accessibilityValue(model.scope.rawValue)
            .accessibilityIdentifier(PosePickerLayout.gridIdentifier)
        }
    }

    private var itemsByColumn: [[PickerItem]] {
        var columns = Array(repeating: [PickerItem](), count: 2)
        for (index, pose) in visiblePoses.enumerated() {
            let column = columnByPoseID[pose.id] ?? (index % 2)
            columns[column].append(PickerItem(index: index, pose: pose))
        }
        return columns
    }

    private func rebuildAssignments() {
        let poses = visiblePoses
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

/// The strip / grid card press: the shared pressed response — one fill step and `scale 0.97`
/// (fill only under Reduce Motion), never a translated hard shadow.
private struct GuideCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // The card draws its own surface, so only the pressed step is painted here.
        CameraPressBody(configuration: configuration, isSelected: false, shape: .rounded16, restingFill: .clear)
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

struct StickFigureView: View {
    let kind: StickFigurePose
    var lineColor: Color = AP.Color.primaryText

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
