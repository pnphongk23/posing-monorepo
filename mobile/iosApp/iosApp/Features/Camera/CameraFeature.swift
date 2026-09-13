import AVFoundation
import Kingfisher
import SwiftUI
import UIKit

// MARK: - View model (business logic unchanged, capture/export/permission paths untouched)

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var guideOpacity = 0.55
    @Published var guideFlipped = false
    @Published var isGridVisible = false
    @Published var flashSetting: CameraFlashSetting = .off
    @Published var showCameraToolsSheet = false
    @Published var statusMessage: String?
    /// URL of the just-captured photo. The screen loads it through Kingfisher instead of decoding a
    /// full-resolution image on the main thread before it can present.
    @Published var capturedPreviewURL: URL?
    @Published var showCapturedSheet = false
    @Published var photosExportMessage: String?
    @Published var zoomLevel: CameraZoomLevel = .one
    /// URL of the newest capture, drawn as a 48pt thumbnail in the shutter rail.
    @Published private(set) var latestThumbnailURL: URL?

    var cameraControlsEnabled: Bool {
        coordinator.state.permission == .authorized
            && !coordinator.state.isCaptureInFlight
    }

    let camera: NativeCameraController
    let coordinator: CameraCoordinator
    let imageStorage: CaptureImageStorage
    private var timeoutTask: Task<Void, Never>?

    init(
        guide: NativePose? = nil,
        camera: NativeCameraController = NativeCameraController(),
        photoRepository: PhotoRepository? = nil,
        photoMetadata: CapturePhotoMetadata? = nil
    ) {
        self.camera = camera
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
    }

    func onAppear() async {
        let start = Date()
        coordinator.onLaunch()
        if coordinator.state.permission == .authorized {
            // `AVCaptureSession.startRunning()` is a blocking, hardware-bound call: it cannot be
            // moved off the main thread from here (the controller is `@MainActor`), so the log below
            // separates how much of "camera is slow" is the session and how much is app work.
            try? await camera.start()
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
        camera.stop()
    }

    func requestPermission() {
        camera.requestPermission { [weak self] result in
            Task { @MainActor in
                self?.coordinator.onPermissionResult(result)
                if result == .authorized {
                    try? await self?.camera.start()
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

    func matchingFeedbackLabel(for guide: NativePose?) -> String? {
        guard let guide else { return nil }
        return "Matching: \(guide.name)"
    }

    func openCameraTools() {
        guard cameraControlsEnabled else { return }
        showCameraToolsSheet = true
    }

    func closeCameraTools() {
        showCameraToolsSheet = false
    }

    func cycleFlash() {
        guard cameraControlsEnabled else { return }
        flashSetting = flashSetting.next()
        camera.setFlashMode(flashSetting)
    }

    func toggleGrid() {
        guard cameraControlsEnabled else { return }
        isGridVisible.toggle()
    }

    func cycleZoom() {
        guard cameraControlsEnabled else { return }
        applyZoom(zoomLevel.next())
    }

    func applyZoom(_ level: CameraZoomLevel) {
        zoomLevel = level
        camera.setZoomFactor(level.factor)
    }

    func dismissCapture() {
        coordinator.dismissResult()
        showCapturedSheet = false
        capturedPreviewURL = nil
        statusMessage = coordinator.state.statusText()
    }

    func exportToPhotos() async {
        guard case .captureSucceeded(_, let photo) = coordinator.state.phase,
              let path = imageStorage.fullPath(for: photo.imagePath) else {
            photosExportMessage = PhotosExporter.confirmation(saved: false)
            return
        }
        let saved = await PhotosExporter.saveImage(at: URL(fileURLWithPath: path))
        photosExportMessage = PhotosExporter.confirmation(saved: saved)
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

    private func observeCaptureCompletion() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            while coordinator.state.isCaptureInFlight {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            timeoutTask?.cancel()
            statusMessage = coordinator.state.statusText()
            reloadThumbnail()
            if case .captureSucceeded = coordinator.state.phase,
               let path = coordinator.state.thumbnailPathValue(),
               let full = imageStorage.fullPath(for: path) {
                capturedPreviewURL = URL(fileURLWithPath: full)
                showCapturedSheet = true
            }
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

// MARK: - Camera screen

struct CameraScreen: View {
    @Binding var guide: NativePose?
    let poseService: any PoseServing
    /// Dismisses the camera back to the Poses tab. Owned by `AppFeatureRoot`.
    let onClose: () -> Void
    /// Opens the Gallery tab from the shutter-rail thumbnail.
    let onOpenGallery: () -> Void
    @StateObject private var model: CameraViewModel
    @Environment(\.scenePhase) private var scenePhase
    /// The guide picker is a cream screen, so the light status bar only applies while the
    /// camera viewport is the top-most screen.
    @State private var isGuidePickerOnTop = false

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
    }

    /// Legacy UIKit host and previews without an injected pose service.
    init() {
        self.init(guide: .constant(nil), poseService: PreviewPoseService())
    }

    private var isAuthorized: Bool { model.coordinator.state.permission == .authorized }

    var body: some View {
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
        .ignoresSafeArea(.container, edges: .top)
        .neoHiddenNavigationBar()
        .preferredColorScheme(isGuidePickerOnTop ? .light : .dark)
        .task { await model.onAppear() }
        .onDisappear { model.onDisappear() }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: model.coordinator.onForeground()
            case .background: model.coordinator.onBackground()
            default: break
            }
        }
        .onChange(of: model.cameraControlsEnabled) { enabled in
            if !enabled { model.closeCameraTools() }
        }
        .sheet(isPresented: $model.showCameraToolsSheet) {
            CameraToolsSheet(
                flashSetting: model.flashSetting,
                isGridVisible: model.isGridVisible,
                controlsEnabled: model.cameraControlsEnabled,
                guideName: guide?.name,
                guideOpacity: $model.guideOpacity,
                guideFlipped: $model.guideFlipped,
                onFlashTap: { model.cycleFlash() },
                onGridToggle: { model.toggleGrid() },
                onClose: { model.closeCameraTools() }
            )
            .cameraToolsSheetPresentation(height: guide == nil ? 268 : 396)
        }
        .sheet(isPresented: $model.showCapturedSheet) {
            if let url = model.capturedPreviewURL {
                CapturedPhotoScreen(
                    imageURL: url,
                    statusMessage: model.statusMessage,
                    photosExportMessage: model.photosExportMessage,
                    onSaveToPhotos: { await model.exportToPhotos() },
                    onDone: { model.dismissCapture() }
                )
            }
        }
    }

    // MARK: Viewport — full-bleed `.nb-camera-viewport--immersive`

    private var viewport: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let framing = CGRect(
                x: size.width * CameraProto.framingHorizontalInset,
                y: size.height * CameraProto.framingTopInset,
                width: size.width * (1 - CameraProto.framingHorizontalInset * 2),
                height: size.height * (1 - CameraProto.framingTopInset - CameraProto.framingBottomInset)
            )
            ZStack {
                CameraProto.dark

                if isAuthorized {
                    CameraPreview(session: model.camera.session)
                }

                verticalScrims

                if let guide {
                    guideOverlay(for: guide)
                        .frame(width: framing.width, height: framing.height)
                        .position(x: framing.midX, y: framing.midY)
                }

                if model.isGridVisible {
                    CameraFramingGrid()
                }

                CameraFramingGuide()
                    .frame(width: framing.width, height: framing.height)
                    .position(x: framing.midX, y: framing.midY)

                if let label = model.matchingFeedbackLabel(for: guide) {
                    Text(label)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AIPoseColor.foreground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AIPoseColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: CameraProto.radiusMedium))
                        .overlay(RoundedRectangle(cornerRadius: CameraProto.radiusMedium)
                            .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth))
                        .shadow(color: AIPoseColor.border, radius: 0,
                                x: CameraProto.shadowSmall, y: CameraProto.shadowSmall)
                        .position(x: size.width / 2, y: CameraProto.topControlsTop + CameraProto.touch + 22)
                        .accessibilityLabel(label)
                }

                if let status = model.statusMessage, !model.showCapturedSheet {
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

    private var topControls: some View {
        HStack(spacing: 0) {
            CameraActionControl(
                systemImage: "xmark",
                accessibilityLabel: "Close camera",
                action: onClose
            )
            Spacer(minLength: 0)
            CameraActionControl(
                systemImage: "ellipsis",
                rotatesIcon: true,
                accessibilityLabel: "Camera tools",
                action: { model.openCameraTools() }
            )
        }
    }

    private var viewportFooter: some View {
        ZStack {
            CameraZoomPill(level: model.zoomLevel) { model.cycleZoom() }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                NavigationLink {
                    GuidePickerScreen(poseService: poseService) { pose in
                        guide = pose
                    }
                    .onAppear { isGuidePickerOnTop = true }
                    .onDisappear { isGuidePickerOnTop = false }
                } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AIPoseColor.foreground)
                        .frame(width: CameraProto.surface, height: CameraProto.surface)
                }
                .buttonStyle(NeoSurfaceStyle(fill: AIPoseColor.accentBlue))
                .frame(width: CameraProto.touch, height: CameraProto.touch, alignment: .bottom)
                .contentShape(Rectangle())
                .accessibilityLabel("Choose a pose guide")
            }
        }
    }

    @ViewBuilder
    private func guideOverlay(for guide: NativePose) -> some View {
        Group {
            if let url = guide.imageURL {
                // The guide image covers most of the viewport, so it is decoded at screen size
                // instead of at whatever the source asset happens to be.
                KFImage(url)
                    .setProcessor(AppImage.downsample(points: FullScreenImageTarget.drawSize, contentMode: .fit))
                    .placeholder { guideFallback(for: guide) }
                    .onFailureView { guideFallback(for: guide) }
                    .loadDiskFileSynchronously(false)
                    .contentConfigure { image, _ in
                        image.resizable().scaledToFit()
                    }
            } else {
                guideFallback(for: guide)
            }
        }
        .opacity(model.guideOpacity)
        .scaleEffect(x: model.guideFlipped ? -1 : 1, y: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Same stand-in the `AsyncImage` placeholder used before the guide asset loads.
    private func guideFallback(for guide: NativePose) -> StickFigureView {
        StickFigureView(kind: .resolve(name: guide.name, category: guide.category, index: 0))
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

private extension View {
    @ViewBuilder
    func cameraToolsSheetPresentation(height: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            presentationDetents([.height(height)])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}

private extension CameraFlashSetting {
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .auto: return "Auto"
        }
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
    static let shadow: CGFloat = 3                    // --nb-shadow-offset
    static let shadowSmall: CGFloat = 1.5             // --nb-shadow-offset-small
    static let shadowLarge: CGFloat = 5               // --nb-shadow-offset-large
    static let touch: CGFloat = 44                    // --nb-touch-min
    static let surface: CGFloat = 32                  // .nb-btn__compact-surface
    static let spaceSM: CGFloat = 8
    static let spaceMD: CGFloat = 16
    static let spaceLG: CGFloat = 24
    static let spaceXL: CGFloat = 32

    // `.nb-camera-viewport__top-controls`
    static let topControlsTop: CGFloat = 62
    static let controlInset: CGFloat = 16

    // `.nb-camera-framing-guide`
    static let framingTopInset: CGFloat = 0.25
    static let framingHorizontalInset: CGFloat = 0.18
    static let framingBottomInset: CGFloat = 0.18
    static let framingCorner: CGFloat = 28

    // `.nb-shutter-bar--redesign`
    static let railHeight: CGFloat = 124
    static let railInset: CGFloat = 24
    static let railControl: CGFloat = 48
    static let shutterSize: CGFloat = 72
    static let zoomToggle: CGFloat = 36

    // `.nb-camera-status`
    static let statusBottomInset: CGFloat = 72
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

/// `.nb-camera-framing-guide` — four 28x28 L corners, 2pt translucent white.
private struct CameraFramingGuide: View {
    var body: some View {
        ZStack {
            corner(.topLeading)
            corner(.topTrailing)
            corner(.bottomLeading)
            corner(.bottomTrailing)
        }
        .accessibilityHidden(true)
    }

    private func corner(_ corner: FramingCorner) -> some View {
        FramingCornerShape(corner: corner)
            .fill(Color.white.opacity(0.9))
            .frame(width: CameraProto.framingCorner, height: CameraProto.framingCorner)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
    }
}

enum FramingCorner {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

struct FramingCornerShape: Shape {
    let corner: FramingCorner

    func path(in rect: CGRect) -> Path {
        let t: CGFloat = CameraProto.borderWidth
        var path = Path()
        switch corner {
        case .topLeading:
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: t))
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: t, height: rect.height))
        case .topTrailing:
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: t))
            path.addRect(CGRect(x: rect.maxX - t, y: rect.minY, width: t, height: rect.height))
        case .bottomLeading:
            path.addRect(CGRect(x: rect.minX, y: rect.maxY - t, width: rect.width, height: t))
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: t, height: rect.height))
        case .bottomTrailing:
            path.addRect(CGRect(x: rect.minX, y: rect.maxY - t, width: rect.width, height: t))
            path.addRect(CGRect(x: rect.maxX - t, y: rect.minY, width: t, height: rect.height))
        }
        return path
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
        .accessibilityLabel("Switch camera")
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

