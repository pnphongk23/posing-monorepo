import Kingfisher
import SwiftUI
import UIKit
import XCTest
@testable import iosApp

@MainActor
final class CameraFeatureTests: XCTestCase {
    func testCameraControlsEnabledWhenAuthorizedAndIdle() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        XCTAssertTrue(model.cameraControlsEnabled)
    }

    func testCameraControlsDisabledWhenPermissionDenied() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        XCTAssertFalse(model.cameraControlsEnabled)
    }

    func testCameraControlsDisabledDuringCapture() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        XCTAssertTrue(model.coordinator.onCaptureRequested())
        XCTAssertFalse(model.cameraControlsEnabled)
    }

    func testOpenCameraToolsRequiresEnabledControls() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        model.openCameraTools()
        XCTAssertFalse(model.showCameraTools)

        model.coordinator.onPermissionResult(.authorized)
        model.openCameraTools()
        XCTAssertTrue(model.showCameraTools)
    }

    func testCloseCameraToolsClearsPopup() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.openCameraTools()
        model.closeCameraTools()
        XCTAssertFalse(model.showCameraTools)
    }

    func testOpenPosePickerRequiresEnabledControls() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        model.openPosePicker()
        XCTAssertFalse(model.showPosePicker)

        model.coordinator.onPermissionResult(.authorized)
        model.openPosePicker()
        XCTAssertTrue(model.showPosePicker)
    }

    func testClosePosePickerClearsSheetFlag() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.openPosePicker()
        model.closePosePicker()
        XCTAssertFalse(model.showPosePicker)
    }

    func testCycleFlashIgnoredWhenControlsDisabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        let initial = model.flashSetting
        model.cycleFlash()
        XCTAssertEqual(model.flashSetting, initial)
    }

    /// `toggle.js` / AC4: the Camera Tools row rotates `Off → Auto → On → Off`. The entry point is
    /// the prototype's shipped default `Auto` (`camera-live.html:87`
    /// `<span id="flash-value">Auto</span>`), so the ring is entered at `Auto`: Auto → On → Off → Auto.
    /// Traversing the full ring still proves the `Off → Auto → On → Off` order.
    func testCycleFlashFollowsPrototypeOffAutoOnOrder() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        XCTAssertEqual(model.flashSetting, .auto)
        model.cycleFlash()
        XCTAssertEqual(model.flashSetting, .on)
        model.cycleFlash()
        XCTAssertEqual(model.flashSetting, .off)
        model.cycleFlash()
        XCTAssertEqual(model.flashSetting, .auto)
    }

    // MARK: - Capture gate (`FEAT-011` M1)

    /// The ordering requirement: the entitlement gate sits *before* camera readiness. With the paywall
    /// on and no entitlement, a press must reach the paywall even though this camera cannot capture at
    /// all (`captureEnabled == false`), so the press can never be answered by the readiness /
    /// `captureError` path first — which is also what makes the flow verifiable on a simulator.
    func testShutterOpensPaywallBeforeCameraReadiness() {
        let gate = StubPremiumGate(.paywall(signIn: false))
        var prompts: [Bool] = []
        let model = CameraViewModel(premiumGate: gate, onPremiumRequired: { prompts.append($0) })
        model.coordinator.onPermissionResult(.denied)
        XCTAssertFalse(model.coordinator.state.captureEnabled)

        model.capture()

        XCTAssertEqual(prompts, [false], "exactly one paywall request")
        XCTAssertEqual(gate.cameraReadyInputs, [false], "the gate sees the real readiness, it just decides first")
        XCTAssertEqual(model.coordinator.state.phase, .permissionRequired, "the capture path was never entered")
        XCTAssertNil(model.coordinator.state.lastFailure, "so no captureError was produced")
        XCTAssertFalse(model.coordinator.state.isCaptureInFlight)
    }

    /// M2: a signed-out press opens the paywall in its sign-in state.
    func testShutterAsksForSignInWhenTheUserIsSignedOut() {
        let gate = StubPremiumGate(.paywall(signIn: true))
        var prompts: [Bool] = []
        let model = CameraViewModel(premiumGate: gate, onPremiumRequired: { prompts.append($0) })
        model.coordinator.onPermissionResult(.authorized)

        model.capture()

        XCTAssertEqual(prompts, [true])
        XCTAssertFalse(model.coordinator.state.isCaptureInFlight)
    }

    func testShutterCapturesWhenTheGateAllowsIt() {
        let gate = StubPremiumGate(.capture)
        var prompts = 0
        let model = CameraViewModel(premiumGate: gate, onPremiumRequired: { _ in prompts += 1 })
        model.coordinator.onPermissionResult(.authorized)

        model.capture()

        XCTAssertTrue(model.coordinator.state.isCaptureInFlight)
        XCTAssertEqual(prompts, 0)
    }

    /// Allowed but not ready keeps today's behaviour: nothing happens, and nothing is presented.
    func testShutterWithAnAllowedButUnreadyCameraDoesNothing() {
        let gate = StubPremiumGate(.unchanged)
        var prompts = 0
        let model = CameraViewModel(premiumGate: gate, onPremiumRequired: { _ in prompts += 1 })
        model.coordinator.onPermissionResult(.denied)

        model.capture()

        XCTAssertEqual(prompts, 0)
        XCTAssertFalse(model.coordinator.state.isCaptureInFlight)
        XCTAssertEqual(model.coordinator.state.phase, .permissionRequired)
    }

    func testToggleGridIgnoredWhenControlsDisabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        XCTAssertFalse(model.isGridVisible)
        model.toggleGrid()
        XCTAssertFalse(model.isGridVisible)
    }

    func testToggleGridWhenEnabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.toggleGrid()
        XCTAssertTrue(model.isGridVisible)
    }

    func testTogglePoseGuideVisibilityIgnoredWhenControlsDisabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        model.togglePoseGuideVisibility()
        XCTAssertTrue(model.isPoseGuideVisible)
    }

    func testTogglePoseGuideVisibilityWhenEnabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.togglePoseGuideVisibility()
        XCTAssertFalse(model.isPoseGuideVisible)
    }

    func testGuideOpacityDefaultMatchesPrototypeFiftyPercent() {
        let model = CameraViewModel()
        XCTAssertEqual(model.guideOpacity, 0.5, accuracy: 0.001)
    }

    func testSetGuideOpacityIgnoredWhenControlsDisabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        model.setGuideOpacity(0.8)
        XCTAssertEqual(model.guideOpacity, 0.5, accuracy: 0.001)
    }

    func testSetGuideOpacityWhenEnabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.setGuideOpacity(0.8)
        XCTAssertEqual(model.guideOpacity, 0.8, accuracy: 0.001)
    }

    func testSetGuideLineColorIgnoredWhenControlsDisabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        model.setGuideLineColor(.white)
        XCTAssertEqual(model.guideLineColor, .black)
    }

    func testSetGuideLineColorWhenEnabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.setGuideLineColor(.white)
        XCTAssertEqual(model.guideLineColor, .white)
    }

    // MARK: Persisted defaults (FEAT-012)

    /// The defaults exist twice: as the published initial values and as the fallback inside
    /// `CameraSettings` for a missing or corrupt row. A relaunch with nothing stored must look
    /// exactly like a first launch, so both spellings have to agree.
    func testPublishedDefaultsMatchThePersistedDefaults() {
        let model = CameraViewModel()
        let defaults = CameraSettings()

        XCTAssertEqual(model.guideOpacity, defaults.guideOpacity, accuracy: 0.001)
        XCTAssertEqual(model.guideFlipped, defaults.guideFlipped)
        XCTAssertEqual(model.isGridVisible, defaults.isGridVisible)
        XCTAssertEqual(model.flashSetting, defaults.flash)
        XCTAssertEqual(model.isPoseGuideVisible, defaults.isPoseGuideVisible)
        XCTAssertEqual(model.guideLineColor, defaults.lineColor)
        XCTAssertEqual(model.guideTransform, defaults.guideTransform)
        XCTAssertEqual(model.zoomLevel, defaults.zoom)
    }

    // MARK: Pose reference placement (pinch / twist / drag)

    func testGuideTransformStartsAtIdentity() {
        let model = CameraViewModel()
        XCTAssertEqual(model.guideTransform, GuideTransform())
    }

    func testCommitGuideGestureAccumulatesAcrossGestures() {
        let model = CameraViewModel()
        model.commitGuideGesture(.init(scale: 1.5, rotation: .degrees(10), translation: CGSize(width: 20, height: -5)))
        model.commitGuideGesture(.init(scale: 2, rotation: .degrees(15), translation: CGSize(width: 5, height: 5)))

        XCTAssertEqual(model.guideTransform.scale, 3, accuracy: 0.001)
        XCTAssertEqual(model.guideTransform.rotation.degrees, 25, accuracy: 0.001)
        XCTAssertEqual(model.guideTransform.offset, CGSize(width: 25, height: 0))
    }

    func testGuideScaleIsClamped() {
        let model = CameraViewModel()
        model.commitGuideGesture(.init(scale: 100, rotation: .zero, translation: .zero))
        XCTAssertEqual(model.guideTransform.scale, GuideTransform.scaleRange.upperBound)
        model.commitGuideGesture(.init(scale: 0.0001, rotation: .zero, translation: .zero))
        XCTAssertEqual(model.guideTransform.scale, GuideTransform.scaleRange.lowerBound)
    }

    func testResetGuideTransformRestoresIdentityAndKeepsOtherSettings() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.setGuideOpacity(0.9)
        model.setGuideLineColor(.white)
        model.commitGuideGesture(.init(scale: 2, rotation: .degrees(30), translation: CGSize(width: 40, height: 40)))

        model.resetGuideTransform()

        XCTAssertEqual(model.guideTransform, GuideTransform())
        XCTAssertEqual(model.guideOpacity, 0.9, accuracy: 0.001)
        XCTAssertEqual(model.guideLineColor, .white)
    }

    /// `NativePose.imageURL` is the source photo; the camera must never draw it.
    func testCameraGuideUsesTheExtractedLineArtNotTheSourcePhoto() {
        let photo = URL(string: "https://api.example.com/poses/p1/original.jpg")!
        let lineArt = URL(string: "https://api.example.com/poses/p1/skeleton.png")!
        let pose = NativePose(id: "p1", name: "Warrior", category: "Standing", imageURL: photo,
                              instructions: [], isSaved: false, guideURL: lineArt)

        XCTAssertEqual(pose.cameraGuideURL, lineArt)
        XCTAssertNotEqual(pose.cameraGuideURL, pose.imageURL)
    }

    /// An extraction that never landed (legacy local pose, failed job) has no line art. The guide
    /// then draws the stick-figure fallback — it must not quietly substitute the source photo.
    func testCameraGuideFallsBackToStickFigureWhenLineArtIsMissing() {
        let pose = NativePose(id: "legacy", name: "Legacy", category: "Standing",
                              imageURL: URL(string: "https://api.example.com/poses/legacy/original.jpg"),
                              instructions: [], isSaved: false)

        XCTAssertNil(pose.cameraGuideURL)
    }

    /// The guide is drawn with `.renderingMode(.template)` so the Line colour setting recolours the
    /// strokes. A template render keeps only the alpha channel, so an opaque background would turn
    /// the reference into a solid block over the preview. This renders the production chain
    /// (`AppImage.downsample` → `.template` → Line colour) off transparent line art and inspects the
    /// bitmap: transparent background, tinted strokes.
    func testTintedGuideKeepsTransparentBackgroundAndLineColour() throws {
        let lineArt = try XCTUnwrap(UIImage(contentsOfFile: try lineArtFixtureURL().path))
        let processor = AppImage.downsample(points: CGSize(width: 120, height: 180), scale: 1, contentMode: .fit)
        let processed = try XCTUnwrap(processor.process(item: .image(lineArt),
                                                        options: KingfisherParsedOptionsInfo([.scaleFactor(1)])))

        let tinted = Image(uiImage: processed)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundColor(.white)
        let rendered = try XCTUnwrap(render(tinted.frame(width: 120, height: 180),
                                           size: CGSize(width: 120, height: 180)))

        let pixels = try XCTUnwrap(rgbaBytes(of: rendered))
        XCTAssertEqual(alpha(pixels, x: 4, y: 4), 0, "the guide background must stay transparent, not a block")
        XCTAssertEqual(alpha(pixels, x: 116, y: 176), 0, "the guide background must stay transparent, not a block")
        XCTAssertGreaterThan(strokes(pixels).whiteCount, 100, "the line art's strokes are drawn")
    }

    // MARK: Runtime evidence — the shipped guide view chain (no camera, no touch in the simulator)

    /// Renders the real `CameraScreen` with an authorized model and a local line-art asset (loaded
    /// through Kingfisher, same processor as production). Asserts on the bitmap that the reference is
    /// the extracted line art — not the source photo, and not a solid tinted block — and that the
    /// committed pinch / rotate / drag transform moves those pixels. Writes the PNGs to the
    /// temporary directory so they can be inspected as evidence.
    func testCameraGuideScreenshotDrawsLineArtAndAppliesPlacement() async throws {
        let lineArt = try lineArtFixtureURL()
        let photo = try photoFixtureURL()
        let pose = NativePose(
            id: "guide-qa",
            name: "Guide QA",
            category: "Standing",
            imageURL: photo,
            instructions: [],
            isSaved: false,
            guideURL: lineArt
        )
        // Warm the exact cache key `guideOverlay` uses, so the hosted screen draws on first layout.
        let processor = AppImage.downsample(points: FullScreenImageTarget.drawSize, contentMode: .fit)
        _ = try? await KingfisherManager.shared.retrieveImage(with: lineArt, options: [.processor(processor)])

        let plain = try XCTUnwrap(renderCamera(guide: pose, placement: GuideTransform()))
        try write(plain, named: "camera-guide-line-art.png")
        let placed = try XCTUnwrap(renderCamera(
            guide: pose,
            placement: GuideTransform(scale: 1.3, rotation: .degrees(12), offset: CGSize(width: 40, height: 60))
        ))
        try write(placed, named: "camera-guide-transformed.png")

        let plainPixels = strokes(try XCTUnwrap(rgbaBytes(of: plain)))
        XCTAssertGreaterThan(plainPixels.whiteCount, 2_000, "the line art is drawn over the preview")
        XCTAssertEqual(plainPixels.redCount, 0, "the source photo must never be the reference")
        XCTAssertLessThan(plainPixels.whiteCount, 30_000, "a transparent asset must not tint into a solid block")

        let placedPixels = strokes(try XCTUnwrap(rgbaBytes(of: placed)))
        XCTAssertGreaterThan(placedPixels.whiteCount, 2_000, "the placed reference is still drawn")
        // Buffers are bottom-up: a downward drag lowers the centroid, a rightward drag raises x. The
        // fixed chrome inside the band (the 1x pill, the More control) dilutes the centroid, so the
        // thresholds only assert the direction of the committed pinch / twist / drag.
        XCTAssertGreaterThan(placedPixels.centroid.x - plainPixels.centroid.x, 8, "drag moves the reference")
        XCTAssertLessThan(placedPixels.centroid.y - plainPixels.centroid.y, -8, "drag moves the reference")
    }

    // MARK: Guide gesture math (pinch / twist / drag)

    /// The in-flight preview applies the same `Delta` the release commits, so letting go cannot jump
    /// the reference.
    func testGuideGesturePreviewMatchesCommittedTransform() {
        let model = CameraViewModel()
        let delta = GuideTransform.Delta(scale: 1.4, rotation: .degrees(12),
                                         translation: CGSize(width: 18, height: -9))

        let previewed = model.guideTransform.applying(delta)
        model.commitGuideGesture(delta)

        XCTAssertEqual(model.guideTransform, previewed)
    }

    /// Pinch, twist and drag fold into independent fields; a twist never scales or moves the guide and
    /// a drag never rotates it.
    func testGuideGesturesDoNotCrossCouple() {
        let rotated = GuideTransform().applying(.init(scale: 1, rotation: .degrees(45), translation: .zero))
        XCTAssertEqual(rotated.scale, 1)
        XCTAssertEqual(rotated.offset, .zero)

        let dragged = GuideTransform().applying(.init(scale: 1, rotation: .zero,
                                                      translation: CGSize(width: 30, height: 12)))
        XCTAssertEqual(dragged.scale, 1)
        XCTAssertEqual(dragged.rotation, .zero)
    }

    /// Zoom pill (`.nb-camera-zoom-slider` stops 1x → 2x → 3x)

    func testZoomStartsAtOneXForTheAccessibilityLabel() {
        let model = CameraViewModel()
        XCTAssertEqual(model.zoomLevel, .one)
        XCTAssertEqual("Zoom \(model.zoomLevel.label)", "Zoom 1x")
    }

    func testZoomCyclesThroughStopsAndWraps() {
        XCTAssertEqual(CameraZoomLevel.one.next(), .two)
        XCTAssertEqual(CameraZoomLevel.two.next(), .three)
        XCTAssertEqual(CameraZoomLevel.three.next(), .one)
    }

    func testZoomFactorsMatchLabels() {
        XCTAssertEqual(CameraZoomLevel.one.factor, 1)
        XCTAssertEqual(CameraZoomLevel.two.factor, 2)
        XCTAssertEqual(CameraZoomLevel.three.factor, 3)
    }

    func testCycleZoomIgnoredWhenControlsDisabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        model.cycleZoom()
        XCTAssertEqual(model.zoomLevel, .one)
    }

    func testCycleZoomAdvancesWhenEnabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.cycleZoom()
        XCTAssertEqual(model.zoomLevel, .two)
    }

    // MARK: Camera Tools popup geometry (`.nb-camera-tools-menu`)

    func testPopupAnchorsAboveChoosePose() {
        // bottom: 16 + 44 + 8 + 44 + 8 — the More control sits at 16 + 44 + 8.
        XCTAssertEqual(CameraProto.popupBottomOffset, 120)
    }

    func testPopupMatchesPrototypeWidthAndHeightCap() {
        XCTAssertEqual(CameraProto.popupWidth, 264)
        XCTAssertEqual(CameraProto.popupMaxHeight, 420)
    }

    // MARK: Pose picker stick figures

    func testStickFigureFollowsPoseName() {
        XCTAssertEqual(StickFigurePose.resolve(name: "Standing", category: "", index: 0), .standing)
        XCTAssertEqual(StickFigurePose.resolve(name: "Jumping", category: "", index: 0), .jumping)
        XCTAssertEqual(StickFigurePose.resolve(name: "Arms Up", category: "", index: 0), .armsUp)
        XCTAssertEqual(StickFigurePose.resolve(name: "Dancing", category: "", index: 0), .dancing)
    }

    func testStickFigureMatchesCategoryWhenNameIsOpaque() {
        XCTAssertEqual(StickFigurePose.resolve(name: "Pose 12", category: "Jumping", index: 0), .jumping)
    }

    func testStickFigureFallsBackToIndexRotation() {
        XCTAssertEqual(StickFigurePose.resolve(name: "Warrior II", category: "Yoga", index: 1), .jumping)
        XCTAssertEqual(StickFigurePose.resolve(name: "Warrior II", category: "Yoga", index: 5), .jumping)
    }

    func testEveryStickFigureHasAHeadAndLimbs() {
        for pose in StickFigurePose.allCases {
            XCTAssertGreaterThanOrEqual(pose.lines.count, 5, "\(pose) should have a torso and limbs")
            XCTAssertGreaterThan(pose.head.radius, 0)
        }
    }

    // MARK: - Render + bitmap helpers (the simulator has no camera and no touch input)

    private struct StrokePixels {
        var whiteCount = 0
        var redCount = 0
        /// Average pixel position of the Line-colour strokes. Buffer coordinates are bottom-up.
        var centroid = CGPoint.zero
    }

    private func renderCamera(guide pose: NativePose, placement: GuideTransform) -> UIImage? {
        var guide: NativePose? = pose
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.setGuideLineColor(.white)
        model.setGuideOpacity(1)
        model.commitGuideGesture(.init(scale: placement.scale,
                                       rotation: placement.rotation,
                                       translation: placement.offset))
        let screen = CameraScreen(
            guide: Binding(get: { guide }, set: { guide = $0 }),
            poseService: PreviewPoseService(),
            model: model
        )
        return render(screen, size: CGSize(width: 390, height: 760))
    }

    private func render<Content: View>(_ view: Content, size: CGSize) -> UIImage? {
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size)
        // The hosting view ships with an opaque system background; clear it so the bitmap keeps the
        // asset's own alpha (the whole point of the tint check).
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }

    private func rgbaBytes(of image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        let count = width * height * 4
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        defer { buffer.deallocate() }
        guard let context = CGContext(data: buffer, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (Array(UnsafeBufferPointer(start: buffer, count: count)), width, height)
    }

    private func alpha(_ pixels: (bytes: [UInt8], width: Int, height: Int), x: Int, y: Int) -> Int {
        let index = (y * pixels.width + x) * 4
        guard index >= 0, index + 3 < pixels.bytes.count else { return -1 }
        return Int(pixels.bytes[index + 3])
    }

    /// Counts Line-colour strokes and photo-red pixels inside the pose-reference band: the columns
    /// between the left/right control rails and the rows between the top controls and the shutter
    /// rail, so app chrome (and its cream rail) cannot be mistaken for the reference.
    private func strokes(_ pixels: (bytes: [UInt8], width: Int, height: Int)) -> StrokePixels {
        let width = pixels.width
        let height = pixels.height
        let minCol = Int(Double(width) * 0.2)
        let maxCol = Int(Double(width) * 0.8)
        // 8%..78% of the image height, top-down, expressed in bottom-up bitmap rows.
        let minRow = Int(Double(height) * 0.22)
        let maxRow = Int(Double(height) * 0.92)
        var result = StrokePixels()
        var sumX = 0.0
        var sumY = 0.0
        guard minCol < maxCol, minRow < maxRow else { return result }
        for row in minRow..<maxRow {
            for col in minCol..<maxCol {
                let index = (row * width + col) * 4
                let r = Int(pixels.bytes[index])
                let g = Int(pixels.bytes[index + 1])
                let b = Int(pixels.bytes[index + 2])
                let a = Int(pixels.bytes[index + 3])
                guard a > 200 else { continue }
                if r > 200, g > 200, b > 200 {
                    result.whiteCount += 1
                    sumX += Double(col)
                    sumY += Double(row)
                }
                if r > 180, g < 90, b < 90 {
                    result.redCount += 1
                }
            }
        }
        if result.whiteCount > 0 {
            result.centroid = CGPoint(x: sumX / Double(result.whiteCount),
                                      y: sumY / Double(result.whiteCount))
        }
        return result
    }

    private func fixtureDirectory() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("aipose-camera-guide-tests", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Transparent line art with the extractor's contract: thin dark strokes, fully transparent
    /// background. Drawn as a template it must tint — never flatten into a filled block.
    private func lineArtFixtureURL() throws -> URL {
        let url = fixtureDirectory().appendingPathComponent("line-art.png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let size = CGSize(width: 600, height: 900)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(14)
            cg.setLineCap(.round)
            cg.strokeEllipse(in: CGRect(x: 255, y: 60, width: 90, height: 90))
            cg.move(to: CGPoint(x: 300, y: 150))
            cg.addLine(to: CGPoint(x: 300, y: 500))
            cg.move(to: CGPoint(x: 150, y: 260))
            cg.addLine(to: CGPoint(x: 450, y: 260))
            cg.move(to: CGPoint(x: 300, y: 500))
            cg.addLine(to: CGPoint(x: 180, y: 820))
            cg.move(to: CGPoint(x: 300, y: 500))
            cg.addLine(to: CGPoint(x: 420, y: 820))
            cg.strokePath()
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    /// The source photo the camera must never draw as its reference: a saturated solid rectangle.
    private func photoFixtureURL() throws -> URL {
        let url = fixtureDirectory().appendingPathComponent("source-photo.png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let size = CGSize(width: 400, height: 600)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setFillColor(UIColor.red.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }

    private func write(_ image: UIImage, named name: String) throws {
        try XCTUnwrap(image.pngData()).write(to: fixtureDirectory().appendingPathComponent(name))
    }
}

/// Fake gate for the capture-path tests. The decision itself is proved in `PremiumGateTests` and
/// `PremiumGateModelTests`; here only the ordering around `capture()` matters — that the gate runs
/// first, and that an unentitled press never reaches the camera.
@MainActor
private final class StubPremiumGate: PremiumGateProviding {
    private let outcome: CaptureGateOutcome
    private(set) var cameraReadyInputs: [Bool] = []

    init(_ outcome: CaptureGateOutcome) {
        self.outcome = outcome
    }

    func captureOutcome(cameraReady: Bool) -> CaptureGateOutcome {
        cameraReadyInputs.append(cameraReady)
        return outcome
    }
}
