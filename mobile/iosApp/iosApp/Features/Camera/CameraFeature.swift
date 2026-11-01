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
    /// F12: `true` draws the pose picker strip above the control bar, `false` is the collapsed camera
    /// (thumbnail · shutter · flip only) with the strip behind one clear control. Persisted.
    @Published var isPickerExpanded = true
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

    /// The zoom presets this lens can serve (`0.5x` only where the device's minimum allows it).
    var zoomPresets: [CameraZoomPreset] {
        CameraZoomPresets.available(range: deviceZoomRange)
    }

    /// The preset the current zoom is nearest to, so the pill highlights a real choice.
    var activeZoomPreset: CameraZoomPreset? {
        CameraZoomPresets.nearest(to: zoomLevel.factor, range: deviceZoomRange)
    }

    /// Selecting a preset applies it (clamped to the lens) and keeps the persisted level in step.
    func selectZoomPreset(_ preset: CameraZoomPreset) {
        guard cameraControlsEnabled else { return }
        applyZoom(factor: CameraZoomPresets.clamp(preset.factor, range: deviceZoomRange))
    }

    func applyZoom(factor: CGFloat) {
        zoomFactor = CameraZoomPresets.clamp(factor, range: deviceZoomRange)
        zoomLevel = CameraZoomLevel.nearest(to: zoomFactor)
        reconcileHardware()
    }

    /// The active lens's zoom range, best effort: the simulator has no capture device, so the shipped
    /// presets (1x/2x) are the fallback.
    private var deviceZoomRange: ClosedRange<CGFloat> {
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

    // MARK: - Picker strip (F12 collapsed / expanded)

    /// Opens and closes the picker strip. This is the **single** control that re-opens the strip: the
    /// Poses control at the right end of the scale row. The strip's own Browse entry
    /// (`camera.choosePose`) opens the full picker *sheet* (search + All/Saved scopes).
    func togglePickerStrip() {
        guard cameraControlsEnabled else { return }
        isPickerExpanded.toggle()
    }

    func expandPickerStrip() {
        guard cameraControlsEnabled else { return }
        isPickerExpanded = true
    }

    func collapsePickerStrip() {
        guard cameraControlsEnabled else { return }
        isPickerExpanded = false
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

    func cycleZoom() {
        guard cameraControlsEnabled else { return }
        applyZoom(zoomLevel.next())
    }

    func applyZoom(_ level: CameraZoomLevel) {
        applyZoom(factor: level.factor)
    }

    // MARK: - Settings persistence (FEAT-012)

    /// The eight settings that survive a relaunch. `CameraSnapshot` carries them in one JSON blob;
    /// the selected pose is deliberately not among them (D8).
    private enum PersistedSetting: Hashable {
        case opacity, flipped, grid, flash, guideVisibility, lineColor, transform, zoom, pickerExpanded, timer, aspectRatio
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
        $isPickerExpanded.dropFirst().sink { [weak self] _ in self?.settingsDidChange(.pickerExpanded) }
            .store(in: &cancellables)
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
            isPickerExpanded: isPickerExpanded,
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
        if !touchedSettings.contains(.pickerExpanded) { isPickerExpanded = stored.isPickerExpanded }
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

extension CameraZoomLevel {
    /// The stored level nearest a lens factor. The enum keeps every pre-existing settings row readable;
    /// the exact factor (which can be 0.5x) lives beside it.
    static func nearest(to factor: CGFloat) -> CameraZoomLevel {
        allCases.min {
            abs(CGFloat($0.rawValue) - factor) < abs(CGFloat($1.rawValue) - factor)
        } ?? .one
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

/// Lens-aware zoom presets (`05-01`/`05-21`: 0.5x / 1x / 2x). A preset the lens cannot serve is not
/// offered at all, and a request outside the device's range is clamped instead of failing silently.
enum CameraZoomPreset: String, CaseIterable, Identifiable, Sendable {
    case half = "0.5x"
    case one = "1x"
    case two = "2x"

    var id: String { rawValue }
    var factor: CGFloat {
        switch self {
        case .half: return 0.5
        case .one: return 1
        case .two: return 2
        }
    }
    var accessibilityIdentifier: String { "camera.zoom.\(rawValue)" }
}

enum CameraZoomPresets {
    static func available(range: ClosedRange<CGFloat>) -> [CameraZoomPreset] {
        let presets = CameraZoomPreset.allCases.filter { range.contains($0.factor) }
        // 1x always exists: it is the lens's native framing even when a device reports a minimum of
        // exactly 1 (every iPhone does).
        return presets.isEmpty ? [.one] : presets
    }

    static func clamp(_ factor: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        guard factor.isFinite else { return 1 }
        return min(max(factor, range.lowerBound), range.upperBound)
    }

    /// The preset closest to a factor, so a clamped or restored value still lights up a choice.
    static func nearest(to factor: CGFloat, range: ClosedRange<CGFloat>) -> CameraZoomPreset? {
        available(range: range).min { abs($0.factor - factor) < abs($1.factor - factor) }
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

/// Saved-photo post-processing for the ratio: the file behind the gallery row is cropped to the aspect
/// the user framed with, so the saved dimensions match the preview (and are asserted in tests).
enum CameraImagePostProcess {
    @discardableResult
    static func cropFileInPlace(at path: String, ratio: CameraAspectRatio) -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let image = UIImage(data: data),
              let cgImage = image.cgImage else { return false }
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        guard CameraAspectCrop.needsCrop(ratio: ratio, imageSize: pixelSize) else { return false }
        let rect = CameraAspectCrop.rect(for: ratio, imageSize: pixelSize).integral
        guard let cropped = cgImage.cropping(to: rect) else { return false }
        let output = UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
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
    /// In-flight pinch / twist / drag, folded into `model.guideTransform` when the gesture ends.
    @GestureState private var guideGestureDelta = GuideTransform.Delta.identity
    /// Height of the top control bar, measured so the tools popup anchors *under* it at every
    /// Dynamic Type size instead of at a hard-coded offset.
    @State private var topBarHeight: CGFloat = AP.HitTarget.minimum

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
            VStack(spacing: 0) {
                viewport
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
                        guide = pose
                        model.closePosePicker()
                    }
                )
                .zIndex(2)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.showPosePicker)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: model.showCameraTools)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.isPickerExpanded)
        .background(AP.Color.background.ignoresSafeArea())
        // The camera is a dark surface, and every AP token inside it has to resolve that way even when
        // the screen is hosted outside a dark presentation (UIKit host, preview, snapshot): the canvas,
        // the chrome and the pose reference's white line colour are all read from the dark values.
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea(.container, edges: .top)
        .neoHiddenNavigationBar()
        .preferredColorScheme(.dark)
        .task { await model.onAppear() }
        .onAppear { model.guideAppeared(hasGuide: guide != nil) }
        .onDisappear { model.onDisappear() }
        .task(id: stripCatalogueID) {
            // The strip draws the same catalogue the sheet does, so it is loaded once for both. Not
            // while the camera is refused (nothing to place a pose on) and not while it is collapsed
            // (the strip is not on screen to show what the load returns).
            guard isAuthorized, model.isPickerExpanded else { return }
            if case .loaded = posePickerModel.state { return }
            await posePickerModel.load()
        }
        .task(id: model.showPosePicker) {
            if model.showPosePicker {
                // R7: monitor only while the sheet is presented.
                posePickerModel.startMonitoring()
                // R6: reopen always retries unless a grid is already in hand, so a dismissed failure
                // (or a load that failed after dismissal) cannot strand the sheet.
                if case .loaded = posePickerModel.state { return }
                await posePickerModel.load()
            } else if model.isPickerExpanded {
                // The strip keeps drawing the rows it already has, and reopening still retries a
                // failed load, so the catalogue has to survive a dismissal that leaves it on screen.
                posePickerModel.dismissKeepingCatalogue()
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

    /// Identity of "the strip should have the catalogue": authorization plus the collapsed state.
    private var stripCatalogueID: String {
        "\(isAuthorized)-\(model.isPickerExpanded)"
    }

    // MARK: Viewport — full-bleed `.nb-camera-viewport--immersive`

    private var viewport: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .bottomTrailing) {
                cameraCanvas(size: size)

                // `.nb-camera-tools-menu` — anchored popup: below the tools control, no scrim, no
                // handle, no app-bar Close.
                if model.showCameraTools {
                    // Outside tap dismisses without a visible scrim.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissCameraTools() }
                        .accessibilityHidden(true)

                    VStack(spacing: 0) {
                        CameraToolsPopup(
                            flashSetting: model.flashSetting,
                            isGridVisible: model.isGridVisible,
                            controlsEnabled: model.cameraControlsEnabled,
                            hasPose: guide != nil,
                            isPoseGuideVisible: model.isPoseGuideVisible,
                            guideFlipped: model.guideFlipped,
                            timerSetting: model.timerSetting,
                            aspectRatio: model.aspectRatio,
                            guideOpacity: model.guideOpacity,
                            guideScale: model.guideTransform.scale,
                            guideLineColor: model.guideLineColor,
                            popupWidth: min(CameraProto.popupWidth, size.width - CameraProto.controlInset * 2),
                            popupMaxHeight: max(
                                AP.Space.space48,
                                min(
                                    size.height - CameraProto.topControlsTop - topBarHeight - AP.Space.space16,
                                    CameraProto.popupMaxHeight
                                )
                            ),
                            onFlashTap: { model.cycleFlash() },
                            onGridToggle: { model.toggleGrid() },
                            onPoseGuideVisibilityToggle: { model.togglePoseGuideVisibility() },
                            onMirrorToggle: { model.toggleGuideMirror() },
                            onTimerChange: { model.setTimerSetting($0) },
                            onAspectRatioChange: { model.setAspectRatio($0) },
                            onGuideScaleChange: { model.setGuideScale($0) },
                            onGuideScaleReset: { model.resetGuideTransform() },
                            onGuideOpacityChange: { model.setGuideOpacity($0) },
                            onGuideLineColorChange: { model.setGuideLineColor($0) },
                            onDismiss: { dismissCameraTools() }
                        )
                        .padding(.top, CameraProto.topControlsTop + topBarHeight + AP.Space.space8)
                        .padding(.trailing, CameraProto.controlInset)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity
                        .combined(with: .offset(y: -AP.Space.space8))
                        .combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                }
            }
        }
        .overlay(alignment: .top) {
            topControls
                .padding(.horizontal, CameraProto.controlInset)
                .padding(.top, CameraProto.topControlsTop)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: CameraTopBarHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .onPreferenceChange(CameraTopBarHeightKey.self) { height in
            guard height > 0 else { return }
            topBarHeight = height
        }
    }

    /// F12: the whole bottom control surface — snackbar, zoom, pose strip (or its clear re-open
    /// control) and the shutter rail. One view, so a rendered test can prove what is on screen.
    private var bottomChrome: some View {
        CameraBottomBar(
            thumbnailURL: model.latestThumbnailURL,
            isBusy: model.coordinator.state.isCaptureInFlight,
            canCapture: model.isShutterEnabled,
            controlsEnabled: model.cameraControlsEnabled,
            status: model.statusMessage,
            statusTone: model.statusTone,
            timerCountdown: model.timerCountdown,
            strip: stripContent,
            selectedPoseID: guide?.id,
            isPickerExpanded: model.isPickerExpanded,
            showsPicker: isAuthorized,
            zoomPresets: model.zoomPresets,
            activeZoomPreset: model.activeZoomPreset,
            onToggleStrip: { model.togglePickerStrip() },
            onSelectPose: { pose in guide = pose },
            onBrowse: { model.openPosePicker() },
            onRetryStrip: { Task { await posePickerModel.load() } },
            onZoomPreset: { preset in model.selectZoomPreset(preset) },
            onOpenGallery: onOpenGallery,
            onCapture: { model.capture() },
            onSwitchCamera: { model.switchCamera() },
            onDismissStatus: { model.dismissStatusMessage() },
            onCancelTimer: { model.cancelTimer() }
        )
    }

    /// What the strip draws. Pure mapping, so "failed" cannot silently render an empty grid.
    private var stripContent: CameraStripContent {
        CameraStripContent.resolve(from: posePickerModel.state, filtered: posePickerModel.filteredPoses)
    }

    private func dismissCameraTools() {
        guard model.showCameraTools else { return }
        model.closeCameraTools()
        // Focus returns to the More control (`guide-picker.js` `setOpen(false)` → `openButton.focus()`).
        isToolsButtonFocused = true
    }

    private func cameraCanvas(size: CGSize) -> some View {
        ZStack {
            AP.Color.background

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
                    // E2E handle (`QA-261029-ID`): the only way a flow can prove a guide is drawn and
                    // say *which* pose it is. Built only when a visible guide exists, so a missing id
                    // is "no pose guide on screen" (no pose, or the guide toggle is off).
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Pose guide")
                    .accessibilityValue(guide.id)
                    .accessibilityIdentifier("camera.poseGuide")
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

            // F4: the camera's permission state is the shared 72 pt panel, over the scrim.
            if !isAuthorized {
                permissionPanel
            }
        }
        .clipped()
    }

    /// `.nb-camera-viewport__top-scrim` (190px) / `__bottom-scrim` (170px).
    private var verticalScrims: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [AP.Color.background.opacity(0.68), AP.Color.background.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 190)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [AP.Color.background.opacity(0), AP.Color.background.opacity(0.54)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 170)
        }
        .allowsHitTesting(false)
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

    // The guide's drawing stays hidden from accessibility; `camera.poseGuide` is set on the wrapper
    // that is only built while a visible guide exists.

    /// Same stand-in the `AsyncImage` placeholder used before the guide asset loads. The stroke
    /// follows the tools popup Line colour (`--nb-camera-pose-line-color`).
    private func guideFallback(for guide: NativePose) -> StickFigureView {
        StickFigureView(kind: .resolve(name: guide.name, category: guide.category, index: 0),
                        lineColor: model.guideLineColor.color)
    }

    /// F4: the camera's permission state is the shared 72 pt state panel — one clean accent-tint
    /// circle, title, copy and one action — instead of the old stacked camera tile on a yellow square.
    private var permissionPanel: some View {
        CameraPermissionPanel(
            permission: model.coordinator.state.permission,
            onAllow: { model.requestPermission() },
            onOpenSettings: openSystemSettings,
            onDismiss: onClose
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AP.Color.scrim)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Camera metrics
//
// Only the layout numbers that have no token (absolute prototype geometry: the immersive top inset,
// the pose-reference insets, the popup and sheet caps) live here. Colours, radii, spacing, type and
// elevation come from `AP`.

enum CameraProto {
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
            APEmptyStateView(
                title: "No poses match “\(term)”",
                message: "Try a different pose name.",
                style: .plain,
                glyph: "magnifyingglass"
            )
        case .pickerOffline:
            APOfflineBanner(message: "You're offline", retryTitle: "Retry", retry: onRetry)
        }
    }
}

// MARK: - Bottom control surface (F12 collapsed / expanded)

/// What the pose strip draws. A pure mapping from the picker's `Loadable`, so a failed or empty
/// catalogue can never render as a blank strip that looks like "no poses".
enum CameraStripContent: Equatable {
    case loading
    case failed
    case empty
    case poses([NativePose])

    /// One mapping for every picker state. A loaded catalogue whose local filter matches nothing is
    /// `.empty` ("no poses match"), never a blank strip; a first-load failure is `.failed`, which
    /// keeps a retry within reach instead of showing an empty row.
    static func resolve(from state: Loadable<[NativePose]>, filtered: [NativePose]) -> CameraStripContent {
        switch state {
        case .idle, .loading:
            return .loading
        case .failed:
            return .failed
        case .empty:
            return .empty
        case .loaded:
            return filtered.isEmpty ? .empty : .poses(filtered)
        }
    }
}

/// Which parts of the bottom surface are on screen (F12). Pure, so "collapsed still has a way back"
/// is a unit test instead of something only a screenshot can show.
enum CameraChromeLayout {
    /// The strip itself is drawn only while expanded and only when the camera can place a pose.
    static func showsStrip(isPickerExpanded: Bool, showsPicker: Bool) -> Bool {
        showsPicker && isPickerExpanded
    }

    /// The control that re-opens (and closes) the strip is always there when a picker is available —
    /// the collapsed state must never hide its own way back.
    static func showsStripToggle(showsPicker: Bool) -> Bool { showsPicker }

    static func stripToggleGlyph(isPickerExpanded: Bool) -> String {
        isPickerExpanded ? "chevron.down" : "chevron.up"
    }

    static func stripToggleLabel(isPickerExpanded: Bool) -> String {
        isPickerExpanded ? "Hide pose picker" : "Show pose picker"
    }

    /// What the Poses control does on the scale row. It is the only way into the picker, so a collapsed
    /// camera always expands first; the strip itself carries the sheet's Browse entry
    /// (`camera.choosePose` → search + All/Saved scopes).
    enum PickerControlTarget: Equatable {
        case expandStrip
        case collapseStrip
    }

    static func pickerControlTarget(isPickerExpanded: Bool) -> PickerControlTarget {
        isPickerExpanded ? .collapseStrip : .expandStrip
    }

    /// The strip's Browse entry is only meaningful while the strip is on screen.
    static func showsStripBrowse(isPickerExpanded: Bool, showsPicker: Bool) -> Bool {
        showsPicker && isPickerExpanded
    }

    /// The bottom surface's vertical order, top to bottom. F5 puts the snackbar first, directly above
    /// the control bar: `CameraBottomBar` renders its children in exactly this order.
    enum BottomSlot: Equatable {
        case snackbar
        case scaleRow
        case panel
    }

    static let bottomSurfaceOrder: [BottomSlot] = [.snackbar, .scaleRow, .panel]

    /// The full picker sheet's handle, kept from the removed top pill so the E2E path is unchanged.
    static let browseIdentifier = "camera.choosePose"
}

/// Snackbar · zoom · pose strip (or its re-open control) · shutter rail.
///
/// The whole bottom surface is one view so the two F12 states and the snackbar's placement above the
/// control bar are provable from a rendered bitmap (see `CameraChromeTests`).
struct CameraBottomBar: View {
    let thumbnailURL: URL?
    let isBusy: Bool
    let canCapture: Bool
    let controlsEnabled: Bool
    let status: String?
    let statusTone: APStateTone
    /// Shutter-timer countdown (`nil` when idle): a visible number and its own Cancel.
    let timerCountdown: Int?
    let strip: CameraStripContent
    let selectedPoseID: String?
    let isPickerExpanded: Bool
    let showsPicker: Bool
    let zoomPresets: [CameraZoomPreset]
    let activeZoomPreset: CameraZoomPreset?
    let onToggleStrip: () -> Void
    let onSelectPose: (NativePose) -> Void
    let onBrowse: () -> Void
    let onRetryStrip: () -> Void
    let onZoomPreset: (CameraZoomPreset) -> Void
    let onOpenGallery: () -> Void
    let onCapture: () -> Void
    let onSwitchCamera: () -> Void
    let onDismissStatus: () -> Void
    let onCancelTimer: () -> Void

    @ScaledMetric(relativeTo: .caption) private var cardWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .caption) private var cardImageHeight: CGFloat = 92

    /// The strip is chrome, not content: at AX3 its cards grow, but the image stops at 140 pt so the
    /// bar can never take the whole viewport away from the pose guide. The name wraps instead.
    private var stripImageHeight: CGFloat { min(cardImageHeight, 140) }

    /// Two caption lines under the image: the strip has one deterministic height in every state, so
    /// the bar cannot jump when a load lands mid-scroll.
    @ScaledMetric(relativeTo: .caption) private var cardCaptionHeight: CGFloat = 36
    private var stripRowHeight: CGFloat { stripImageHeight + cardCaptionHeight + AP.Space.space8 }

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
        .background(AP.Color.background)
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
        VStack(spacing: AP.Space.space8) {
            if CameraChromeLayout.showsStrip(isPickerExpanded: isPickerExpanded, showsPicker: showsPicker) {
                stripView
            }
            rail
        }
        .padding(.top, AP.Space.space12)
        .padding(.bottom, AP.Space.space8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedTopShape(radius: AP.Radius.radius24)
                .fill(Color.black.opacity(0.5))
        )
        .accessibilityElement(children: .contain)
    }

    /// The clear control that re-opens (and closes) the picker strip: glyph + word, never a hidden
    /// gesture, so the collapsed camera can always get back to the strip.
    private var stripToggle: some View {
        Button(action: onToggleStrip) {
            HStack(spacing: AP.Space.space4) {
                Image(systemName: CameraChromeLayout.stripToggleGlyph(isPickerExpanded: isPickerExpanded))
                    .font(AP.Font.caption.weight(.semibold))
                Text("Poses")
                    .font(AP.Font.supporting)
            }
            .foregroundStyle(AP.Color.primaryText)
            .padding(.horizontal, AP.Space.space16)
            .frame(minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(CameraPressStyle(shape: .capsule, restingFill: AP.Color.controlFill))
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel(CameraChromeLayout.stripToggleLabel(isPickerExpanded: isPickerExpanded))
        .accessibilityValue(isPickerExpanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("camera.pickerStripToggle")
    }

    @ViewBuilder private var stripView: some View {
        switch strip {
        case .poses(let poses):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AP.Space.space8) {
                    // The Browse card leads the strip. As the trailing card it left the viewport as soon
                    // as the catalogue filled the row, and the sheet had no other entry point.
                    if showsPicker {
                        browseAllCard
                    }
                    ForEach(poses) { pose in stripCard(pose) }
                }
                .padding(.horizontal, AP.Space.space16)
            }
            .frame(height: stripRowHeight)
            .accessibilityIdentifier("camera.poseStrip")
        case .loading:
            // Flat controlFill skeleton cards — the loading look, not a spinner over nothing.
            HStack(spacing: AP.Space.space8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                        .fill(AP.Color.controlFill)
                        .frame(width: cardWidth, height: stripImageHeight)
                }
            }
            .frame(maxWidth: .infinity, minHeight: stripRowHeight, alignment: .leading)
            .padding(.horizontal, AP.Space.space16)
            .accessibilityIdentifier("camera.poseStrip")
        case .empty, .failed:
            HStack(spacing: AP.Space.space12) {
                APStateWordRow(
                    tone: strip == .failed ? .error : .empty,
                    word: strip == .failed ? "Couldn't load poses" : "No poses yet"
                )
                Spacer(minLength: 0)
                if strip == .failed {
                    Button("Try again", action: onRetryStrip)
                        .buttonStyle(APChipButtonStyle())
                        .accessibilityIdentifier("camera.poseStrip.retry")
                }
            }
            .padding(.horizontal, AP.Space.space16)
            .frame(maxWidth: .infinity, minHeight: stripRowHeight, alignment: .leading)
            .accessibilityIdentifier("camera.poseStrip")
        }
    }

    /// The strip's leading card opens the full picker (search + All/Saved scopes). It keeps the
    /// `camera.choosePose` handle the old top pill had, so the existing E2E path still reaches
    /// `posePicker.search` and `posePicker.grid`. It sits *first* so a full catalogue can never push the
    /// sheet's only entry off screen.
    private var browseAllCard: some View {
        Button(action: onBrowse) {
            VStack(spacing: AP.Space.space4) {
                Image(systemName: "magnifyingglass")
                    .font(AP.Font.heading)
                    .foregroundStyle(AP.Color.primaryText)
                    .frame(width: cardWidth, height: stripImageHeight)
                    .background(
                        RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                            .fill(AP.Color.controlFill)
                    )
                Text("Browse")
                    .font(AP.Font.caption)
                    .foregroundStyle(AP.Color.secondaryText)
                    .lineLimit(1)
                    .frame(width: cardWidth - AP.Space.space8, alignment: .leading)
            }
            .padding(AP.Space.space4)
        }
        .buttonStyle(CameraPressStyle(restingFill: AP.Color.controlFill))
        .accessibilityLabel("Browse all poses")
        .accessibilityIdentifier("camera.choosePose")
    }

    private func stripCard(_ pose: NativePose) -> some View {
        let isSelected = pose.id == selectedPoseID
        return Button {
            onSelectPose(pose)
        } label: {
            VStack(spacing: AP.Space.space4) {
                ZStack(alignment: .topTrailing) {
                    KFImage(pose.imageURL)
                        .placeholder { AP.Color.controlFill }
                        .onFailureView { AP.Color.controlFill }
                        .loadDiskFileSynchronously(false)
                        .contentConfigure { image, _ in
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                        .frame(width: cardWidth, height: stripImageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous))
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(AP.Font.caption.weight(.bold))
                            .foregroundStyle(AP.Color.onAccent)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(AP.Color.accent))
                            .padding(AP.Space.space4)
                            .accessibilityHidden(true)
                    }
                }
                Text(pose.name)
                    .font(AP.Font.caption)
                    .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.secondaryText)
                    .lineLimit(2)
                    .frame(width: cardWidth - AP.Space.space8, alignment: .leading)
            }
            .padding(AP.Space.space4)
        }
        .buttonStyle(CameraPressStyle(isSelected: isSelected, restingFill: AP.Color.controlFill))
        .accessibilityLabel("Use \(pose.name) pose")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("camera.poseStrip.card.\(pose.id)")
    }

    // MARK: Zoom

    /// The scale row: the zoom presets stay centred, the Poses control sits at its right end (owner
    /// feedback calls this row the scale bar). The Poses control is the only way back into the picker,
    /// so it is always present while the camera can pick a pose.
    private var scaleRow: some View {
        ZStack {
            zoomPill
            if showsPicker, CameraChromeLayout.showsStripToggle(showsPicker: showsPicker) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    stripToggle
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AP.Space.space16)
    }

    /// The zoom presets: compact (owner feedback), no container, the selection marked by its own small
    /// chip plus weight — and still a 44 pt target per preset.
    private var zoomPill: some View {
        HStack(spacing: AP.Space.space4) {
            ForEach(zoomPresets) { preset in
                let isActive = preset == activeZoomPreset
                Button {
                    onZoomPreset(preset)
                } label: {
                    Text(preset.rawValue)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? AP.Color.primaryText : AP.Color.secondaryText)
                        .frame(minWidth: AP.HitTarget.minimum)
                        .frame(height: 36)
                        .background(
                            Capsule().fill(isActive ? AP.Color.selectedBackground : .clear)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .frame(minHeight: AP.HitTarget.minimum)
                .disabled(!controlsEnabled)
                .opacity(controlsEnabled ? 1 : 0.45)
                .accessibilityLabel("Zoom \(preset.rawValue)")
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
                .accessibilityIdentifier(preset.accessibilityIdentifier)
            }
        }
        .accessibilityElement(children: .contain)
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

/// The camera tools popover's surface contract (owner feedback, build 18).
///
/// There is no title row and no Done action: every control applies and persists the moment it changes,
/// and the popover is dismissed by tapping outside or with VoiceOver's escape. The identifiers below are
/// the ones the rows expose, so "the Done handle is gone" is a unit-testable fact rather than a memory.
enum CameraToolsLayout {
    static let hasHeaderRow = false
    /// Retired with the Done button; no row may expose it again.
    static let retiredDoneIdentifier = "camera.tools.done"
    static let controlIdentifiers = [
        "camera.tools.flash",
        "camera.tools.grid",
        "camera.tools.mirror",
        "camera.tools.timer",
        "camera.tools.ratio",
        "camera.tools.poseGuide",
        "camera.tools.opacity",
        "camera.tools.scale",
        "camera.tools.lineColor.black",
        "camera.tools.lineColor.white",
    ]

    /// Every change lands on the model directly (no commit step), so a setting is persisted while the
    /// popover is still open.
    static func persistsImmediately(identifier: String) -> Bool {
        controlIdentifiers.contains(identifier)
    }
}

// MARK: - Camera tools (AP tokens, forced dark)

/// The camera's settings surface: an anchored popup under the tools control (no scrim, no handle, no
/// app-bar Close), `surface` fill, radius 24, E1 — the dark card edge is the elevation's `cardStroke`
/// hairline, never a hand-drawn border. Rows are `controlFill` pills with 44 pt targets and a pressed
/// fill step, and every status pairs a glyph with a word.
///
/// The popup hugs its content up to `max-height` with `overflow-y: auto`, so the content height is
/// measured once through a preference and the scroll view is bounded to it.
private struct CameraToolsPopup: View {
    let flashSetting: CameraFlashSetting
    let isGridVisible: Bool
    let controlsEnabled: Bool
    let hasPose: Bool
    let isPoseGuideVisible: Bool
    let guideFlipped: Bool
    let timerSetting: CameraTimerSetting
    let aspectRatio: CameraAspectRatio
    let guideOpacity: Double
    let guideScale: CGFloat
    let guideLineColor: GuideLineColor
    let popupWidth: CGFloat
    let popupMaxHeight: CGFloat
    let onFlashTap: () -> Void
    let onGridToggle: () -> Void
    let onPoseGuideVisibilityToggle: () -> Void
    let onMirrorToggle: () -> Void
    let onTimerChange: (CameraTimerSetting) -> Void
    let onAspectRatioChange: (CameraAspectRatio) -> Void
    let onGuideScaleChange: (CGFloat) -> Void
    let onGuideScaleReset: () -> Void
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
            RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous)
                .fill(AP.Color.surface)
        )
        .apElevation(.e1, cornerRadius: AP.Radius.radius24)
        .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous))
        .accessibilityElement(children: .contain)
        // VoiceOver's local Back (two-finger Z scrub) — the native equivalent of Escape.
        .accessibilityAction(.escape) { onDismiss() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: AP.Space.space8) {
            row(
                systemImage: flashSetting.symbolName,
                title: "Flash",
                value: flashSetting.toolsDisplayName,
                accessibilityLabel: "Flash \(flashSetting.toolsDisplayName), tap to change",
                identifier: "camera.tools.flash",
                action: onFlashTap
            )
            gridRow
            timerRow
            ratioRow

            if hasPose {
                Divider()
                    .overlay(AP.Color.separator)
                    .padding(.vertical, AP.Space.space4)

                Text("Pose guide")
                    .font(AP.Font.caption)
                    .foregroundStyle(AP.Color.secondaryText)
                    .accessibilityAddTraits(.isHeader)

                row(
                    systemImage: isPoseGuideVisible ? "eye" : "eye.slash",
                    title: "Pose guide",
                    value: isPoseGuideVisible ? "Shown" : "Hidden",
                    accessibilityLabel: isPoseGuideVisible ? "Hide pose guide" : "Show pose guide",
                    identifier: "camera.tools.poseGuide",
                    action: onPoseGuideVisibilityToggle
                )
                mirrorRow
                opacityRow
                guideScaleRow
                lineColorRow
            }
        }
        .padding(AP.Space.space12)
    }

    /// One settings row: glyph + word on `controlFill`, 44 pt tall, pressed fill step.
    private func row(
        systemImage: String?,
        title: String,
        value: String?,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AP.Space.space8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AP.Font.body)
                        .foregroundStyle(AP.Color.primaryText)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                Spacer(minLength: AP.Space.space8)
                if let value {
                    Text(value)
                        .font(AP.Font.body.weight(.semibold))
                        .foregroundStyle(AP.Color.accentText)
                }
            }
            .padding(.horizontal, AP.Space.space12)
            .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
        }
        .buttonStyle(CameraRowStyle())
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

    private var gridRow: some View {
        HStack(spacing: AP.Space.space8) {
            Image(systemName: "grid")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text("Grid")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
            Spacer(minLength: AP.Space.space8)
            gridSwitch
        }
        .padding(.horizontal, AP.Space.space12)
        .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel("Show camera grid")
        .accessibilityIdentifier("camera.tools.grid")
    }

    /// Switch: `accent` track when on, `controlFillPressed` when off, ink knob, 44 pt hit area.
    private var gridSwitch: some View {
        Button(action: onGridToggle) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isGridVisible ? AP.Color.accent : AP.Color.controlFillPressed)
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(AP.Color.onAccent)
                    .frame(width: 22, height: 22)
                    .padding(.leading, 3)
                    .offset(x: isGridVisible ? 20 : 0)
            }
            .animation(.easeOut(duration: 0.1), value: isGridVisible)
        }
        .buttonStyle(.plain)
        // The drawn switch is 48x28; the row's own minimum height does not enlarge the Button, so the
        // target is applied here, where the tap actually lands.
        .apMinimumHitTarget()
        .disabled(!controlsEnabled)
        .accessibilityLabel("Show camera grid")
        .accessibilityValue(isGridVisible ? "On" : "Off")
        .accessibilityIdentifier("camera.tools.grid")
        .accessibilityAddTraits(isGridVisible ? [.isSelected] : [])
    }

    /// Opacity: label + value on the tone's ink, slider tinted with the accent.
    /// Mirror: flips the pose reference (the guide), with a glyph and a word so the state is never
    /// carried by the switch's own position.
    private var mirrorRow: some View {
        HStack(spacing: AP.Space.space8) {
            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text("Mirror guide")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
            Spacer(minLength: AP.Space.space8)
            Text(guideFlipped ? "Mirrored" : "Normal")
                .font(AP.Font.body.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
            mirrorSwitch
        }
        .padding(.horizontal, AP.Space.space12)
        .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.tools.mirror")
    }

    private var mirrorSwitch: some View {
        Button(action: onMirrorToggle) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(guideFlipped ? AP.Color.accent : AP.Color.controlFillPressed)
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(AP.Color.onAccent)
                    .frame(width: 22, height: 22)
                    .padding(.leading, 3)
                    .offset(x: guideFlipped ? 20 : 0)
            }
            .animation(.easeOut(duration: 0.1), value: guideFlipped)
        }
        .buttonStyle(.plain)
        .apMinimumHitTarget()
        .disabled(!controlsEnabled)
        .accessibilityLabel("Mirror pose guide")
        .accessibilityValue(guideFlipped ? "Mirrored" : "Normal")
        .accessibilityIdentifier("camera.tools.mirror.switch")
        .accessibilityAddTraits(guideFlipped ? [.isSelected] : [])
    }

    /// Pose reference's size: value, slider and a Reset, so the gesture has a visible control.
    private var guideScaleRow: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            HStack(spacing: AP.Space.space8) {
                Text("Scale")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                Spacer(minLength: AP.Space.space8)
                Text(CameraGuideScale.label(guideScale))
                    .font(AP.Font.body.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
            }
            HStack(spacing: AP.Space.space8) {
                Slider(
                    value: Binding(get: { guideScale }, set: { onGuideScaleChange($0) }),
                    in: CameraGuideScale.range
                )
                .tint(AP.Color.accent)
                .disabled(!controlsEnabled)
                .accessibilityLabel("Pose guide scale \(CameraGuideScale.label(guideScale))")
                .accessibilityIdentifier("camera.tools.scale")

                Button("Reset", action: onGuideScaleReset)
                    .buttonStyle(.plain)
                    .font(AP.Font.supporting.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
                    .apMinimumHitTarget()
                    .disabled(!controlsEnabled)
                    .accessibilityIdentifier("camera.tools.scale.reset")
            }
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .opacity(controlsEnabled ? 1 : 0.45)
    }

    /// Ratio: the saved capture's aspect. The chosen option carries a check glyph and its word.
    private var ratioRow: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            HStack(spacing: AP.Space.space8) {
                Image(systemName: "rectangle.portrait")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text("Ratio")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                Spacer(minLength: AP.Space.space8)
                Text(aspectRatio.rawValue)
                    .font(AP.Font.body.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
            }
            HStack(spacing: AP.Space.space8) {
                ForEach(CameraAspectRatio.allCases) { ratio in
                    ratioChoice(ratio)
                }
            }
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityIdentifier("camera.tools.ratio")
    }

    private func ratioChoice(_ ratio: CameraAspectRatio) -> some View {
        let isSelected = aspectRatio == ratio
        return Button {
            onAspectRatioChange(ratio)
        } label: {
            HStack(spacing: AP.Space.space4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AP.Font.caption.weight(.bold))
                }
                Text(ratio.rawValue)
                    .font(AP.Font.supporting.weight(.semibold))
            }
            .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(CameraSelectStyle(isSelected: isSelected))
        .accessibilityLabel("Ratio \(ratio.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(ratio.accessibilityIdentifier)
    }

    /// Timer: Off / 3 s / 10 s, the chosen option with a check glyph and its word.
    private var timerRow: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            HStack(spacing: AP.Space.space8) {
                Image(systemName: "timer")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text("Timer")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                Spacer(minLength: AP.Space.space8)
                Text(timerSetting.rawValue)
                    .font(AP.Font.body.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
            }
            HStack(spacing: AP.Space.space8) {
                ForEach(CameraTimerSetting.allCases) { setting in
                    timerChoice(setting)
                }
            }
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityIdentifier("camera.tools.timer")
    }

    private func timerChoice(_ setting: CameraTimerSetting) -> some View {
        let isSelected = timerSetting == setting
        return Button {
            onTimerChange(setting)
        } label: {
            HStack(spacing: AP.Space.space4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AP.Font.caption.weight(.bold))
                }
                Text(setting.rawValue)
                    .font(AP.Font.supporting.weight(.semibold))
            }
            .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(CameraSelectStyle(isSelected: isSelected))
        .accessibilityLabel("Timer \(setting.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(setting.accessibilityIdentifier)
    }

    private var opacityRow: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            HStack(spacing: AP.Space.space8) {
                Text("Opacity")
                    .font(AP.Font.body)
                    .foregroundStyle(AP.Color.primaryText)
                Spacer(minLength: AP.Space.space8)
                Text("\(Int((guideOpacity * 100).rounded()))%")
                    .font(AP.Font.body.weight(.semibold))
                    .foregroundStyle(AP.Color.accentText)
            }
            Slider(value: Binding(
                get: { guideOpacity },
                set: { onGuideOpacityChange($0) }
            ), in: 0.1...1)
            .tint(AP.Color.accent)
            .disabled(!controlsEnabled)
            .accessibilityLabel("Pose guide opacity \(Int((guideOpacity * 100).rounded())) percent")
            .accessibilityIdentifier("camera.tools.opacity")
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
    }

    /// Line colour: the selected choice carries a check glyph **and** its word, never colour alone.
    private var lineColorRow: some View {
        VStack(alignment: .leading, spacing: AP.Space.space4) {
            Text("Line colour")
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
            HStack(spacing: AP.Space.space8) {
                choiceButton(.black, identifier: "camera.tools.lineColor.black")
                choiceButton(.white, identifier: "camera.tools.lineColor.white")
            }
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
    }

    private func choiceButton(_ color: GuideLineColor, identifier: String) -> some View {
        let isSelected = guideLineColor == color
        return Button {
            onGuideLineColorChange(color)
        } label: {
            HStack(spacing: AP.Space.space4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AP.Font.caption.weight(.bold))
                }
                Text(color.label)
                    .font(AP.Font.supporting.weight(.semibold))
            }
            .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(CameraSelectStyle(isSelected: isSelected))
        .accessibilityLabel("\(color.label) pose line colour")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Selected/unselected fill for an option chip: `selectedBackground` when chosen, else transparent
/// (it sits on the row's `controlFill`).
private struct CameraSelectStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius8, style: .continuous)
                    .fill(isSelected ? AP.Color.selectedBackground
                          : (configuration.isPressed ? AP.Color.controlFillPressed : Color.clear))
            )
            .apMinimumHitTarget()
    }
}