// MARK: - Camera tools sheet (`.nb-camera-settings-panel`)

private struct CameraToolsSheet: View {
    let flashSetting: CameraFlashSetting
    let isGridVisible: Bool
    let controlsEnabled: Bool
    let guideName: String?
    @Binding var guideOpacity: Double
    @Binding var guideFlipped: Bool
    let onFlashTap: () -> Void
    let onGridToggle: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            VStack(spacing: CameraProto.spaceSM) {
                row(
                    systemImage: flashSetting.symbolName,
                    title: "Flash",
                    value: flashSetting.displayName,
                    accessibilityLabel: "Flash \(flashSetting.displayName), tap to change",
                    action: onFlashTap
                )
                gridRow
                if let guideName {
                    opacityRow(guideName: guideName)
                    flipRow
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CameraProto.spaceMD)
        .padding(.top, 10)
        .padding(.bottom, CameraProto.spaceXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AIPoseColor.background.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var handle: some View {
        Capsule()
            .fill(AIPoseColor.foreground)
            .frame(width: 42, height: 4)
            .padding(.bottom, CameraProto.spaceMD)
    }

    private var header: some View {
        HStack(spacing: CameraProto.spaceMD) {
            Text("Camera tools")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            CameraActionControl(
                systemImage: "xmark",
                accessibilityLabel: "Close camera tools",
                action: onClose
            )
        }
        .padding(.bottom, CameraProto.spaceMD)
    }

    private func row(
        systemImage: String,
        title: String,
        value: String?,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: CameraProto.spaceSM) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 18, height: 18)
                Text(title)
                Spacer(minLength: 0)
                if let value {
                    Text(value).foregroundStyle(AIPoseColor.accentYellow)
                }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AIPoseColor.foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
        .buttonStyle(NeoSurfaceStyle(fill: AIPoseColor.surface))
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel(accessibilityLabel)
    }

