import Combine
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

    // MARK: - Shutter control state (P1-a)

    /// The control has to be pressable for a paywall answer even when the camera is not ready — the
    /// case where the paywall used to be unreachable at all (no permission, no hardware, simulator).
    func testShutterIsTappableForThePaywallWhenTheCameraIsNotReady() {
        let gate = StubPremiumGate(.paywall(signIn: false))
        let model = CameraViewModel(premiumGate: gate)
        model.coordinator.onPermissionResult(.denied)
        XCTAssertFalse(model.coordinator.state.captureEnabled, "the camera really is not ready")

        XCTAssertTrue(model.isShutterEnabled, "readiness must not hide the gate behind a dead button")

        // And the press it accepts is the paywall, never a capture attempt.
        var prompts: [Bool] = []
        let prompted = CameraViewModel(premiumGate: gate, onPremiumRequired: { prompts.append($0) })
        prompted.coordinator.onPermissionResult(.denied)
        prompted.capture()
        XCTAssertEqual(prompts, [false])
        XCTAssertEqual(prompted.coordinator.state.phase, .permissionRequired)
    }

    /// For the outcomes that would capture, readiness still decides the control — unchanged.
    func testShutterStaysDisabledWhenTheGateWouldOnlyDoNothing() {
        let gate = StubPremiumGate(.unchanged)
        let model = CameraViewModel(premiumGate: gate)
        model.coordinator.onPermissionResult(.denied)

        XCTAssertFalse(model.isShutterEnabled)
    }

    func testShutterIsEnabledForACapturableCamera() {
        let gate = StubPremiumGate(.capture)
        let model = CameraViewModel(premiumGate: gate)
        model.coordinator.onPermissionResult(.authorized)

        XCTAssertTrue(model.isShutterEnabled)
    }

    /// The press that starts a capture owns the control until it settles.
    func testShutterIsDisabledWhileACaptureIsInFlight() {
        let gate = StubPremiumGate(.capture)
        let model = CameraViewModel(premiumGate: gate)
        model.coordinator.onPermissionResult(.authorized)
        model.capture()

        XCTAssertTrue(model.coordinator.state.isCaptureInFlight)
        XCTAssertFalse(model.isShutterEnabled)
    }

    /// The shutter's enabled state reads the gate, so a gate move has to invalidate the camera view.
    func testGateMovesInvalidateTheCameraView() {
        let gate = StubPremiumGate(.paywall(signIn: false))
        let model = CameraViewModel(premiumGate: gate)
        var invalidations = 0
        let cancellable = model.objectWillChange.sink { _ in invalidations += 1 }

        gate.settle(.capture)

        XCTAssertEqual(invalidations, 1, "the control re-renders when a purchase lands")
        withExtendedLifetime(cancellable) {}
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

        // The committed drag moves the reference; prove it on the strokes' own painted box, measured in
        // a band that excludes the chrome (its text is white too, which is what made a centroid
        // comparison chrome-dependent: a pinch also redistributes stroke mass).
        let plainBytes = try XCTUnwrap(rgbaBytes(of: plain))
        // The reference lives between the top control bar (top 12%) and the collapsed control bar
        // (bottom 22%); this band is the pose-reference frame, so the chrome's white text is outside
        // it and the strokes measured here are the reference's own.
        let guideBand = Int(Double(plainBytes.height) * 0.20)..<Int(Double(plainBytes.height) * 0.80)
        let plainGuide = strokes(plainBytes, rows: guideBand)
        let placedGuide = strokes(try XCTUnwrap(rgbaBytes(of: placed)), rows: guideBand)
        XCTAssertGreaterThan(
            plainGuide.whiteCount, 300,
            "the reference's strokes are inside the measured band (\(plainGuide.whiteCount) px)"
        )
        // The committed pinch / twist / drag moves the painted reference. The *direction* of each axis
        // is pinned by the pure transform tests above; here the movement of the strokes' painted mass
        // is measured, so neither the buffer orientation nor a static chrome pixel can fake the result
        // (a box edge could: one stray glyph fixes it in both renders).
        XCTAssertGreaterThan(
            abs(placedGuide.centroid.y - plainGuide.centroid.y), 8,
            "the committed drag moves the reference vertically (\(plainGuide.centroid.y) → \(placedGuide.centroid.y))"
        )
        XCTAssertGreaterThan(
            abs(placedGuide.centroid.x - plainGuide.centroid.x), 8,
            "the committed drag moves the reference horizontally (\(plainGuide.centroid.x) → \(placedGuide.centroid.x))"
        )
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

    // MARK: Camera tools geometry

    /// The tools moved from the lower-right column to the top bar, so the popup now anchors *under*
    /// the top control bar instead of above the old Choose-pose control.
    func testPopupAnchorsUnderTheTopControlBar() {
        XCTAssertEqual(CameraProto.topControlsTop, 62)
        XCTAssertEqual(AP.HitTarget.minimum, 44, "the anchor is the bar's 44 pt control plus 8 pt")
    }

    func testPopupKeepsItsWidthAndHeightCap() {
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
        /// The painted box of the strokes, in the same bottom-up buffer coordinates.
        var minRow = Int.max
        var maxRow = Int.min
        var minCol = Int.max
        var maxCol = Int.min
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
        // F12: the strip is chrome and this evidence is about the *reference*, so the camera renders
        // collapsed (thumbnail · shutter · flip) and tall enough that the guide keeps the same share
        // of the image the band measurement was written against.
        model.collapsePickerStrip()
        let screen = CameraScreen(
            guide: Binding(get: { guide }, set: { guide = $0 }),
            poseService: PreviewPoseService(),
            model: model
        )
        return render(screen, size: CGSize(width: 390, height: 1_000))
    }

    private func render<Content: View>(_ view: Content, size: CGSize) -> UIImage? {
        let host = UIHostingController(rootView: view)
        // The camera is a dark surface; pin the appearance on the host so a `UIColor` dynamic provider
        // (the guide's Line-colour ink, the canvas) resolves its dark value whatever the test app's
        // current mode is. Without this the reference could render in dark ink on a light canvas.
        host.overrideUserInterfaceStyle = .dark
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
    private func strokes(
        _ pixels: (bytes: [UInt8], width: Int, height: Int),
        rows: Range<Int>? = nil
    ) -> StrokePixels {
        let width = pixels.width
        let height = pixels.height
        let minCol = Int(Double(width) * 0.2)
        let maxCol = Int(Double(width) * 0.8)
        // 8%..78% of the image height, top-down, expressed in bottom-up bitmap rows.
        let minRow = rows.map { max(0, $0.lowerBound) } ?? Int(Double(height) * 0.22)
        let maxRow = rows.map { min(height, $0.upperBound) } ?? Int(Double(height) * 0.92)
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
                    result.minRow = min(result.minRow, row)
                    result.maxRow = max(result.maxRow, row)
                    result.minCol = min(result.minCol, col)
                    result.maxCol = max(result.maxCol, col)
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
/// `PremiumGateModelTests`; here only what the camera does with that answer matters — the ordering
/// around `capture()`, the shutter's enabled state, and the fact that an unentitled press never
/// reaches the camera.
@MainActor
private final class StubPremiumGate: PremiumGateProviding {
    private let updates = PassthroughSubject<Void, Never>()
    private(set) var outcome: CaptureGateOutcome
    private(set) var cameraReadyInputs: [Bool] = []

    var gateUpdates: AnyPublisher<Void, Never> { updates.eraseToAnyPublisher() }

    init(_ outcome: CaptureGateOutcome) {
        self.outcome = outcome
    }

    /// A provider/session move: the camera has to re-render, exactly as the live model announces it.
    func settle(_ outcome: CaptureGateOutcome) {
        self.outcome = outcome
        updates.send(())
    }

    func captureOutcome(cameraReady: Bool) -> CaptureGateOutcome {
        cameraReadyInputs.append(cameraReady)
        return outcome
    }
}

// MARK: - Pose picker catalogue loads (two surfaces, one catalogue)

/// A service whose first call the test finishes on demand: the only way to deliver a *stale*
/// completion after a newer request has already succeeded.
private actor DeferredPoseService: PoseServing {
    private var callCount = 0
    private var firstContinuation: CheckedContinuation<[NativePose], Error>?
    private let rows: [NativePose]

    init(rows: [NativePose]) {
        self.rows = rows
    }

    var calls: Int { callCount }

    func waitUntilFirstCallStarted() async {
        while firstContinuation == nil {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func failFirstCall() {
        firstContinuation?.resume(throwing: URLError(.notConnectedToInternet))
        firstContinuation = nil
    }

    func poses(query: String?) async throws -> [NativePose] {
        callCount += 1
        guard callCount == 1 else { return rows }
        return try await withCheckedThrowingContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func pose(id: String) async throws -> NativePose {
        rows[0]
    }

    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage {
        guard offset <= 0 else { return .end }
        let rows = try await poses(query: query)
        return PosePage(poses: rows, hasMore: false, consumed: rows.count)
    }
}

@MainActor
final class PosePickerCatalogueLoadTests: XCTestCase {
    private func pose(_ id: String) -> NativePose {
        NativePose(id: id, name: "Pose \(id)", category: "Standing", imageURL: nil, instructions: [], isSaved: false)
    }

    /// The strip and the sheet both need the catalogue. The second caller joins the request in
    /// flight, so expanding the camera and then opening the sheet cannot race two answers.
    func testTwoSurfacesShareOneCatalogueRequest() async {
        let service = DeferredPoseService(rows: [pose("new")])
        let model = PosePickerViewModel(service: service)

        let strip = Task { await model.load() }
        await service.waitUntilFirstCallStarted()
        let sheet = Task { await model.load() }
        await Task.yield()

        let callsWhileJoining = await service.calls
        XCTAssertEqual(callsWhileJoining, 1, "the second surface joins the request in flight")

        await service.failFirstCall()
        await strip.value
        await sheet.value
        let callsAfter = await service.calls
        XCTAssertEqual(callsAfter, 1, "no second request was started")
        XCTAssertEqual(model.stateTone, .error, "the shared answer lands once")
    }

    /// The reported ordering: an older request fails *after* a newer one already populated the
    /// catalogue. The stale completion must be inert (generation guard), so the strip keeps its rows.
    func testAStaleFailureCannotReplaceANewerCatalogue() async {
        let service = DeferredPoseService(rows: [pose("new")])
        let model = PosePickerViewModel(service: service)

        let stale = Task { await model.load() }
        await service.waitUntilFirstCallStarted()
        // The collapsed camera's dismissal drops the catalogue and abandons the request behind it.
        model.prepareForDismissal()
        await model.load()
        XCTAssertEqual(model.filteredPoses.map(\.id), ["new"], "the newer request populated the catalogue")

        // ...and only now does the abandoned request fail.
        await service.failFirstCall()
        await stale.value

        XCTAssertEqual(
            model.filteredPoses.map(\.id), ["new"],
            "a stale failure must not replace the catalogue a newer request returned"
        )
        XCTAssertNil(model.stateTone, "no error card over a populated grid")
    }
}

// MARK: - Camera chrome: F12 collapsed state, F4 state panels, F5 snackbar

/// The redesign slice's own evidence: the collapse/expand contract, the strip's content mapping, the
/// shared 72 pt state panels and the snackbar's placement above the control bar.
///
/// Constants are not read back here: the collapse contract is asserted through the view model and the
/// pure layout mapping, and what the chrome *draws* is asserted on a rendered bitmap, pinned to one
/// appearance at a time (light and dark, the same token pairs the design system documents).
@MainActor
final class CameraChromeTests: XCTestCase {
    private func pose(_ id: String, name: String) -> NativePose {
        NativePose(id: id, name: name, category: "Standing", imageURL: nil, instructions: [], isSaved: false)
    }

    // MARK: - F12: collapsed / expanded (logic)

    func testTheCameraOpensExpandedAndTheSameControlCollapsesIt() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)

        XCTAssertTrue(model.isPickerExpanded, "default = expanded")
        model.togglePickerStrip()
        XCTAssertFalse(model.isPickerExpanded)
        model.togglePickerStrip()
        XCTAssertTrue(model.isPickerExpanded)
    }

    func testCollapsingIsGatedLikeEveryOtherCameraControl() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)

        model.togglePickerStrip()
        model.collapsePickerStrip()

        XCTAssertTrue(model.isPickerExpanded, "a control the camera cannot serve must not move the state")
    }

    /// The board's old "Guide hidden" screen becomes this collapsed state, so collapsing must not
    /// also hide the pose reference — the guide keeps its own eye control.
    func testCollapsedStateKeepsThePoseGuideVisible() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        XCTAssertTrue(model.isPoseGuideVisible)

        model.collapsePickerStrip()
        XCTAssertFalse(model.isPickerExpanded)
        XCTAssertTrue(model.isPoseGuideVisible, "collapsing the strip is not the guide-visibility toggle")

        model.expandPickerStrip()
        XCTAssertTrue(model.isPoseGuideVisible)
    }

    func testChromeLayoutHidesTheStripButNeverItsWayBack() {
        XCTAssertTrue(CameraChromeLayout.showsStrip(isPickerExpanded: true, showsPicker: true))
        XCTAssertFalse(CameraChromeLayout.showsStrip(isPickerExpanded: false, showsPicker: true))
        XCTAssertFalse(
            CameraChromeLayout.showsStrip(isPickerExpanded: true, showsPicker: false),
            "no camera, no strip"
        )
        XCTAssertTrue(
            CameraChromeLayout.showsStripToggle(showsPicker: true),
            "the collapsed state must keep the control that re-opens the strip"
        )
        XCTAssertFalse(CameraChromeLayout.showsStripToggle(showsPicker: false))

        XCTAssertEqual(CameraChromeLayout.stripToggleGlyph(isPickerExpanded: false), "chevron.up")
        XCTAssertEqual(CameraChromeLayout.stripToggleGlyph(isPickerExpanded: true), "chevron.down")
        XCTAssertEqual(CameraChromeLayout.stripToggleLabel(isPickerExpanded: false), "Show pose picker")
        XCTAssertEqual(CameraChromeLayout.stripToggleLabel(isPickerExpanded: true), "Hide pose picker")
    }

    // MARK: - F12: persistence

    func testCollapsedStateRoundTripsAndDefaultsToExpanded() throws {
        XCTAssertTrue(CameraSettings().isPickerExpanded, "default = expanded")

        var collapsed = CameraSettings()
        collapsed.isPickerExpanded = false
        let decoded = try XCTUnwrap(CameraSettings.decode(try collapsed.encodedJSON()))
        XCTAssertFalse(decoded.isPickerExpanded)

        // A row written before the collapsed state existed reads back as the state that shows more.
        let legacy = try XCTUnwrap(CameraSettings.decode(#"{"guideOpacity":0.8}"#))
        XCTAssertTrue(legacy.isPickerExpanded)
    }

    func testCollapsedStateSurvivesARelaunchAndIsWrittenBack() async throws {
        let store = InMemoryCameraSettingsStore(seed: CameraSettings(isPickerExpanded: false))
        let model = CameraViewModel(settingsStore: store, saveDebounceNanoseconds: 1_000_000)

        await waitUntil { model.initialMergeDone }
        XCTAssertFalse(model.isPickerExpanded, "the stored collapsed state comes back")

        model.coordinator.onPermissionResult(.authorized)
        model.expandPickerStrip()
        await waitUntil { await store.saved.last?.isPickerExpanded == true }
        let saved = await store.saved
        XCTAssertEqual(saved.last?.isPickerExpanded, true, "an expand is persisted like every other setting")
    }

    // MARK: - Strip content per picker state

    func testStripContentFollowsEveryPickerState() {
        let armsUp = pose("p1", name: "Arms up")

        XCTAssertEqual(CameraStripContent.resolve(from: .idle, filtered: []), .loading)
        XCTAssertEqual(CameraStripContent.resolve(from: .loading, filtered: []), .loading)
        XCTAssertEqual(CameraStripContent.resolve(from: .failed("boom"), filtered: []), .failed)
        XCTAssertEqual(CameraStripContent.resolve(from: .empty, filtered: []), .empty)
        XCTAssertEqual(CameraStripContent.resolve(from: .loaded([]), filtered: []), .empty)
        XCTAssertEqual(
            CameraStripContent.resolve(from: .loaded([armsUp]), filtered: []),
            .empty,
            "a filter that matches nothing is the empty strip, never a blank row"
        )
        XCTAssertEqual(
            CameraStripContent.resolve(from: .loaded([armsUp]), filtered: [armsUp]),
            .poses([armsUp])
        )
    }

    // MARK: - F4: which shared state panel

    func testStatePanelSelectionPerPermission() {
        XCTAssertNil(CameraStatePanel.permission(.authorized))
        XCTAssertEqual(CameraStatePanel.permission(.notDetermined), .permissionRequest)
        XCTAssertEqual(CameraStatePanel.permission(.denied), .permissionDenied)
        XCTAssertEqual(CameraStatePanel.permission(.restricted), .permissionDenied)

        XCTAssertEqual(CameraStatePanel.permissionDenied.permissionCopy.title, "Camera access is off")
        XCTAssertEqual(CameraStatePanel.permissionDenied.permissionCopy.actionTitle, "Open Settings")
        XCTAssertEqual(CameraStatePanel.permissionRequest.permissionCopy.actionTitle, "Allow Camera")
    }

    func testStatePanelSelectionPerPickerState() {
        XCTAssertNil(CameraStatePanel.picker(tone: nil, isNoMatch: false, term: "", isOffline: false))
        XCTAssertEqual(CameraStatePanel.picker(tone: .loading, isNoMatch: false, term: "", isOffline: false), .pickerLoading)
        XCTAssertEqual(CameraStatePanel.picker(tone: .error, isNoMatch: false, term: "", isOffline: false), .pickerFailed)
        XCTAssertEqual(
            CameraStatePanel.picker(tone: .error, isNoMatch: false, term: "", isOffline: true),
            .pickerOffline,
            "a failed load while offline is the offline notice"
        )
        XCTAssertEqual(CameraStatePanel.picker(tone: .offline, isNoMatch: false, term: "", isOffline: false), .pickerOffline)
        XCTAssertEqual(
            CameraStatePanel.picker(tone: .empty, isNoMatch: true, term: "cat", isOffline: false),
            .pickerNoMatch("cat")
        )
        XCTAssertEqual(
            CameraStatePanel.picker(tone: .empty, isNoMatch: false, term: "", isOffline: false),
            .pickerEmptyCatalogue
        )
        XCTAssertNil(CameraStatePanel.picker(tone: .success, isNoMatch: false, term: "", isOffline: false))
        XCTAssertNil(CameraStatePanel.picker(tone: .warning, isNoMatch: false, term: "", isOffline: false))
    }

    // MARK: - F12: what the bottom surface draws

    private static let bothSchemes: [ColorScheme] = [.dark, .light]

    func testExpandedDrawsTheStripAndCollapsedHidesItBehindOneControl() throws {
        let poses = [pose("p1", name: "Arms up"), pose("p2", name: "City walk"), pose("p3", name: "Café lean")]
        let size = CGSize(width: 393, height: 470)

        for scheme in Self.bothSchemes {
            let label = scheme == .dark ? "dark" : "light"
            let expanded = chromeBitmap(
                bar(poses: poses, selectedPoseID: "p1", isPickerExpanded: true),
                scheme: scheme,
                size: size
            )
            let collapsed = chromeBitmap(
                bar(poses: poses, selectedPoseID: "p1", isPickerExpanded: false),
                scheme: scheme,
                size: size
            )

            let panel = hex(APColorTokens.secondaryBackground, scheme)
            let expandedPanel = panelRows(expanded, hex: panel)
            let collapsedPanel = panelRows(collapsed, hex: panel)
            XCTAssertGreaterThan(
                expandedPanel.count, collapsedPanel.count + 100,
                "\(label): expanded draws the strip above the control bar, collapsed does not"
            )
            let expandedTop = try XCTUnwrap(expandedPanel.min(), "\(label): expanded paints no panel")
            let collapsedTop = try XCTUnwrap(collapsedPanel.min(), "\(label): collapsed paints no panel")
            XCTAssertTrue(
                expanded.differs(from: collapsed, inRows: band(expandedTop, expandedTop + 100, in: expanded)),
                "\(label): the strip band must not be identical in the two states"
            )

            // The strip's thumbnails are flat controlFill tiles; at least two of them are on that row,
            // which is a strip. The collapsed state's one control is asserted just below.
            // Collapsed keeps its way back: one hugging control (the "Poses" chip) sits directly
            // under the panel's top edge, while expanded draws a row of strip cards there. Measured as
            // filled pixels on one row: a card row paints ~3 fill widths, a chip row one.
            let controlFill = hex(APColorTokens.controlFill, scheme)
            let collapsedFill = fillPixels(collapsed, y: collapsedTop + 34, hex: controlFill)
            let expandedFill = fillPixels(expanded, y: expandedTop + 34, hex: controlFill)
            XCTAssertGreaterThanOrEqual(
                collapsedFill, 40,
                "\(label): the collapsed bar keeps a control that re-opens the strip (\(collapsedFill) px)"
            )
            XCTAssertGreaterThan(
                expandedFill, collapsedFill + 100,
                "\(label): expanded draws the strip's cards there (\(expandedFill) vs \(collapsedFill) px)"
            )

            // The shutter is still on screen in both states.
            let shutter = hex(APColorTokens.accent, scheme)
            XCTAssertFalse(
                filledRows(collapsed, hex: shutter, minRun: 40).isEmpty,
                "\(label): collapsed keeps the shutter"
            )
            XCTAssertFalse(
                filledRows(expanded, hex: shutter, minRun: 40).isEmpty,
                "\(label): expanded keeps the shutter"
            )
        }
    }

    func testNoPermissionHidesTheStripAndItsControl() {
        let poses = [pose("p1", name: "Arms up")]
        let size = CGSize(width: 393, height: 470)

        for scheme in Self.bothSchemes {
            let label = scheme == .dark ? "dark" : "light"
            let noPicker = chromeBitmap(
                bar(poses: poses, isPickerExpanded: true, showsPicker: false),
                scheme: scheme,
                size: size
            )
            let withPicker = chromeBitmap(
                bar(poses: poses, isPickerExpanded: true, showsPicker: true),
                scheme: scheme,
                size: size
            )

            // The panel is shorter by the whole strip + chip, so nothing of them was drawn.
            let panel = hex(APColorTokens.secondaryBackground, scheme)
            XCTAssertGreaterThan(
                panelRows(withPicker, hex: panel).count,
                panelRows(noPicker, hex: panel).count + 100,
                "\(label): a camera with no permission has no strip row"
            )
            XCTAssertFalse(
                filledRows(noPicker, hex: hex(APColorTokens.accent, scheme), minRun: 40).isEmpty,
                "\(label): the shutter stays reachable for QA"
            )
        }
    }

    // MARK: - F5: the snackbar sits above the control bar

    func testSnackbarIsPinnedAboveTheControlBar() throws {
        let poses = [pose("p1", name: "Arms up")]
        let size = CGSize(width: 393, height: 540)

        for scheme in Self.bothSchemes {
            let label = scheme == .dark ? "dark" : "light"
            let withStatus = chromeBitmap(bar(poses: poses, status: "Photo saved"), scheme: scheme, size: size)
            let withoutStatus = chromeBitmap(bar(poses: poses, status: nil), scheme: scheme, size: size)

            let surface = hex(APColorTokens.surface, scheme)
            let panel = hex(APColorTokens.secondaryBackground, scheme)

            // Geometry, not a colour hunt: the snackbar content spans x = 16…377, so one column inside
            // it (x = 20) meets the snackbar's surface exactly where the snackbar is.
            // The snackbar's own surface, sampled in the pill's empty tail (at x = 8 the bar's margin is
            // the panel, at x = 60 the message text and at x = 330 the action live).
            let snackbarRows = columnRows(withStatus, column: 300, hex: surface)
            XCTAssertGreaterThan(
                snackbarRows.count, 20,
                "\(label): the message is drawn as a snackbar band"
            )
            // F5: above the control bar. The shutter is the bar's unambiguous anchor in both schemes
            // (72 pt accent disc), so "above the shutter" is "above the control bar".
            let shutterTop = try XCTUnwrap(
                filledRows(withStatus, hex: hex(APColorTokens.accent, scheme), minRun: 40).min(),
                "\(label): no shutter in the control bar"
            )
            XCTAssertLessThan(
                try XCTUnwrap(snackbarRows.max()), shutterTop,
                "\(label): F5: the snackbar sits above the bottom control bar, never over it or mid-screen"
            )
            XCTAssertTrue(
                columnRows(withoutStatus, column: 300, hex: surface).isEmpty,
                "\(label): no message, no snackbar"
            )
        }
    }

    // MARK: - F4: the shared 72 pt state circle

    func testPermissionPanelDrawsTheSharedSeventyTwoPointCircle() throws {
        for scheme in Self.bothSchemes {
            let label = scheme == .dark ? "dark" : "light"
            let permission = chromeBitmap(
                CameraPermissionPanel(permission: .denied, onAllow: {}, onOpenSettings: {})
                    .background(AP.Color.scrim),
                scheme: scheme,
                size: CGSize(width: 393, height: 620),
                scale: 2
            )
            try assertSeventyTwoPointCircle(permission, scheme: scheme, label: label)
        }
    }

    func testEveryPickerStateDrawsTheSharedCircle() throws {
        let panels: [CameraStatePanel] = [
            .pickerLoading,
            .pickerFailed,
            .pickerEmptyCatalogue,
            .pickerNoMatch("cat")
        ]

        for scheme in Self.bothSchemes {
            let label = scheme == .dark ? "dark" : "light"
            var renders: [APBitmap] = []
            for panel in panels {
                renders.append(chromeBitmap(
                    CameraPickerStatePanel(panel: panel, onRetry: {}),
                    scheme: scheme,
                    size: CGSize(width: 393, height: 520),
                    scale: 2
                ))
                try assertSeventyTwoPointCircle(renders[renders.count - 1], scheme: scheme, label: "\(label) \(panel)")
            }
            // Different states are different pictures: a panel that ignored its tone would not differ.
            XCTAssertTrue(renders[1].differs(from: renders[2], inRows: 0..<renders[1].height), "\(label): error vs empty")
            XCTAssertTrue(renders[1].differs(from: renders[3], inRows: 0..<renders[1].height), "\(label): error vs no-match")
        }
    }

    func testOfflinePickerStateIsTheBannerNotAStateCircle() {
        for scheme in Self.bothSchemes {
            let label = scheme == .dark ? "dark" : "light"
            let offline = chromeBitmap(
                CameraPickerStatePanel(panel: .pickerOffline, onRetry: {}),
                scheme: scheme,
                size: CGSize(width: 393, height: 200),
                scale: 2
            )
            XCTAssertTrue(
                filledRows(offline, hex: hex(APColorTokens.selectedBackground, scheme), minRun: 20).isEmpty,
                "\(label): offline is a notice above the grid, not the empty/error panel"
            )
            XCTAssertFalse(
                filledRows(offline, hex: hex(APColorTokens.warningSurface, scheme), minRun: 200).isEmpty,
                "\(label): the offline banner draws its warning surface"
            )
        }
    }

    // MARK: - AX3

    func testChromeGrowsWithAccessibilityTextInsteadOfClipping() {
        let poses = [pose("p1", name: "Arms up")]
        for scheme in Self.bothSchemes {
            let label = scheme == .dark ? "dark" : "light"
            let panel = hex(APColorTokens.secondaryBackground, scheme)
            let regular = chromeBitmap(bar(poses: poses, isPickerExpanded: true), scheme: scheme, size: CGSize(width: 393, height: 720))
            let ax3 = chromeBitmap(
                bar(poses: poses, isPickerExpanded: true).environment(\.sizeCategory, .accessibilityExtraLarge),
                scheme: scheme,
                size: CGSize(width: 393, height: 900)
            )
            XCTAssertGreaterThan(
                panelRows(ax3, hex: panel).count,
                panelRows(regular, hex: panel).count + 20,
                "\(label): AX3 grows the bar (larger strip cards and chip) instead of clipping"
            )
        }
    }

    // MARK: - Screenshot evidence (S3 handback: no Maestro for Camera)

    /// Renders the shipped chrome to PNGs, one per appearance. The camera itself forces dark, so the
    /// light render is the token check for the same views; both are drawn from the production views.
    func testChromeScreenshotsForHandback() throws {
        let poses = [pose("p1", name: "Arms up"), pose("p2", name: "City walk"), pose("p3", name: "Café lean")]
        let size = CGSize(width: 393, height: 470)
        var captured: [(name: String, url: URL, bitmap: APBitmap)] = []

        for scheme in Self.bothSchemes {
            let tag = scheme == .dark ? "dark" : "light"
            captured.append(try writeScreenshot(
                bar(poses: poses, selectedPoseID: "p1", isPickerExpanded: true),
                scheme: scheme,
                size: size,
                name: "01-camera-expanded-\(tag).png"
            ))
            captured.append(try writeScreenshot(
                bar(poses: poses, selectedPoseID: "p1", isPickerExpanded: false),
                scheme: scheme,
                size: size,
                name: "02-camera-collapsed-\(tag).png"
            ))
            captured.append(try writeScreenshot(
                bar(poses: poses, selectedPoseID: "p1", isPickerExpanded: false, status: "Photo saved"),
                scheme: scheme,
                size: CGSize(width: 393, height: 540),
                name: "03-camera-snackbar-\(tag).png"
            ))
            captured.append(try writeScreenshot(
                CameraPermissionPanel(permission: .denied, onAllow: {}, onOpenSettings: {})
                    .background(AP.Color.scrim),
                scheme: scheme,
                size: CGSize(width: 393, height: 620),
                name: "04-camera-permission-denied-\(tag).png"
            ))
        }

        XCTAssertEqual(captured.count, 8)
        try writeScreenshotIndex(captured)
        print("SCREENSHOT_DIR \(captured[0].url.deletingLastPathComponent().path)")

        // The same state in the two appearances differs — and each appearance paints its own token.
        let darkExpanded = captured[0]
        let lightExpanded = captured[4]
        XCTAssertEqual(darkExpanded.name, "01-camera-expanded-dark.png")
        XCTAssertEqual(lightExpanded.name, "01-camera-expanded-light.png")
        XCTAssertNotEqual(try Data(contentsOf: darkExpanded.url), try Data(contentsOf: lightExpanded.url))

        let darkPanel = hex(APColorTokens.secondaryBackground, .dark)
        let lightPanel = hex(APColorTokens.secondaryBackground, .light)
        XCTAssertFalse(
            panelRows(darkExpanded.bitmap, hex: darkPanel).isEmpty,
            "the dark render paints the dark panel token"
        )
        XCTAssertTrue(
            panelRows(darkExpanded.bitmap, hex: lightPanel).isEmpty,
            "the dark render never paints the light panel token"
        )
        XCTAssertFalse(
            panelRows(lightExpanded.bitmap, hex: lightPanel).isEmpty,
            "the light render paints the light panel token"
        )
    }

    private func writeScreenshotIndex(_ captured: [(name: String, url: URL, bitmap: APBitmap)]) throws {
        let directory = try XCTUnwrap(captured.first).url.deletingLastPathComponent()
        let index = captured.map { "- \($0.name)" }.joined(separator: "\n")
        try index.write(
            to: directory.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeScreenshot<V: View>(
        _ view: V,
        scheme: ColorScheme,
        size: CGSize,
        name: String
    ) throws -> (name: String, url: URL, bitmap: APBitmap) {
        let host = UIHostingController(
            rootView: view
                .frame(width: size.width, height: size.height)
                .background(AP.Color.background)
        )
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .clear
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        let data = try XCTUnwrap(image.pngData(), "\(name) did not encode")
        XCTAssertGreaterThan(data.count, 2_000, "\(name) is blank")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-ds/s3", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return (name: name, url: url, bitmap: APBitmap(image: image) ?? APBitmap(width: 1, height: 1))
    }

    // MARK: - Helpers

    private func bar(
        poses: [NativePose],
        selectedPoseID: String? = nil,
        isPickerExpanded: Bool = true,
        showsPicker: Bool = true,
        status: String? = nil
    ) -> CameraBottomBar {
        CameraBottomBar(
            thumbnailURL: nil,
            isBusy: false,
            canCapture: true,
            controlsEnabled: true,
            status: status,
            statusTone: .success,
            strip: .poses(poses),
            selectedPoseID: selectedPoseID,
            isPickerExpanded: isPickerExpanded,
            showsPicker: showsPicker,
            zoomLevel: .one,
            onToggleStrip: {},
            onSelectPose: { _ in },
            onRetryStrip: {},
            onZoom: { _ in },
            onOpenGallery: {},
            onCapture: {},
            onSwitchCamera: {},
            onDismissStatus: {}
        )
    }

    private func dark<Content: View>(_ view: Content) -> some View {
        view.environment(\.colorScheme, .dark)
    }

    private func appPixel(_ hex: UInt32) -> APPixel {
        APPixel(
            red: Int((hex >> 16) & 0xFF),
            green: Int((hex >> 8) & 0xFF),
            blue: Int(hex & 0xFF),
            alpha: 255
        )
    }

    /// The token's value in the scheme the renderer is pinned to.
    private func hex(_ token: APColorToken, _ scheme: ColorScheme) -> UInt32 {
        token.spec(for: scheme).hex ?? 0
    }

    /// Deterministic renderer. The appearance is set on the hosting view's trait collection (a
    /// `UIColor` dynamic provider does not follow SwiftUI's `colorScheme` environment alone), so the
    /// expected token values are known instead of guessed from a first frame.
    private func chromeBitmap<V: View>(
        _ view: V,
        scheme: ColorScheme,
        size: CGSize,
        scale: CGFloat = 1
    ) -> APBitmap {
        let host = UIHostingController(
            rootView: view
                .environment(\.colorScheme, scheme)
                .frame(width: size.width, height: size.height)
                .background(AP.Color.background)
        )
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return APBitmap(image: image) ?? APBitmap(width: Int(size.width * scale), height: Int(size.height * scale))
    }

    /// Rows where `hex` is painted as a **flat run** of at least `minRun` pixels. A single-pixel match
    /// is not evidence: antialiased text produces every grey between two tokens, so a plain
    /// `rows(paintedWith:)` can "find" a snackbar surface inside a text edge. Only fills paint runs.
    private func filledRows(_ bitmap: APBitmap, hex: UInt32, minRun: Int, tolerance: Int = 6) -> [Int] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var rows: [Int] = []
        for y in 0..<bitmap.height {
            var run = 0
            for x in 0..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { run = 0; continue }
                let matches = abs(pixel.red - target.red) <= tolerance
                    && abs(pixel.green - target.green) <= tolerance
                    && abs(pixel.blue - target.blue) <= tolerance
                run = matches ? run + 1 : 0
                if run >= minRun {
                    rows.append(y)
                    break
                }
            }
        }
        return rows
    }

    /// Rows where the panel's own fill shows through its content-free left margin (x = 8). Counting
    /// flat runs instead is unreliable here: the strip's cards cover most of the width, so only a
    /// handful of padding rows would be "flat", while the margin is the panel all the way down.
    private func panelRows(_ bitmap: APBitmap, hex: UInt32, column: Int = 8) -> [Int] {
        var rows: [Int] = []
        for y in 0..<bitmap.height {
            guard let pixel = bitmap.color(x: column, y: y), pixel.alpha > 200 else { continue }
            if matches(pixel, hex) { rows.append(y) }
        }
        return rows
    }

    /// Rows where one vertical sample shows `hex`: the geometry of a control that spans a known x.
    private func columnRows(_ bitmap: APBitmap, column: Int, hex: UInt32) -> [Int] {
        panelRows(bitmap, hex: hex, column: column)
    }

    /// How many pixels of `hex` are painted on one row — a control's fill, not its glyphs.
    private func fillPixels(_ bitmap: APBitmap, y: Int, hex: UInt32) -> Int {
        guard y >= 0, y < bitmap.height else { return 0 }
        var count = 0
        for x in 0..<bitmap.width {
            guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { continue }
            if matches(pixel, hex) { count += 1 }
        }
        return count
    }

    private func matches(_ pixel: APPixel, _ hex: UInt32, tolerance: Int = 6) -> Bool {
        abs(pixel.red - Int((hex >> 16) & 0xFF)) <= tolerance
            && abs(pixel.green - Int((hex >> 8) & 0xFF)) <= tolerance
            && abs(pixel.blue - Int(hex & 0xFF)) <= tolerance
    }

    /// A row band that is always a legal range, even when the two edges are inverted or off the bitmap.
    private func band(_ lower: Int, _ upper: Int, in bitmap: APBitmap) -> Range<Int> {
        let start = max(0, min(min(lower, upper), bitmap.height))
        let end = max(start, min(max(lower, upper), bitmap.height))
        return start..<end
    }

    /// Rows carrying a text colour's ink — the word on a control, in the pinned scheme.
    private func inkRows(
        _ bitmap: APBitmap,
        inRows rows: Range<Int>,
        token: APColorToken,
        scheme: ColorScheme
    ) -> [Int] {
        let ink = appPixel(hex(token, scheme))
        var found: [Int] = []
        for y in rows where y >= 0 && y < bitmap.height {
            for x in 0..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 else { continue }
                if abs(pixel.red - ink.red) <= 14,
                   abs(pixel.green - ink.green) <= 14,
                   abs(pixel.blue - ink.blue) <= 14 {
                    found.append(y)
                    break
                }
            }
        }
        return found
    }

    /// F4: one 72 pt circle in the subtle accent tint, then the copy and the action below it.
    private func assertSeventyTwoPointCircle(
        _ bitmap: APBitmap,
        scheme: ColorScheme,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let rows = filledRows(bitmap, hex: hex(APColorTokens.selectedBackground, scheme), minRun: 20)
        let first = try XCTUnwrap(rows.min(), "\(label): no accent-tint circle painted", file: file, line: line)
        let last = try XCTUnwrap(rows.max(), file: file, line: line)
        // 72 pt at scale 2 = 144 rows; the antialiased rim may drop a row on each side.
        XCTAssertEqual(
            Double(last - first + 1), 144, accuracy: 8,
            "\(label): the state circle is 72 pt, not another size",
            file: file, line: line
        )
        let belowCircle = band(last + 8, bitmap.height, in: bitmap)
        XCTAssertFalse(belowCircle.isEmpty, "\(label): nothing below the circle", file: file, line: line)
        XCTAssertGreaterThan(
            bitmap.inkExtent(inRows: belowCircle, background: appPixel(0xFFFFFF)),
            0,
            "\(label): the title, copy and action are drawn under the circle",
            file: file, line: line
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @MainActor @escaping () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                XCTFail("condition not met within \(timeout)s", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}