/// `controlFill` row with a pressed fill step.
private struct CameraRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(configuration.isPressed ? AP.Color.controlFillPressed : AP.Color.controlFill)
            )
            .apMinimumHitTarget()
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

    /// The rows this scope draws. Both scopes filter by the same search text through the **same**
    /// helpers the Poses screens use: the catalogue's own local filter for All, and the shared saved
    /// name filter for Saved (`PoseAdapterMerge.filterSavedLocally`), so the two cannot drift.
    func rows(catalogue: [NativePose], saved: [NativePose], query: String) -> [NativePose] {
        switch self {
        case .all:
            let term = query.trimmingCharacters(in: .whitespaces).lowercased()
            guard !term.isEmpty else { return catalogue }
            return catalogue.filter { $0.name.lowercased().contains(term) }
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
    /// Which collection the sheet lists (`05-camera-picker-loaded`: All / Saved). Saved is
    /// account-scoped and loaded by `CameraSavedPosesModel`, never by this model.
    @Published var scope: CameraPickerScope = .all
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

    /// Drops the request behind the catalogue: the collapsed camera's dismissal retries on reopen
    /// (R6), so a late answer must not paint the sheet again. Bumping the generation is what makes
    /// the abandoned completion inert.
    private func abandonInFlightLoad() {
        inFlightLoad?.cancel()
        inFlightLoad = nil
        loadGeneration &+= 1
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

    /// The scope chip. One control switches the collection; leaving Saved drops the query so the two
    /// lists cannot filter each other's text.
    func selectScope(_ scope: CameraPickerScope) {
        guard scope != self.scope else { return }
        self.scope = scope
        query = ""
    }

    /// `pose-picker-search__clear`: resets to the full grid without refetching.
    func clearSearch() {
        query = ""
    }

    /// The sheet closed while the picker strip stays on screen (F12 expanded). R7 still applies —
    /// monitoring stops and the offline reading is cleared — but the rows stay: the strip is still
    /// drawing them, and reopening retries any load that is not `.loaded`.
    func dismissKeepingCatalogue() {
        stopMonitoring()
        query = ""
    }
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

    /// Rows the grid draws for the current scope. The rule owns the name filter for **both** lists, so
    /// the catalogue is passed unfiltered and cannot be filtered twice.
    private var visiblePoses: [NativePose] {
        model.scope.rows(
            catalogue: model.state.rows,
            saved: savedPoses.rows,
            query: model.query
        )
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

    /// The sheet's scrim (`scrim` token: 64% black in the camera's dark appearance).
    private var backdrop: some View {
        AP.Color.scrim
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
            .accessibilityHidden(true)
    }

    private func panel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            handle
            header
            scopeChips
            searchField
            scrollContent
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
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 18)))
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
                .accessibilityIdentifier("posePicker.close")
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
                .accessibilityIdentifier("posePicker.search")

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
                .accessibilityIdentifier("posePicker.searchClear")
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
            savedStateSurface
        case .all:
            if let panel = CameraStatePanel.picker(
                tone: model.stateTone,
                isNoMatch: model.emptyIsNoMatch,
                term: model.query.trimmingCharacters(in: .whitespaces),
                isOffline: model.isOffline
            ) {
                CameraPickerStatePanel(panel: panel) {
                    Task { await model.load() }
                }
                .accessibilityIdentifier("posePicker.state")
            }
        }
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
            .accessibilityIdentifier("posePicker.grid")
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

private struct StickFigureView: View {
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