    private var gridRow: some View {
        HStack(spacing: CameraProto.spaceSM) {
            Image(systemName: "grid")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 18, height: 18)
            Text("Grid")
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { isGridVisible }, set: { _ in onGridToggle() }))
                .labelsHidden()
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(AIPoseColor.foreground)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(AIPoseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: CameraProto.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: CameraProto.radiusMedium)
            .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth))
        .shadow(color: AIPoseColor.border, radius: 0,
                x: CameraProto.shadowSmall, y: CameraProto.shadowSmall)
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel("Show camera grid")
    }

    private func opacityRow(guideName: String) -> some View {
        HStack(spacing: CameraProto.spaceSM) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 18, height: 18)
            Text("Guide")
            Slider(value: $guideOpacity, in: 0.1...1)
                .accessibilityLabel("Guide opacity")
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(AIPoseColor.foreground)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(AIPoseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: CameraProto.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: CameraProto.radiusMedium)
            .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth))
        .shadow(color: AIPoseColor.border, radius: 0,
                x: CameraProto.shadowSmall, y: CameraProto.shadowSmall)
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel("Guide opacity for \(guideName)")
    }

    private var flipRow: some View {
        Button {
            guideFlipped.toggle()
        } label: {
            HStack(spacing: CameraProto.spaceSM) {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 18, height: 18)
                Text("Flip guide")
                Spacer(minLength: 0)
                if guideFlipped {
                    Text("On").foregroundStyle(AIPoseColor.accentYellow)
                }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AIPoseColor.foreground)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
        .buttonStyle(NeoSurfaceStyle(fill: AIPoseColor.surface))
        .disabled(!controlsEnabled)
        .opacity(controlsEnabled ? 1 : 0.45)
        .accessibilityLabel("Flip guide")
    }
}

// MARK: - Captured result

private struct CapturedPhotoScreen: View {
    let imageURL: URL
    let statusMessage: String?
    let photosExportMessage: String?
    let onSaveToPhotos: () async -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                // The preview is shown full screen, so the decode is bounded by the screen, not by
                // the 4032px the capture was taken at.
                KFImage(imageURL)
                    .setProcessor(AppImage.downsample(points: FullScreenImageTarget.drawSize, contentMode: .fit))
                    .placeholder { Color.clear }
                    .onFailureView { Color.clear }
                    .loadDiskFileSynchronously(false)
                    .contentConfigure { image, _ in
                        image.resizable().scaledToFit()
                    }
                if let statusMessage {
                    Text(statusMessage).font(.subheadline.weight(.semibold))
                }
                if let photosExportMessage {
                    Text(photosExportMessage).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Save to Photos") {
                    Task { await onSaveToPhotos() }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Captured")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - Guide picker

@MainActor
final class GuidePickerViewModel: ObservableObject {
    @Published var state: Loadable<[NativePose]> = .idle
    private let service: any PoseServing

    init(service: any PoseServing) { self.service = service }

    func load() async {
        state = .loading
        do {
            let poses = try await service.poses(query: nil)
            state = poses.isEmpty ? .empty : .loaded(poses)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct GuidePickerScreen: View {
    @StateObject private var model: GuidePickerViewModel
    let onSelect: (NativePose) -> Void
    @Environment(\.dismiss) private var dismiss

    init(poseService: any PoseServing, onSelect: @escaping (NativePose) -> Void) {
        _model = StateObject(wrappedValue: GuidePickerViewModel(service: poseService))
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, CameraProto.spaceMD)
                .padding(.top, CameraProto.spaceMD)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AIPoseColor.background.ignoresSafeArea())
        .neoHiddenNavigationBar()
        .preferredColorScheme(.light)
        .task { if case .idle = model.state { await model.load() } }
    }

    /// `.nb-camera-guide-header` — 44pt row, 8pt gap, 16pt bottom margin.
    private var header: some View {
        HStack(spacing: CameraProto.spaceSM) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AIPoseColor.foreground)
                    .frame(width: CameraProto.touch, height: CameraProto.touch)
            }
            .buttonStyle(NeoSurfaceStyle(fill: AIPoseColor.surface, shadowOffset: CameraProto.shadow))
            .accessibilityLabel("Back")

            Text("Choose a guide")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(minHeight: CameraProto.touch)
        .padding(.bottom, CameraProto.spaceMD)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading poses…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            FeatureStateView(icon: "figure.stand", title: "No poses", message: "The pose catalog is empty.")
        case .failed(let message):
            FeatureStateView(icon: "wifi.exclamationmark", title: "Couldn't load poses", message: message) {
                Task { await model.load() }
            }
        case .loaded(let poses):
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: CameraProto.spaceMD),
                        GridItem(.flexible(), spacing: CameraProto.spaceMD),
                    ],
                    spacing: CameraProto.spaceMD
                ) {
                    ForEach(Array(poses.enumerated()), id: \.element.id) { index, pose in
                        Button {
                            onSelect(pose)
                            dismiss()
                        } label: {
                            GuidePickerCardView(pose: pose, index: index)
                        }
                        .buttonStyle(GuideCardPressStyle())
                        .accessibilityLabel("Use \(pose.name) as guide")
                    }
                }
                .padding(.horizontal, CameraProto.spaceMD)
                .padding(.bottom, CameraProto.spaceXL)
            }
        }
    }
}

/// `.nb-camera-guide-card` — flat surface (no shadow), 1:1, 78% stick figure, 14pt bold name.
private struct GuidePickerCardView: View {
    let pose: NativePose
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: CameraProto.spaceSM) {
            ZStack {
                RoundedRectangle(cornerRadius: CameraProto.radiusLarge)
                    .fill(GuideCardPalette.fill(at: index))
                RoundedRectangle(cornerRadius: CameraProto.radiusLarge)
                    .stroke(AIPoseColor.border, lineWidth: CameraProto.borderWidth)
                StickFigureView(kind: .resolve(name: pose.name, category: pose.category, index: index))
                    .padding(CameraProto.spaceLG)
            }
            .aspectRatio(1, contentMode: .fit)

            Text(pose.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AIPoseColor.foreground)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

/// `.nb-camera-guide-card:active` — the flat surface just translates 1.5pt (no shadow to drop).
private struct GuideCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? CameraProto.shadowSmall : 0,
                    y: configuration.isPressed ? CameraProto.shadowSmall : 0)
    }
}

/// Surfaces cycle `yellow → pink → blue → green` by card index.
enum GuideCardPalette {
    static let fills: [Color] = [
        AIPoseColor.accentYellow,
        AIPoseColor.primary,
        AIPoseColor.accentBlue,
        AIPoseColor.success,
    ]

    static func fill(at index: Int) -> Color {
        guard !fills.isEmpty else { return AIPoseColor.accentYellow }
        return fills[((index % fills.count) + fills.count) % fills.count]
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

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.78
            ZStack {
                StickFigureShape(kind: kind)
                    .stroke(
                        AIPoseColor.border,
                        style: StrokeStyle(lineWidth: 2 * side / 24, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: side, height: side)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}
