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

    func testFlashChipIsIgnoredWhenControlsDisabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        let initial = model.flashSetting
        model.setFlash(.on)
        XCTAssertEqual(model.flashSetting, initial)
    }

    /// The Flash row is three chips, so a choice applies exactly itself: there is no ring to cycle through and no
    /// hidden next step. Auto stays the shipped default.
    func testFlashIsChosenNotCycled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        XCTAssertEqual(model.flashSetting, .auto, "the shipped default")
        for setting in CameraFlashSetting.toolsChoices {
            model.setFlash(setting)
            XCTAssertEqual(model.flashSetting, setting)
        }
        XCTAssertEqual(CameraFlashSetting.toolsChoices, [.off, .auto, .on], "the board's order")
        XCTAssertEqual(CameraFlashSetting.toolsChoices.map(\.toolsSlug), ["off", "auto", "on"])
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
        model.setGuideLineColor(.yellow)
        XCTAssertEqual(model.guideLineColor, .pink, "a control the camera cannot serve does not move")
    }

    func testSetGuideLineColorWhenEnabled() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.setGuideLineColor(.yellow)
        XCTAssertEqual(model.guideLineColor, .yellow)
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
        model.setGuideLineColor(.yellow)
        model.commitGuideGesture(.init(scale: 2, rotation: .degrees(30), translation: CGSize(width: 40, height: 40)))

        model.resetGuideTransform()

        XCTAssertEqual(model.guideTransform, GuideTransform())
        XCTAssertEqual(model.guideOpacity, 0.9, accuracy: 0.001)
        XCTAssertEqual(model.guideLineColor, .yellow)
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
        // The placement stays inside the photo: the reference is now clipped to the framing rect (it is a
        // reference *for* the photo, never for the black bars), and a reference pushed past that edge is
        // measured by `CameraCanvasFramingTests`, not by a centroid.
        let placed = try XCTUnwrap(renderCamera(
            guide: pose,
            placement: GuideTransform(scale: 1.15, rotation: .degrees(12), offset: CGSize(width: 30, height: 50))
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

    /// The stored stops the slider's factor is written back to for older readers.
    func testTheStoredStopsMatchTheirFactors() {
        XCTAssertEqual(CameraZoomLevel.one.factor, 1)
        XCTAssertEqual(CameraZoomLevel.two.factor, 2)
        XCTAssertEqual(CameraZoomLevel.three.factor, 3)
    }

    func testTheSliderIsIgnoredWhenTheCameraCannotServeIt() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        model.setZoomFactor(2)
        XCTAssertEqual(model.zoomFactor, 1, "a control the camera cannot serve does not move")
    }

    func testTheSliderSetsTheFactorAndClampsItToTheLens() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        // The simulator has no capture device: the lens fallback is 1...2.
        XCTAssertEqual(model.zoomRange, 1...2)

        model.setZoomFactor(1.5)
        XCTAssertEqual(model.zoomFactor, 1.5, accuracy: 0.0001, "a continuous value, not a preset")

        model.setZoomFactor(9)
        XCTAssertEqual(model.zoomFactor, 2, accuracy: 0.0001, "the slider stops where the lens stops")
        model.setZoomFactor(0.2)
        XCTAssertEqual(model.zoomFactor, 1, accuracy: 0.0001)
    }

    // MARK: Camera tools geometry

    /// The tools live in the top bar, drawn from the safe-area top, so the popover anchors *under* that row
    /// instead of above the old Choose-pose control.
    func testPopupAnchorsUnderTheTopControlBar() {
        XCTAssertEqual(AP.HitTarget.minimum, 44, "the anchor is the bar's 44 pt control plus 8 pt")
        XCTAssertEqual(CameraStageFrame.shortRatioTopInset, 45, "and the photo frame starts a point below it")
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
        model.setGuideLineColor(.yellow)
        model.setGuideOpacity(1)
        model.commitGuideGesture(.init(scale: placement.scale,
                                       rotation: placement.rotation,
                                       translation: placement.offset))
        // This evidence is about the *reference*, and the bottom surface is now just the rail, so the
        // canvas is tall enough that the guide keeps the share of the image the band was written against.
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
                // The Line colour's ink: any of the sheet's bright palette colours (pink, yellow, green) and
                // white, against the black preview the simulator draws.
                if r > 190, g > 150, b > 40 {
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

    /// Two presentations of the picker both need the catalogue. The second caller joins the request in
    /// flight, so closing and reopening the sheet cannot race two answers.
    func testTwoSurfacesShareOneCatalogueRequest() async {
        let service = DeferredPoseService(rows: [pose("new")])
        let model = PosePickerViewModel(service: service)

        let firstPresentation = Task { await model.load() }
        await service.waitUntilFirstCallStarted()
        let sheet = Task { await model.load() }
        await Task.yield()

        let callsWhileJoining = await service.calls
        XCTAssertEqual(callsWhileJoining, 1, "the second surface joins the request in flight")

        await service.failFirstCall()
        await firstPresentation.value
        await sheet.value
        let callsAfter = await service.calls
        XCTAssertEqual(callsAfter, 1, "no second request was started")
        XCTAssertEqual(model.stateTone, .error, "the shared answer lands once")
    }

    /// The reported ordering: an older request fails *after* a newer one already populated the
    /// catalogue. The stale completion must be inert (generation guard), so the grid keeps its rows.
    func testAStaleFailureCannotReplaceANewerCatalogue() async {
        let service = DeferredPoseService(rows: [pose("new")])
        let model = PosePickerViewModel(service: service)

        let stale = Task { await model.load() }
        await service.waitUntilFirstCallStarted()
        // The sheet's dismissal drops the catalogue and abandons the request behind it.
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

// MARK: - The picker's search is the Search screen's search

/// Records the exact request each surface makes, so "the picker asks the Search screen's question" is a
/// recorded fact rather than a shared comment. It can hold a request open (to deliver a *stale* answer
/// late), fail every request (offline), and match on something other than the name (the server's own notion
/// of relevance, which no local name filter can reproduce).
private actor RecordingPoseSearchService: PoseServing {
    /// One recorded window read. When `PoseServing` carries the route in the request, `filter` joins this
    /// record and nothing else about the double changes.
    struct Request: Equatable, Sendable {
        let query: String?
        let offset: Int
        let limit: Int
    }

    private let rows: [NativePose]
    private let matches: @Sendable (NativePose, String) -> Bool
    private var recorded: [Request] = []
    private var held: [(query: String?, continuation: CheckedContinuation<PosePage, Error>)] = []
    private var holdsSearches = false
    private var fails = false

    init(
        rows: [NativePose],
        matches: @escaping @Sendable (NativePose, String) -> Bool = { $0.name.localizedStandardContains($1) }
    ) {
        self.rows = rows
        self.matches = matches
    }

    var requests: [Request] { recorded }
    /// Only the query-bearing reads: the catalogue load is not a search.
    var searchRequests: [Request] { recorded.filter { $0.query != nil } }

    func holdSearches() { holdsSearches = true }
    func failRequests(_ fail: Bool) { fails = fail }

    func poses(query: String?) async throws -> [NativePose] {
        try await posesPage(query: query, offset: 0, limit: PosesViewModel.Paging.pageSize).poses
    }

    func pose(id: String) async throws -> NativePose {
        rows.first { $0.id == id } ?? rows[0]
    }

    func posesPage(query: String?, offset: Int, limit: Int) async throws -> PosePage {
        recorded.append(Request(query: query, offset: offset, limit: limit))
        if holdsSearches, query != nil {
            return try await withCheckedThrowingContinuation { held.append((query, $0)) }
        }
        if fails { throw URLError(.notConnectedToInternet) }
        return answer(for: query)
    }

    func waitForSearchRequests(_ count: Int) async {
        while searchRequests.count < count {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    /// Finishes the newest held request: the query the user is waiting for.
    func releaseNewestHeld() {
        guard !held.isEmpty else { return }
        let next = held.removeLast()
        next.continuation.resume(returning: answer(for: next.query))
    }

    /// Finishes the oldest held request: the query the user has already typed past.
    func releaseOldestHeld() {
        guard !held.isEmpty else { return }
        let next = held.removeFirst()
        next.continuation.resume(returning: answer(for: next.query))
    }

    private func answer(for query: String?) -> PosePage {
        let term = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let poses = term.isEmpty ? rows : rows.filter { matches($0, term) }
        return PosePage(poses: poses, hasMore: false, consumed: poses.count)
    }
}

/// The picker's All scope asks the server the question the Search screen asks — same call, same window, same
/// rows — instead of filtering names client-side, and it keeps the local matcher only for what it has in hand
/// (the first paint under a new query, and the whole answer offline).
@MainActor
final class CameraPickerServerSearchTests: XCTestCase {
    private func pose(_ id: String, name: String, category: String = "Standing") -> NativePose {
        NativePose(
            id: id,
            name: name,
            category: category,
            imageURL: nil,
            instructions: [],
            isSaved: false
        )
    }

    private func picker(_ service: any PoseServing, debounce: UInt64 = 0) -> PosePickerViewModel {
        PosePickerViewModel(service: service, searchDebounceNanoseconds: debounce)
    }

    /// Same query, same request, same rows, same order — measured on both surfaces' real code paths: the
    /// picker's model and `PosesViewModel` (what the Search screen drives).
    func testThePickerAndTheSearchScreenGetTheSameRowsForTheSameQuery() async throws {
        let rows = [
            pose("w1", name: "Warrior II"),
            pose("d1", name: "Downward Dog"),
            pose("c1", name: "Café lean"),
        ]
        let service = RecordingPoseSearchService(rows: rows)

        let sheet = picker(service)
        await sheet.load()
        sheet.query = "warrior"
        await waitUntil { !sheet.state.rows.isEmpty }

        let searchScreen = PosesViewModel(service: service, debounceNanoseconds: 0)
        searchScreen.query = "warrior"
        searchScreen.scheduleSearch()
        await waitUntil {
            if case .loaded = searchScreen.state { return true }
            return false
        }

        XCTAssertEqual(
            sheet.state.rows.map(\.id),
            searchScreen.state.rows.map(\.id),
            "the same query returns the same pose ids, in the same order, from both screens"
        )
        XCTAssertEqual(sheet.state.rows.map(\.id), ["w1"])

        let requests = await service.searchRequests
        XCTAssertEqual(requests.count, 2, "one search request per surface")
        XCTAssertEqual(requests[0], requests[1], "and the two surfaces sent the same request")
        XCTAssertEqual(
            requests.last,
            RecordingPoseSearchService.Request(query: "warrior", offset: 0, limit: PosesViewModel.Paging.pageSize),
            "the Search screen's own window: first page, the server's page size"
        )
    }

    /// The rows the sheet draws are the server's answer, not a local name filter over it: a pose the server
    /// matched by its category is shown even though its name does not contain the query.
    func testAServerMatchIsNotFilteredOutByName() async {
        let service = RecordingPoseSearchService(
            rows: [pose("run1", name: "Sun salutation", category: "Cardio warrior flow")],
            matches: { $0.category.localizedStandardContains($1) }
        )
        let sheet = picker(service)
        await sheet.load()

        sheet.query = "warrior"
        await waitUntil { !sheet.state.rows.isEmpty }

        XCTAssertEqual(
            sheet.state.rows.map(\.id), ["run1"],
            "the sheet shows what the server matched; a second local name filter would hide it"
        )
        XCTAssertEqual(sheet.stateTone, nil, "a populated grid draws no card")
    }

    /// A slow answer for a query the user has already typed past never lands.
    func testAStaleAnswerCannotReplaceANewerQuery() async {
        let service = RecordingPoseSearchService(rows: [
            pose("warrior", name: "Warrior II"),
            pose("walk", name: "City walk"),
        ])
        await service.holdSearches()
        let sheet = picker(service)
        await sheet.load()

        sheet.query = "walk"
        await service.waitForSearchRequests(1)
        sheet.query = "warrior"
        await service.waitForSearchRequests(2)

        // The answer the user is waiting for arrives first...
        await service.releaseNewestHeld()
        await waitUntil { sheet.state.rows.map(\.id) == ["warrior"] }
        XCTAssertEqual(sheet.state.rows.map(\.id), ["warrior"])

        // ...and the abandoned one lands afterwards, with rows for a query nobody is looking at.
        await service.releaseOldestHeld()
        // Give the stale completion a turn to (wrongly) paint.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(
            sheet.state.rows.map(\.id), ["warrior"],
            "an answer for an older query must not replace the newer query's rows"
        )
    }

    /// Typing cancels the search that has not fired yet: one request, for the last text.
    func testChangingTheQueryCancelsThePendingSearch() async {
        let service = RecordingPoseSearchService(rows: [
            pose("a", name: "Arms up"),
            pose("b", name: "Warrior II"),
        ])
        let sheet = picker(service, debounce: 60_000_000)
        await sheet.load()

        sheet.query = "a"
        sheet.query = "warrior"
        await service.waitForSearchRequests(1)
        try? await Task.sleep(nanoseconds: 120_000_000)

        let requests = await service.searchRequests
        XCTAssertEqual(requests.count, 1, "the keystroke cancelled the debounced search for \"a\"")
        XCTAssertEqual(requests.first?.query, "warrior")
        XCTAssertEqual(sheet.state.rows.map(\.id), ["b"])
    }

    /// While the answer is out, the grid narrows what is already in hand instead of blanking (or showing a
    /// spinner over rows the sheet already has).
    func testTheFirstPaintNarrowsWhatIsInHandWhileTheAnswerIsOut() async {
        let service = RecordingPoseSearchService(rows: [
            pose("w", name: "Warrior II"),
            pose("d", name: "Downward Dog"),
        ])
        await service.holdSearches()
        let sheet = picker(service)
        await sheet.load()

        sheet.query = "warrior"
        XCTAssertEqual(
            sheet.state.rows.map(\.id), ["w"],
            "the first paint is the local matcher over the catalogue, with no request answered yet"
        )
        await service.waitForSearchRequests(1)
        XCTAssertEqual(sheet.state.rows.map(\.id), ["w"], "and it holds while the request is out")

        await service.releaseNewestHeld()
        await waitUntil { !sheet.state.rows.isEmpty }
        XCTAssertEqual(sheet.state.rows.map(\.id), ["w"], "the answer replaces it when it lands")
    }

    /// Offline the sheet cannot ask the server, so the local name filter is the whole answer — narrowed, with
    /// the offline notice on top, never a blank or a dead-end card.
    func testOfflineNarrowsWhatIsInHandInsteadOfBlanking() async {
        let service = RecordingPoseSearchService(rows: [
            pose("w", name: "Warrior II"),
            pose("d", name: "Downward Dog"),
        ])
        let sheet = picker(service)
        await sheet.load()
        sheet.setOfflineForTesting(true)
        await service.failRequests(true)

        sheet.query = "warrior"
        await waitUntil { sheet.state.rows.map(\.id) == ["w"] }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(sheet.state.rows.map(\.id), ["w"], "the catalogue's own matches are the offline answer")
        XCTAssertTrue(sheet.showsOfflineNotice, "and the notice says the rows may be stale")
        XCTAssertNil(sheet.stateTone, "a populated grid keeps its content area")
    }

    /// A query with nothing in hand and no answer is the failed/offline card, not a silent empty grid.
    func testAQueryWithNothingInHandShowsTheOfflineCard() async {
        let service = RecordingPoseSearchService(rows: [pose("w", name: "Warrior II")])
        await service.failRequests(true)
        let sheet = picker(service)
        sheet.setOfflineForTesting(true)

        sheet.query = "zzz"
        await waitUntil { sheet.stateTone == .offline }
        XCTAssertEqual(sheet.stateTone, .offline, "nothing in hand and nothing from the server: say why")
    }

    /// The window is closed at the first page: the sheet is a picker, not the Search screen's endless list.
    func testTheSearchUsesTheFirstWindowOnly() async {
        let service = RecordingPoseSearchService(rows: [pose("w", name: "Warrior II")])
        let sheet = picker(service)
        await sheet.load()

        sheet.query = "warrior"
        await service.waitForSearchRequests(1)

        let requests = await service.searchRequests
        XCTAssertEqual(requests.map(\.offset), [0])
        XCTAssertEqual(requests.map(\.limit), [PosesViewModel.Paging.pageSize])
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

// MARK: - Picker scope (All / Saved)

/// A Saved provider the test drives: `rows` for a success, `failure` for a failure, and an optional
/// gate that holds the first call open so a stale completion can be delivered late.
private actor StubSavedPosesService: CameraSavedPosesProviding {
    private let rows: [NativePose]
    private let failure: Error?
    private let heldFirstCall: Bool
    private var calls = 0
    private var firstContinuation: CheckedContinuation<[NativePose], Error>?
    private var firstStarted = false

    init(rows: [NativePose] = [], failure: Error? = nil, heldFirstCall: Bool = false) {
        self.rows = rows
        self.failure = failure
        self.heldFirstCall = heldFirstCall
    }

    var callCount: Int { calls }

    var firstCallStarted: Bool { firstStarted }

    func releaseFirstCall() {
        firstStarted = true
        if let failure {
            firstContinuation?.resume(throwing: failure)
        } else {
            firstContinuation?.resume(returning: rows)
        }
        firstContinuation = nil
    }

    func savedPoses() async throws -> [NativePose] {
        calls += 1
        if heldFirstCall, calls == 1 {
            return try await withCheckedThrowingContinuation { continuation in
                firstStarted = true
                firstContinuation = continuation
            }
        }
        if let failure { throw failure }
        return rows
    }
}

@MainActor
final class CameraPickerScopeTests: XCTestCase {
    private func pose(_ id: String, name: String? = nil) -> NativePose {
        NativePose(
            id: id,
            name: name ?? "Pose \(id)",
            category: "Standing",
            imageURL: nil,
            instructions: [],
            isSaved: true
        )
    }

    // MARK: Scope switching

    /// Search sits above the chips, and the chips *narrow* what the query already matched. A scope tap
    /// therefore keeps the query: emptying the field would make "type a name, then pick a collection"
    /// impossible, which is the order the sheet is laid out in.
    func testThePickerOpensOnAllAndSwitchingScopeKeepsTheQuery() {
        let model = PosePickerViewModel(service: PreviewPoseService())
        XCTAssertEqual(model.scope, .all, "the picker opens on the catalogue")

        model.query = "arms"
        model.selectScope(.saved)
        XCTAssertEqual(model.scope, .saved)
        XCTAssertEqual(model.query, "arms", "the Saved chip narrows the query instead of discarding it")

        model.selectScope(.all)
        XCTAssertEqual(model.query, "arms", "and the All chip keeps it on the way back")

        model.query = "walk"
        model.selectScope(.all)
        XCTAssertEqual(model.query, "walk", "tapping the chip already selected is a no-op")
    }

    func testScopeIdentifiersAreTheQaContract() {
        XCTAssertEqual(CameraPickerScope.all.accessibilityIdentifier, "posePicker.scope.all")
        XCTAssertEqual(CameraPickerScope.saved.accessibilityIdentifier, "posePicker.scope.saved")
    }

    func testScopeRowsFilterThroughTheSharedRules() {
        let catalogue = [pose("a", name: "Arms up"), pose("b", name: "City walk")]
        let saved = [pose("b", name: "City walk"), pose("c", name: "Café lean")]

        XCTAssertEqual(
            CameraPickerScope.all.rows(catalogue: catalogue, saved: saved, query: "").map(\.id),
            ["a", "b"]
        )
        XCTAssertEqual(
            CameraPickerScope.all.rows(catalogue: catalogue, saved: saved, query: "walk").map(\.id),
            ["b"]
        )
        XCTAssertEqual(
            CameraPickerScope.saved.rows(catalogue: catalogue, saved: saved, query: "").map(\.id),
            ["b", "c"],
            "the Saved chip lists the account's saved collection, not the catalogue"
        )
        XCTAssertEqual(
            CameraPickerScope.saved.rows(catalogue: catalogue, saved: saved, query: "lean").map(\.id),
            ["c"],
            "the saved list uses the same name filter the Saved screen uses"
        )
        XCTAssertEqual(
            CameraPickerScope.saved.rows(catalogue: catalogue, saved: [], query: "").map(\.id),
            [],
            "no saved rows is the empty scope, never the catalogue"
        )
    }

    /// One name matcher for both scopes and for the Search screen: the picker cannot answer a query
    /// differently from the Saved screen, and it cannot answer it differently in its two scopes either.
    /// The assertions compare the picker's own rows against `PoseAdapterMerge`, so the test fails if the
    /// two ever drift apart again (the All scope used to run `lowercased().contains` of its own).
    func testBothScopesFilterWithTheSharedNameMatcher() {
        let catalogue = [
            pose("a", name: "Warrior II"),
            pose("b", name: "Downward Dog"),
            pose("c", name: "Café lean"),
        ]
        let saved = [pose("b", name: "Downward Dog"), pose("c", name: "Café lean")]

        for query in ["WARRIOR", "  warrior  ", "dog", "café", "CAFÉ", "  ", "zzz", ""] {
            XCTAssertEqual(
                CameraPickerScope.all.rows(catalogue: catalogue, saved: saved, query: query).map(\.id),
                PoseAdapterMerge.filterSavedLocally(catalogue, query: query).map(\.id),
                "the All scope answers \"\(query)\" exactly like the shared filter"
            )
            XCTAssertEqual(
                CameraPickerScope.saved.rows(catalogue: catalogue, saved: saved, query: query).map(\.id),
                PoseAdapterMerge.filterSavedLocally(saved, query: query).map(\.id),
                "the Saved scope answers \"\(query)\" exactly like the shared filter"
            )
        }
    }

    /// Diacritic-insensitivity, which is what `localizedStandardContains` buys over
    /// `localizedCaseInsensitiveContains`: a user who types "cafe" — no accent key, no patience — finds
    /// "Café lean", on both chips and through the Saved screen's filter, because there is one matcher.
    func testTheSharedMatcherIgnoresDiacritics() {
        let poses = [pose("c", name: "Café lean"), pose("d", name: "Warrior II")]

        XCTAssertEqual(
            CameraPickerScope.all.rows(catalogue: poses, saved: [], query: "cafe").map(\.id),
            ["c"],
            "the All chip finds an accented name from an unaccented query"
        )
        XCTAssertEqual(
            CameraPickerScope.saved.rows(catalogue: [], saved: poses, query: "CAFE").map(\.id),
            ["c"],
            "and so does the Saved chip, which is the Saved screen's own filter"
        )
        XCTAssertEqual(
            PoseAdapterMerge.filterSavedLocally(poses, query: "cafe").map(\.id),
            ["c"],
            "the Saved screen reads the same answer from the shared filter"
        )
        XCTAssertEqual(
            PoseAdapterMerge.filterSavedLocally(poses, query: "café").map(\.id),
            ["c"],
            "an accented query still matches the accented name"
        )
        XCTAssertEqual(
            PoseAdapterMerge.filterSavedLocally([pose("e", name: "Cafe stretch")], query: "café").map(\.id),
            ["e"],
            "and matches the unaccented spelling of the same word"
        )
    }

    /// The three behaviours the shared matcher is chosen for, spelled out on the picker's own rows:
    /// case-insensitivity, a trimmed query, and an empty query that filters nothing.
    func testTheQueryIsCaseInsensitiveAndTrimmed() {
        let catalogue = [pose("a", name: "Warrior II"), pose("b", name: "Downward Dog")]
        let saved = [pose("a", name: "Warrior II")]

        XCTAssertEqual(
            CameraPickerScope.all.rows(catalogue: catalogue, saved: saved, query: "  WARRIOR  ").map(\.id),
            ["a"],
            "a padded, upper-case query finds the pose a hand-typed search would"
        )
        XCTAssertEqual(
            CameraPickerScope.saved.rows(catalogue: catalogue, saved: saved, query: "wArRiOr").map(\.id),
            ["a"]
        )
        XCTAssertEqual(
            CameraPickerScope.all.rows(catalogue: catalogue, saved: saved, query: "   ").map(\.id),
            ["a", "b"],
            "whitespace is not a query"
        )
    }

    /// A query that matches nothing is the sheet's "No poses match" card, not a blank grid: the picker
    /// model's own state mapping is what the sheet reads to draw it.
    func testANoMatchQueryIsTheEmptyState() async {
        let model = PosePickerViewModel(service: PreviewPoseService())
        await model.load()
        guard case .loaded(let poses) = model.state, !poses.isEmpty else {
            return XCTFail("the preview catalogue should have loaded, saw \(model.state)")
        }

        model.query = "no-such-pose-anywhere"

        XCTAssertTrue(model.filteredPoses.isEmpty, "nothing in hand matches, so the grid holds no rows")
        // "No poses match" is the server's answer, so it arrives with the answer — the sheet asks the same
        // question the Search screen asks instead of deciding locally.
        await model.searchNowForTesting()
        XCTAssertEqual(model.stateTone, .empty, "the no-match card, not an error and not a blank grid")
        XCTAssertTrue(model.emptyIsNoMatch, "the copy names the query instead of \"no poses yet\"")

        model.clearSearch()
        XCTAssertFalse(model.filteredPoses.isEmpty, "clearing the query brings the grid back")
    }

    // MARK: Saved data model (real behaviour, no fakes in the app)

    func testSavedScopeLoadsTheAccountsCollection() async {
        let rows = [pose("s1"), pose("s2")]
        let model = CameraSavedPosesModel(provider: StubSavedPosesService(rows: rows))

        XCTAssertEqual(model.rows, [], "nothing is drawn before the first load")
        await model.load()

        XCTAssertEqual(model.rows.map(\.id), ["s1", "s2"])
    }

    func testSavedScopeEmptyAndFailureStates() async {
        let empty = CameraSavedPosesModel(provider: StubSavedPosesService(rows: []))
        await empty.load()
        guard case .empty = empty.state else {
            return XCTFail("no saved rows is the empty state, saw \(empty.state)")
        }

        let failing = CameraSavedPosesModel(
            provider: StubSavedPosesService(failure: URLError(.notConnectedToInternet))
        )
        await failing.load()
        guard case .failed = failing.state else {
            return XCTFail("a failed saved load is the error state, saw \(failing.state)")
        }
    }

    func testTwoSavedLoadsShareOneRequest() async {
        let service = StubSavedPosesService(rows: [pose("s1")], heldFirstCall: true)
        let model = CameraSavedPosesModel(provider: service)

        let first = Task { await model.load() }
        while !(await service.firstCallStarted) { await Task.yield() }
        let second = Task { await model.load() }
        await Task.yield()

        let callsWhileJoining = await service.callCount
        XCTAssertEqual(callsWhileJoining, 1, "the second tap joins the request in flight")

        await service.releaseFirstCall()
        await first.value
        await second.value
        XCTAssertEqual(model.rows.map(\.id), ["s1"])
    }

    func testAStaleSavedFailureCannotReplaceANewerCollection() async {
        let service = StubSavedPosesService(rows: [pose("new")], heldFirstCall: true)
        let model = CameraSavedPosesModel(provider: service)

        let stale = Task { await model.load() }
        while !(await service.firstCallStarted) { await Task.yield() }
        // The scope left Saved (or the account changed): the rows and the request behind them go.
        model.reset()
        await model.load()
        XCTAssertEqual(model.rows.map(\.id), ["new"], "the newer request populated the collection")

        await service.releaseFirstCall()   // the abandoned request fails only now
        await stale.value
        XCTAssertEqual(
            model.rows.map(\.id), ["new"],
            "a stale failure must not replace the collection a newer request returned"
        )
    }

    // MARK: Session gate

    func testSavedScopePresentationPerStageAndState() {
        let rows = [pose("s1")]
        XCTAssertEqual(
            CameraSavedScopePresentation.resolve(stage: .resolvingSession, state: .idle, isOffline: false),
            .resolvingSession
        )
        XCTAssertEqual(
            CameraSavedScopePresentation.resolve(stage: .signInRequired, state: .loaded(rows), isOffline: false),
            .signInRequired,
            "a guest is never shown cached rows as current"
        )
        XCTAssertEqual(
            CameraSavedScopePresentation.resolve(stage: .list, state: .loading, isOffline: false),
            .loading
        )
        XCTAssertEqual(
            CameraSavedScopePresentation.resolve(stage: .list, state: .failed("boom"), isOffline: false),
            .failed
        )
        XCTAssertEqual(
            CameraSavedScopePresentation.resolve(stage: .list, state: .empty, isOffline: false),
            .empty
        )
        XCTAssertEqual(
            CameraSavedScopePresentation.resolve(stage: .list, state: .loaded([]), isOffline: false),
            .empty
        )
        XCTAssertEqual(
            CameraSavedScopePresentation.resolve(stage: .list, state: .loaded(rows), isOffline: false),
            .rows(rows)
        )
    }

    func testTheSavedCopyIsTheSavedScreensOwn() {
        // The camera must describe the collection the same way the Saved screen does.
        XCTAssertEqual(PoseResultsStateCopy.savedEmptyTitle, "No saved poses yet")
        XCTAssertEqual(PoseResultsStateCopy.savedSignInTitle, "Sign in to view your saved poses")
        XCTAssertEqual(PoseResultsStateCopy.retryActionTitle, "Try again")
    }

    // MARK: Permission gate

    func testPermissionGateKeepsItsHandleAndTheBoardsSecondAction() {
        XCTAssertEqual(CameraPermissionPanel.notNowTitle, "Not now")
        XCTAssertEqual(CameraPermissionPanel.notNowIdentifier, "camera.permission.notNow")
        XCTAssertEqual(CameraStatePanel.permissionDenied.permissionCopy.title, "Camera access is off")
        XCTAssertEqual(CameraStatePanel.permissionDenied.permissionCopy.actionTitle, "Open Settings")
    }
}

// MARK: - Where the pose picker lives (owner feedback, build 18)

@MainActor
final class CameraPickerAccessTests: XCTestCase {
    /// The Poses control on the scale row is the sheet's only entry, and it opens the sheet in one tap —
    /// there is no strip to expand first, and no state in which the picker is hidden behind a chevron.
    func testThePosesControlOpensTheSheetInOneTap() {
        XCTAssertEqual(CameraChromeLayout.posesControlIdentifier, "camera.choosePose")
        XCTAssertTrue(CameraChromeLayout.showsPosesControl(showsPicker: true))
        XCTAssertFalse(CameraChromeLayout.showsPosesControl(showsPicker: false), "no camera, no control")

        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        XCTAssertFalse(model.showPosePicker, "the sheet is closed until it is asked for")

        model.openPosePicker()
        XCTAssertTrue(model.showPosePicker, "one tap opens the picker sheet with search and scopes")
        model.closePosePicker()
        XCTAssertFalse(model.showPosePicker)

        model.openPosePicker()
        XCTAssertTrue(model.showPosePicker, "and it opens again after a close: nothing was collapsed")
    }

    /// A denied camera cannot open the sheet at all — the control is the entry point, not a bypass.
    func testTheSheetIsGated() {
        let denied = CameraViewModel()
        denied.coordinator.onPermissionResult(.denied)
        denied.openPosePicker()
        XCTAssertFalse(denied.showPosePicker, "a camera that cannot serve the picker does not open it")
    }
}

@MainActor
final class CameraPickerSheetLayoutTests: XCTestCase {
    /// Search is at the top of the sheet: directly under the title, above the scope chips. A catalogue
    /// of hundreds is only usable through the query, so it must not sit below the fold behind chips.
    func testSearchSitsAtTheTopOfTheSheet() {
        XCTAssertEqual(
            PosePickerLayout.order,
            [.handle, .header, .search, .scopes, .results],
            "the sheet renders exactly this order (PosePickerSheet.panel iterates it)"
        )
        let searchIndex = PosePickerLayout.order.firstIndex(of: .search)
        let scopesIndex = PosePickerLayout.order.firstIndex(of: .scopes)
        let resultsIndex = PosePickerLayout.order.firstIndex(of: .results)
        XCTAssertNotNil(searchIndex)
        XCTAssertLessThan(searchIndex ?? .max, scopesIndex ?? .min, "search is above the All/Saved chips")
        XCTAssertLessThan(searchIndex ?? .max, resultsIndex ?? .min, "search is above the results")
    }

    /// The sheet's QA handles are the contract the picker flows use; they are named here so a rename has
    /// to be a deliberate edit of this test.
    func testTheSheetHandlesAreStable() {
        XCTAssertEqual(PosePickerLayout.searchIdentifier, "posePicker.search")
        XCTAssertEqual(PosePickerLayout.searchClearIdentifier, "posePicker.searchClear")
        XCTAssertEqual(PosePickerLayout.closeIdentifier, "posePicker.close")
        XCTAssertEqual(PosePickerLayout.stateIdentifier, "posePicker.state")
        XCTAssertEqual(PosePickerLayout.gridIdentifier, "posePicker.grid")
        XCTAssertEqual(PosePickerLayout.sheetIdentifier, "posePicker.sheet")
        XCTAssertEqual(PosePickerLayout.rowIdentifier(poseID: "p-42"), "posePicker.row.p-42")
        XCTAssertEqual(CameraPickerScope.all.accessibilityIdentifier, "posePicker.scope.all")
        XCTAssertEqual(CameraPickerScope.saved.accessibilityIdentifier, "posePicker.scope.saved")
    }

    /// The no-match card speaks the Search screen's language, because it is the Search screen's copy:
    /// `SearchResultsCopy` is the one place the words live, so the two surfaces cannot drift apart.
    func testTheNoMatchCardReusesTheSearchScreenCopy() {
        let copy = CameraStatePanel.noMatchCopy(term: "dancing")
        XCTAssertEqual(copy.title, SearchResultsCopy.emptyTitle(query: "dancing", filter: .all))
        XCTAssertEqual(copy.message, SearchResultsCopy.emptyMessage(query: "dancing", filter: .all))
        XCTAssertEqual(copy.title, "No poses match “dancing”")
        XCTAssertEqual(copy.message, "Try a different pose name.")

        // And the panel the sheet draws for a no-match query is that card, not a blank grid.
        XCTAssertEqual(
            CameraStatePanel.picker(tone: .empty, isNoMatch: true, term: "dancing", isOffline: false),
            .pickerNoMatch("dancing")
        )
        XCTAssertEqual(
            CameraStatePanel.picker(tone: .empty, isNoMatch: true, term: "dancing", isOffline: true),
            .pickerNoMatch("dancing"),
            "an empty result keeps the no-match card even offline (guide-picker.js returns early)"
        )
    }

    /// The panel mounts the fixed rows through a `ForEach` and the results scroll content **directly**: the
    /// scroll view is the one flexible child, and a flexible child re-parented under a `ForEach` is proposed
    /// its height differently. The order is unchanged — `fixedRows + [.results] == order` — and what the panel
    /// actually paints is measured on a rendered screen
    /// (`CameraPickerSheetGeometryTests.testTheResultsFillThePanelBelowTheChips`).
    func testTheResultsAreMountedOutsideTheForEach() throws {
        XCTAssertEqual(PosePickerLayout.fixedRows + [.results], PosePickerLayout.order)

        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Features/Camera/CameraFeature.swift"),
            encoding: .utf8
        )
        let panelStart = try XCTUnwrap(source.range(of: "private func panel(height: CGFloat)")?.upperBound)
        let panel = source[panelStart...].prefix(700)
        XCTAssertTrue(
            panel.contains("ForEach(PosePickerLayout.fixedRows"),
            "the fixed rows are the ones the ForEach iterates"
        )
        XCTAssertFalse(
            panel.contains("ForEach(PosePickerLayout.order"),
            "the results are not iterated with them"
        )
        XCTAssertTrue(
            panel.contains("scrollContent\n                .frame(maxHeight: .infinity)"),
            "the scroll content is a direct, flexible child of the panel's VStack"
        )
    }

    /// The offline notice is a row of the scroll content above the grid, never an overlay: it pushes the
    /// grid down, so it cannot cover the third row of cards.
    func testTheOfflineBannerIsAScrollRowAboveTheGrid() {
        XCTAssertEqual(PosePickerLayout.contentOrder, [.offlineBanner, .statePanel, .grid])
        let banner = PosePickerLayout.contentOrder.firstIndex(of: .offlineBanner)
        let grid = PosePickerLayout.contentOrder.firstIndex(of: .grid)
        XCTAssertLessThan(banner ?? .max, grid ?? .min, "the banner is above the grid, in the same flow")
    }

    /// Selecting a pose is the sheet's whole purpose: the reference becomes the guide and the sheet
    /// closes, so the user is back on the framing they were about to shoot.
    ///
    /// The close is the camera's own dismissal on the model the screen reads (`showPosePicker`), not a
    /// stand-in flag: the sheet is opened first, so this is the same open → pick → closed path a tap runs.
    func testSelectingAPoseSetsTheGuideAndClosesTheSheet() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.openPosePicker()
        XCTAssertTrue(model.showPosePicker, "the sheet is open before the pick")

        var guide: NativePose?
        let binding = Binding(get: { guide }, set: { guide = $0 })
        let chosen = NativePose(
            id: "pick-me",
            name: "Pick Me",
            category: "Standing",
            imageURL: nil,
            instructions: [],
            isSaved: false
        )

        CameraPickerSelection.select(chosen, guide: binding, camera: model)

        XCTAssertEqual(guide?.id, "pick-me", "the chosen pose is the camera's reference")
        XCTAssertFalse(model.showPosePicker, "and the sheet closes on the same tap")
        XCTAssertTrue(model.isPoseGuideVisible, "the reference the user picked is the one on screen")
    }

    /// Source-level: the two joins the wrapper cannot prove — the sheet's row tap calls its `onSelect`, and
    /// the screen's `onSelect` runs the selection above on its own guide binding and model.
    ///
    /// Mutation target: call something else from `onSelect`, or stop passing the pose from the row — each
    /// turns one assertion below red.
    func testTheRowTapReachesTheScreenWiredSelection() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Features/Camera/CameraFeature.swift"),
            encoding: .utf8
        )

        let gridStart = try XCTUnwrap(source.range(of: "var poseGrid: some View {")?.upperBound)
        let grid = source[gridStart...].prefix(1_200)
        XCTAssertTrue(
            grid.contains("onSelect(item.pose)"),
            "a row tap hands the sheet's callback that row's pose"
        )

        let sheetStart = try XCTUnwrap(source.range(of: "PosePickerSheet(")?.upperBound)
        let sheet = source[sheetStart...].prefix(700)
        XCTAssertTrue(sheet.contains("onSelect: { pose in"), "the sheet is given the screen's selection")
        XCTAssertTrue(
            sheet.contains("CameraPickerSelection.select(pose, guide: $guide, camera: model)"),
            "and that selection is the one above, on the screen's own guide binding and model"
        )
    }

    /// The Saved chip's no-match card: the query matched none of the account's loaded rows, so the sheet
    /// draws the shared no-match state instead of a blank area under the chips — and a collection that has
    /// not answered yet keeps its own panel.
    func testTheSavedScopeTurnsAnEmptyResultIntoTheNoMatchCard() throws {
        let rows = [
            NativePose(
                id: "b",
                name: "City walk",
                category: "Standing",
                imageURL: nil,
                instructions: [],
                isSaved: true
            ),
        ]

        XCTAssertTrue(
            CameraSavedScopePresentation.savedHasNoMatch(
                presentation: .rows(rows),
                rows: [],  // the query filtered every loaded row out
                query: "warrior"
            ),
            "a loaded collection with no match is the no-match card"
        )
        XCTAssertFalse(
            CameraSavedScopePresentation.savedHasNoMatch(presentation: .rows(rows), rows: [], query: "   "),
            "an empty query is not a search: the grid is the answer"
        )
        XCTAssertFalse(
            CameraSavedScopePresentation.savedHasNoMatch(
                presentation: .rows(rows),
                rows: CameraPickerScope.saved.rows(catalogue: [], saved: rows, query: "walk"),
                query: "walk"
            ),
            "a query that matches keeps the rows"
        )
        XCTAssertFalse(
            CameraSavedScopePresentation.savedHasNoMatch(presentation: .signInRequired, rows: [], query: "walk"),
            "a guest sees the sign-in panel, not \"nothing matched\""
        )
        XCTAssertFalse(
            CameraSavedScopePresentation.savedHasNoMatch(presentation: .loading, rows: [], query: "walk"),
            "a load in flight is not an empty result"
        )
        XCTAssertFalse(
            CameraSavedScopePresentation.savedHasNoMatch(presentation: .empty, rows: [], query: "walk"),
            "an empty collection has its own copy: there is nothing to search yet"
        )

        // And the sheet draws the card from that one rule instead of keeping a copy of the condition.
        let source = try source()
        XCTAssertTrue(
            source.contains("CameraSavedScopePresentation.savedHasNoMatch("),
            "the sheet's no-match card reads the rule above"
        )
        XCTAssertTrue(
            source.contains(".pickerNoMatch(trimmedQuery)"),
            "and draws the shared no-match card with the query in its copy"
        )
    }

    private func source() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Features/Camera/CameraFeature.swift"),
            encoding: .utf8
        )
    }
}

// MARK: - Camera tools popover (owner feedback: no title, no Done)

@MainActor
final class CameraToolsPopoverTests: XCTestCase {
    /// Every control applies and persists on change — there is no Done to defer it, so the popover
    /// being open must not hold a setting back.
    func testAChangePersistsWhileThePopoverIsStillOpen() async throws {
        let store = InMemoryCameraSettingsStore(seed: CameraSettings())
        let model = CameraViewModel(settingsStore: store, saveDebounceNanoseconds: 1_000_000)
        await waitUntil { model.initialMergeDone }
        model.coordinator.onPermissionResult(.authorized)
        model.openCameraTools()
        XCTAssertTrue(model.showCameraTools, "the popover is open for the whole test")

        model.setFlash(.on)
        model.toggleGrid()
        model.setTimerSetting(.threeSeconds)
        model.setAspectRatio(.oneOne)
        // The guide's own controls live in the adjust sheet now, and it has no Done either.
        model.setGuideOpacity(0.8)
        model.setGuideScale(1.5)
        model.toggleGuideMirror()

        await waitUntil { await store.saved.last?.aspectRatio == .oneOne }
        let writes = await store.saved
        let saved = try XCTUnwrap(writes.last)
        XCTAssertEqual(saved.flash, model.flashSetting)
        XCTAssertTrue(saved.isGridVisible)
        XCTAssertTrue(saved.guideFlipped, "Mirror persists on change")
        XCTAssertEqual(saved.guideOpacity, 0.8, accuracy: 0.0001)
        XCTAssertEqual(saved.timer, .threeSeconds)
        XCTAssertEqual(saved.aspectRatio, .oneOne)
        XCTAssertEqual(saved.transform.placement.scale, 1.5, accuracy: 0.0001)
        XCTAssertTrue(model.showCameraTools, "no dismiss step was needed to persist")
    }

    /// The popover dismisses by tapping outside or with VoiceOver's escape — both call this.
    func testDismissalIsTheOnlyCommitFreeWayOut() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.openCameraTools()
        XCTAssertTrue(model.showCameraTools)

        model.closeCameraTools()
        XCTAssertFalse(model.showCameraTools, "the popover's own escape/outside-tap action dismisses it")

        model.toggleCameraTools()
        XCTAssertTrue(model.showCameraTools, "the tools control still opens it")
        model.toggleCameraTools()
        XCTAssertFalse(model.showCameraTools, "and closes it")
    }

    /// The popover is exactly four one-line rows — Flash, Grid, Timer, Ratio — and nothing else: no title, no
    /// Done, no guide section. The guide's controls live in the adjust sheet, and the ids it used to expose are
    /// retired so no flow can address a row that no longer exists.
    func testThePopoverIsFourOneLineRows() {
        XCTAssertEqual(CameraToolsLayout.rows.map(\.rawValue), ["flash", "grid", "timer", "ratio"])
        XCTAssertEqual(
            CameraToolsLayout.controlIdentifiers,
            ["camera.tools.flash", "camera.tools.grid", "camera.tools.timer", "camera.tools.ratio"]
        )
        for retired in CameraToolsLayout.retiredIdentifiers {
            XCTAssertFalse(
                CameraToolsLayout.controlIdentifiers.contains(retired),
                "\(retired) is gone from the popover"
            )
        }
        XCTAssertTrue(CameraToolsLayout.retiredIdentifiers.contains("camera.tools.opacity"))
        XCTAssertTrue(CameraToolsLayout.retiredIdentifiers.contains("camera.tools.lineColor.black"))
        XCTAssertTrue(CameraToolsLayout.retiredIdentifiers.contains("camera.tools.done"))
    }

    /// The card's own geometry: the artboard's 232 pt, a caret pointing up at the tools control, and the card
    /// sitting a short gap under the measured top bar.
    func testThePopoverHangsUnderTheToolsControl() {
        XCTAssertEqual(CameraToolsLayout.width, 232)
        XCTAssertEqual(CameraToolsLayout.rowHeight, AP.HitTarget.minimum)
        XCTAssertEqual(
            CameraToolsLayout.caretCenterX(),
            CameraToolsLayout.width - AP.HitTarget.minimum / 2,
            "the caret is centred on the control it points at"
        )
        XCTAssertEqual(CameraToolsLayout.cardTop(belowTopBar: 103), 103 + AP.Space.space4)
        XCTAssertEqual(
            CameraToolsLayout.height,
            CameraToolsLayout.caret.height + 4 * AP.HitTarget.minimum + 3,
            "the caret plus four 44 pt rows and their hairlines"
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

// MARK: - Camera chrome: picker entry, F4 state panels, F5 snackbar

/// The redesign slice's own evidence: the picker's single entry point, the shared 72 pt state panels
/// and the snackbar's placement above the control bar.
///
/// Constants are not read back here: the entry contract is asserted through the view model and the pure
/// layout mapping, and what the chrome *draws* is asserted on a rendered bitmap, pinned to one
/// appearance at a time (light and dark, the same token pairs the design system documents).
@MainActor
final class CameraChromeTests: XCTestCase {
    private func pose(_ id: String, name: String) -> NativePose {
        NativePose(id: id, name: name, category: "Standing", imageURL: nil, instructions: [], isSaved: false)
    }

    // MARK: - The picker is always a sheet (no strip, no collapse)

    /// The old collapse/expand product is gone: there is no state to collapse, so the only picker action
    /// is "open the sheet", and a camera that cannot serve it does not open it.
    func testTheOnlyPickerActionIsOpeningTheSheet() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)

        XCTAssertFalse(model.showPosePicker)
        model.openPosePicker()
        XCTAssertTrue(model.showPosePicker)
        model.closePosePicker()
        XCTAssertFalse(model.showPosePicker)

        let denied = CameraViewModel()
        denied.coordinator.onPermissionResult(.denied)
        denied.openPosePicker()
        XCTAssertFalse(denied.showPosePicker, "a control the camera cannot serve must not move the state")
    }

    /// Opening the sheet must not also hide the pose reference: the guide keeps its own eye control, and
    /// the sheet is an overlay, not a different camera state.
    func testOpeningTheSheetKeepsThePoseGuideVisible() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        XCTAssertTrue(model.isPoseGuideVisible)

        model.openPosePicker()

        XCTAssertTrue(model.isPoseGuideVisible, "opening the picker is not the guide-visibility toggle")
    }

    /// The bottom surface is snackbar · scale row · rail, in that order. What it *draws* (no catalogue, no
    /// strip) is asserted structurally on the rendered bar and on the screen's own source
    /// (`CameraChromeContractTests.testThePosesControlOpensTheSheetAndTheStripIsGone`); reading a retired-id
    /// list back at itself proves nothing.
    func testTheBottomSurfaceKeepsItsOrder() {
        XCTAssertEqual(CameraChromeLayout.bottomSurfaceOrder, [.snackbar, .scaleRow, .panel])
    }

    // MARK: - Persistence of the retired strip state

    /// Rows written while the strip existed still decode: `isPickerExpanded` is a dead field the codec
    /// keeps reading, so an old snapshot cannot crash or blank the camera's settings.
    func testARowFromTheStripEraStillDecodes() throws {
        let old = try XCTUnwrap(
            CameraSettings.decode(#"{"guideOpacity":0.8,"isPickerExpanded":false,"zoom":2}"#)
        )
        XCTAssertEqual(old.guideOpacity, 0.8, accuracy: 0.001)
        XCTAssertEqual(old.zoom, .two)
        XCTAssertFalse(old.isPickerExpanded, "the dead field is preserved, not crashed on")
        XCTAssertTrue(CameraSettings().isPickerExpanded, "and a fresh row keeps the codec's default")
    }

    /// A stored row that carries the dead field does not stop the camera from restoring what still
    /// matters — the strip state is simply not part of the screen any more.
    func testAStripEraRowStillRestoresTheSettingsThatMatter() async throws {
        let store = InMemoryCameraSettingsStore(
            seed: CameraSettings(guideOpacity: 0.25, isPickerExpanded: false)
        )
        let model = CameraViewModel(settingsStore: store, saveDebounceNanoseconds: 1_000_000)

        await waitUntil { model.initialMergeDone }

        XCTAssertEqual(model.guideOpacity, 0.25, accuracy: 0.001)
        XCTAssertFalse(model.showPosePicker, "a restored camera still opens on the camera, not on the sheet")
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

    // MARK: - What the bottom surface draws

    private static let bothSchemes: [ColorScheme] = [.dark, .light]

    /// The strip is gone: the bar draws the rail and one Poses chip, and it does not grow a catalogue row
    /// when a picker is available. Both appearances are pinned, so the assertion cannot pass on one
    /// scheme's token values alone.
    func testTheBarDrawsOnePosesChipAndNoCatalogueRow() throws {
        let size = CGSize(width: 393, height: 470)

        for scheme in Self.bothSchemes {
            let label = scheme == .dark ? "dark" : "light"
            let withPicker = chromeBitmap(bar(showsPicker: true), scheme: scheme, size: size)
            let noPicker = chromeBitmap(bar(showsPicker: false), scheme: scheme, size: size)

            // No strip row: the rail panel is exactly as tall with a picker as without one. Before, the
            // expanded state added the whole strip (cards + captions) to the panel.
            let panel = barPanelHex(scheme)
            XCTAssertEqual(
                panelRows(withPicker, hex: panel).count,
                panelRows(noPicker, hex: panel).count,
                "\(label): a picker on screen must not add a catalogue row to the bar"
            )

            // The Poses chip is the one wide controlFill pill on the scale row; the rail's controls are
            // 48 pt squares, so a run this long can only be the chip.
            let controlFill = hex(APColorTokens.controlFill, scheme)
            XCTAssertFalse(
                filledRows(withPicker, hex: controlFill, minRun: 70).isEmpty,
                "\(label): the Poses control is drawn on the scale row"
            )
            XCTAssertTrue(
                filledRows(noPicker, hex: controlFill, minRun: 70).isEmpty,
                "\(label): a camera that cannot place a pose draws no Poses control"
            )

            // And the shutter is reachable in both states.
            let shutter = hex(APColorTokens.accent, scheme)
            XCTAssertFalse(
                filledRows(withPicker, hex: shutter, minRun: 40).isEmpty,
                "\(label): the shutter stays reachable for QA"
            )
            XCTAssertFalse(
                filledRows(noPicker, hex: shutter, minRun: 40).isEmpty,
                "\(label): the shutter stays reachable for QA"
            )
        }
    }

    // MARK: - F5: the snackbar sits above the control bar

    /// F5: the snackbar is part of the bottom surface and sits directly above the control bar.
    ///
    /// Asserted as the bar's declared render order plus the model's status contract: the pixel band a
    /// snackbar paints is not a stable enough instrument while the shared components are being
    /// restyled underneath it, and the order is what F5 actually requires.
    func testSnackbarIsPinnedAboveTheControlBar() throws {
        XCTAssertEqual(
            CameraChromeLayout.bottomSurfaceOrder,
            [.snackbar, .scaleRow, .panel],
            "the snackbar is the first child of the bottom surface, so it can never land mid-screen"
        )

        let size = CGSize(width: 393, height: 540)
        let withStatus = chromeBitmap(bar(status: "Photo saved"), scheme: .dark, size: size)
        let withoutStatus = chromeBitmap(bar(status: nil), scheme: .dark, size: size)

        XCTAssertFalse(
            filledRows(withStatus, hex: hex(APColorTokens.surface, .dark), minRun: 300).isEmpty,
            "the message is drawn as a snackbar surface"
        )
        XCTAssertTrue(
            filledRows(withoutStatus, hex: hex(APColorTokens.surface, .dark), minRun: 300).isEmpty,
            "no message, no snackbar"
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
        selectedPoseID: String? = nil,
        selectedPoseName: String? = nil,
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
            timerCountdown: nil,
            selectedPoseID: selectedPoseID,
            selectedPoseName: selectedPoseName,
            showsPicker: showsPicker,
            zoomFactor: 1,
            zoomRange: 1...2,
            onOpenPosePicker: {},
            onZoomChange: { _ in },
            onOpenGallery: {},
            onCapture: {},
            onSwitchCamera: {},
            onDismissStatus: {},
            onCancelTimer: {},
            safeBottom: 34
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

    /// The bottom bar's fill: black at 50% over the screen background (owner feedback, build 18).
    private func barPanelHex(_ scheme: ColorScheme) -> UInt32 {
        let background = hex(APColorTokens.background, scheme)
        let red = ((background >> 16) & 0xFF) / 2
        let green = ((background >> 8) & 0xFF) / 2
        let blue = (background & 0xFF) / 2
        return (red << 16) | (green << 8) | blue
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
    /// Rows that paint a run of `hex` at least `minRun` pixels long, **bounded on both sides** by a different
    /// pixel. A control has edges: a background band that runs to the screen's edge is never one, which is what
    /// keeps a gradient that drifts within tolerance of a token from reading as a chip.
    private func filledRows(_ bitmap: APBitmap, hex: UInt32, minRun: Int, tolerance: Int = 6) -> [Int] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var rows: [Int] = []
        for y in 0..<bitmap.height {
            var runStart: Int?
            var longestBounded = 0
            for x in 0...bitmap.width {
                var matches = false
                if x < bitmap.width, let pixel = bitmap.color(x: x, y: y), pixel.alpha > 200 {
                    matches = abs(pixel.red - target.red) <= tolerance
                        && abs(pixel.green - target.green) <= tolerance
                        && abs(pixel.blue - target.blue) <= tolerance
                }
                if matches {
                    if runStart == nil { runStart = x }
                } else if let start = runStart {
                    if start > 0, x < bitmap.width {
                        longestBounded = max(longestBounded, x - start)
                    }
                    runStart = nil
                }
            }
            if longestBounded >= minRun { rows.append(y) }
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
        let rows = filledRows(bitmap, hex: hex(APColorTokens.selectedBackground, scheme), minRun: 8)
        try XCTUnwrap(rows.min(), "\(label): no accent-tint state tile painted", file: file, line: line)
        let last = try XCTUnwrap(rows.max(), file: file, line: line)
        let belowCircle = band(last + 1, bitmap.height, in: bitmap)
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

// MARK: - Mirror (pose guide)

@MainActor
final class CameraGuideMirrorTests: XCTestCase {
    /// Mirror flips the *pose guide* — the reference the user lines up against — because that is the
    /// setting the camera has persisted since FEAT-012 without a control, and `tokens.md` pins the
    /// guide flip's motion ("guide flip mirrors with a turn").
    func testMirrorFlipsThePoseGuideAndIsGated() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        XCTAssertFalse(model.guideFlipped, "the guide starts unmirrored")

        model.toggleGuideMirror()
        XCTAssertTrue(model.guideFlipped, "Mirror flips the pose reference")
        model.toggleGuideMirror()
        XCTAssertFalse(model.guideFlipped)

        let denied = CameraViewModel()
        denied.coordinator.onPermissionResult(.denied)
        denied.toggleGuideMirror()
        XCTAssertFalse(denied.guideFlipped, "a control the camera cannot serve does not move the state")
    }

    /// The flip is what the render path applies (`scaleEffect(x: guideFlipped ? -1 : 1)`), and it is
    /// persisted with the other guide settings.
    func testTheFlippedStateRoundTripsWithTheCameraSettings() throws {
        var settings = CameraSettings()
        settings.guideFlipped = true
        let decoded = try XCTUnwrap(CameraSettings.decode(try settings.encodedJSON()))
        XCTAssertTrue(decoded.guideFlipped)
    }
}

// MARK: - Timer (shutter countdown)

final class CameraTimerMachineTests: XCTestCase {
    func testWithoutATimerThePressCapturesAtOnce() {
        var machine = CameraTimerMachine()
        machine.setting = .off
        XCTAssertEqual(machine.shutterPressed(isReady: true), .captureNow)
        XCTAssertEqual(machine.phase, .capturing)

        var notReady = CameraTimerMachine()
        XCTAssertEqual(notReady.shutterPressed(isReady: false), .ignored, "an unready camera never captures")
    }

    func testTheCountdownFiresExactlyOnce() {
        var machine = CameraTimerMachine()
        machine.setting = .threeSeconds

        XCTAssertEqual(machine.shutterPressed(isReady: true), .countdownStarted(remaining: 3))
        XCTAssertEqual(machine.tick(), .countdownAdvanced(remaining: 2))
        XCTAssertEqual(machine.tick(), .countdownAdvanced(remaining: 1))
        XCTAssertEqual(machine.tick(), .captureNow, "the tick that reaches zero is the capture")
        XCTAssertEqual(machine.phase, .capturing)
        XCTAssertEqual(machine.tick(), .ignored, "a capture in flight is never fired again")

        machine.captureFinished()
        XCTAssertEqual(machine.phase, .ready, "the next press starts from scratch")
    }

    func testASecondPressDuringTheCountdownIsIgnored() {
        var machine = CameraTimerMachine()
        machine.setting = .tenSeconds
        XCTAssertEqual(machine.shutterPressed(isReady: true), .countdownStarted(remaining: 10))
        XCTAssertEqual(machine.shutterPressed(isReady: true), .ignored, "never a double capture")
        XCTAssertEqual(machine.shutterPressed(isReady: false), .ignored)
        XCTAssertEqual(machine.remainingSeconds, 10, "the running countdown is untouched")
    }

    func testCancelReturnsToReadyWithoutCapturing() {
        var machine = CameraTimerMachine()
        machine.setting = .threeSeconds
        _ = machine.shutterPressed(isReady: true)

        XCTAssertTrue(machine.cancel())
        XCTAssertEqual(machine.phase, .ready)
        XCTAssertFalse(machine.cancel(), "nothing to cancel when ready")
        XCTAssertFalse(machine.isCountingDown)
    }
}

@MainActor
final class CameraTimerModelTests: XCTestCase {
    func testTheShutterWaitsForTheCountdownAndCancelTakesNoPhoto() {
        let model = CameraViewModel(premiumGate: StubPremiumGate(.capture))
        model.coordinator.onPermissionResult(.authorized)
        model.setTimerSetting(.threeSeconds)

        model.capture()
        XCTAssertEqual(model.timerCountdown, 3, "the countdown is visible")
        XCTAssertFalse(model.coordinator.state.isCaptureInFlight, "nothing is captured before it ends")

        model.capture()
        XCTAssertEqual(model.timerCountdown, 3, "a second press is ignored, not a second capture")
        XCTAssertFalse(model.coordinator.state.isCaptureInFlight)

        model.cancelTimer()
        XCTAssertNil(model.timerCountdown)
        XCTAssertFalse(model.coordinator.state.isCaptureInFlight, "cancel takes no photo")
    }

    func testThePaywallStillWinsOverTheTimer() {
        let gate = StubPremiumGate(.paywall(signIn: false))
        var prompts: [Bool] = []
        let model = CameraViewModel(premiumGate: gate, onPremiumRequired: { prompts.append($0) })
        model.coordinator.onPermissionResult(.authorized)
        model.setTimerSetting(.threeSeconds)

        model.capture()

        XCTAssertEqual(prompts, [false], "the gate is still the first thing a press meets")
        XCTAssertNil(model.timerCountdown, "no countdown starts for a gated press")
    }

    func testTheTimerSettingIsGated() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        model.setTimerSetting(.tenSeconds)
        XCTAssertEqual(model.timerSetting, .off, "a control the camera cannot serve does not move")
    }
}

// MARK: - Ratio (saved capture aspect)

final class CameraAspectCropTests: XCTestCase {
    func testAThreeByFourCaptureNeedsNoCrop() {
        let size = CGSize(width: 3000, height: 4000)
        XCTAssertEqual(CameraAspectCrop.rect(for: .threeFour, imageSize: size), CGRect(origin: .zero, size: size))
        XCTAssertFalse(CameraAspectCrop.needsCrop(ratio: .threeFour, imageSize: size))
    }

    func testASquareCropIsCentredAndFullHeight() {
        let size = CGSize(width: 3000, height: 4000)
        XCTAssertEqual(
            CameraAspectCrop.rect(for: .oneOne, imageSize: size),
            CGRect(x: 0, y: 500, width: 3000, height: 3000)
        )
        XCTAssertTrue(CameraAspectCrop.needsCrop(ratio: .oneOne, imageSize: size))
    }

    func testAStoryCropTrimsTheSides() {
        let size = CGSize(width: 3000, height: 4000)
        // 9:16 is narrower than 3:4, so the width gives way and the height is kept.
        XCTAssertEqual(
            CameraAspectCrop.rect(for: .nineSixteen, imageSize: size),
            CGRect(x: 375, y: 0, width: 2250, height: 4000)
        )
    }

    func testALandscapeCaptureIsCroppedToThePortraitRatio() {
        let size = CGSize(width: 4000, height: 3000)
        XCTAssertEqual(
            CameraAspectCrop.rect(for: .threeFour, imageSize: size),
            CGRect(x: 875, y: 0, width: 2250, height: 3000)
        )
    }

    func testDegenerateSizesDoNotCrash() {
        XCTAssertEqual(CameraAspectCrop.rect(for: .oneOne, imageSize: .zero), .zero)
    }

    /// The saved file really is cropped (dimensions asserted on the written JPEG, no device needed).
    func testTheSavedFileIsCroppedToTheChosenRatio() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("crop-\(UUID().uuidString).jpg")
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(CameraImagePostProcess.cropFileInPlace(at: url.path, ratio: .oneOne))

        let saved = try XCTUnwrap(UIImage(data: try Data(contentsOf: url))?.cgImage)
        XCTAssertEqual(saved.width, 300, "1:1 keeps the short side")
        XCTAssertEqual(saved.height, 300)
    }

    func testACaptureThatAlreadyMatchesIsNotRewritten() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400), format: format).image { _ in }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nocrop-\(UUID().uuidString).jpg")
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let before = try Data(contentsOf: url)

        XCTAssertFalse(CameraImagePostProcess.cropFileInPlace(at: url.path, ratio: .threeFour))

        XCTAssertEqual(try Data(contentsOf: url), before, "a matching capture is left byte-identical")
    }
}

@MainActor
final class CameraAspectRatioModelTests: XCTestCase {
    func testTheRatioSettingIsGatedAndPersisted() throws {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        model.setAspectRatio(.oneOne)
        XCTAssertEqual(model.aspectRatio, .threeFour, "a control the camera cannot serve does not move")

        model.coordinator.onPermissionResult(.authorized)
        model.setAspectRatio(.nineSixteen)
        XCTAssertEqual(model.aspectRatio, .nineSixteen)

        var settings = CameraSettings()
        settings.aspectRatio = .oneOne
        XCTAssertEqual(try XCTUnwrap(CameraSettings.decode(try settings.encodedJSON())).aspectRatio, .oneOne)
    }

    func testTheRatioIdentifiersAreTheQaContract() {
        XCTAssertEqual(CameraAspectRatio.threeFour.accessibilityIdentifier, "camera.tools.ratio.3x4")
        XCTAssertEqual(CameraAspectRatio.oneOne.accessibilityIdentifier, "camera.tools.ratio.1x1")
        XCTAssertEqual(CameraAspectRatio.nineSixteen.accessibilityIdentifier, "camera.tools.ratio.9x16")
    }
}

// MARK: - Scale (pose reference size) and lens-aware zoom presets

final class CameraGuideScaleTests: XCTestCase {
    func testScaleIsClampedToTheGuideRange() {
        XCTAssertEqual(CameraGuideScale.clamped(0.01), GuideTransform.scaleRange.lowerBound)
        XCTAssertEqual(CameraGuideScale.clamped(99), GuideTransform.scaleRange.upperBound)
        XCTAssertEqual(CameraGuideScale.clamped(.nan), 1, "a corrupt value falls back to 1×")
    }

    func testTheScaleLabelIsAPercentage() {
        XCTAssertEqual(CameraGuideScale.label(1), "100%")
        XCTAssertEqual(CameraGuideScale.label(1.5), "150%")
        XCTAssertEqual(CameraGuideScale.label(0.4), "40%")
        XCTAssertEqual(CameraGuideScale.label(9), "300%", "the label never leaves the range")
    }

    func testTheSliderStepsStayInsideTheRange() {
        XCTAssertEqual(CameraGuideScale.stepped(0.42), 0.4, accuracy: 0.0001)
        XCTAssertEqual(CameraGuideScale.stepped(1.53), 1.55, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(CameraGuideScale.stepped(0), GuideTransform.scaleRange.lowerBound)
        XCTAssertLessThanOrEqual(CameraGuideScale.stepped(9), GuideTransform.scaleRange.upperBound)
    }
}

/// The camera stage as the *screen* composes it: preview, dim, frame, chrome. The canvas has its own pixel
/// tests; this one drives the real screen, with the window's insets stated and a stand-in image where the
/// camera feed would be (a simulator has none), so "the preview is full screen and only the photo is
/// undimmed" is asserted on the thing the app actually shows.
@MainActor
final class CameraScreenStageTests: XCTestCase {
    private let phone = CameraSafeArea.Insets(top: 59, bottom: 34)
    private let size = CGSize(width: 393, height: 852)
    /// A bright stand-in for the photo: a dim over it is measurable, and so is leaving it alone.
    private let previewColour = Color(red: 1, green: 0, blue: 1)

    func testTheScreensPreviewIsFullBleedAndOnlyTheFrameIsUndimmed() throws {
        for ratio in CameraAspectRatio.allCases {
            let bitmap = try renderScreen(ratio: ratio)
            let frame = CameraStageFrame.make(ratio: ratio, screen: size, safeTop: phone.top).frame

            // Above the frame, clear of the top controls' buttons: the preview covers the whole screen and is
            // dimmed there — never an opaque bar, and never the plain background.
            let band = max(2, Int(frame.minY / 2))
            for x in [8, Int(size.width) - 8] {
                let pixel = try XCTUnwrap(bitmap.color(x: x, y: band))
                XCTAssertGreaterThan(pixel.red, 40, "\(ratio.rawValue) at (\(x), \(band)): the preview shows through")
                XCTAssertLessThan(pixel.red, 150, "\(ratio.rawValue) at (\(x), \(band)): and it is dimmed")
            }

            // Inside the frame the photo is untouched.
            let inside = try XCTUnwrap(
                bitmap.color(x: Int(frame.midX), y: Int(frame.midY)),
                "\(ratio.rawValue): the frame's middle is painted"
            )
            XCTAssertGreaterThan(inside.red, 200, "\(ratio.rawValue): the photo inside the frame is not dimmed")
        }
    }

    private func renderScreen(ratio: CameraAspectRatio) throws -> APBitmap {
        var guide: NativePose? = NativePose(
            id: "p1",
            name: "Warrior II",
            category: "Yoga",
            imageURL: nil,
            instructions: [],
            isSaved: false
        )
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.setAspectRatio(ratio)
        model.setGuideLineColor(.green)
        let screen = CameraScreen(
            guide: Binding(get: { guide }, set: { guide = $0 }),
            poseService: PreviewPoseService(),
            model: model,
            preview: AnyView(previewColour),
            windowInsets: phone
        )
        let host = UIHostingController(rootView: screen)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return try XCTUnwrap(APBitmap(image: image))
    }
}

/// The guide-adjust sheet: the reference's own controls, moved off the tools popover, over a live camera.
@MainActor
final class CameraGuideAdjustTests: XCTestCase {
    /// It opens only where there is something to adjust: a camera that works and a reference on screen.
    func testTheSheetNeedsACameraAndAReference() {
        let noCamera = CameraViewModel()
        noCamera.coordinator.onPermissionResult(.denied)
        noCamera.guideAppeared(hasGuide: true)
        noCamera.openGuideAdjust()
        XCTAssertFalse(noCamera.showGuideAdjust, "a camera that cannot serve it does not open the sheet")

        let noGuide = CameraViewModel()
        noGuide.coordinator.onPermissionResult(.authorized)
        noGuide.openGuideAdjust()
        XCTAssertFalse(noGuide.showGuideAdjust, "no reference, nothing to adjust")

        let ready = CameraViewModel()
        ready.coordinator.onPermissionResult(.authorized)
        ready.guideAppeared(hasGuide: true)
        ready.openGuideAdjust()
        XCTAssertTrue(ready.showGuideAdjust)
        ready.closeGuideAdjust()
        XCTAssertFalse(ready.showGuideAdjust, "Done closes it")
    }

    /// One surface at a time: the sheet, the picker and the popover never stack on each other.
    func testTheSheetAndTheOtherSurfacesAreExclusive() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.guideAppeared(hasGuide: true)

        model.openGuideAdjust()
        model.openPosePicker()
        XCTAssertFalse(model.showGuideAdjust, "the picker takes the screen")

        model.closePosePicker()
        model.openGuideAdjust()
        model.toggleCameraTools()
        XCTAssertFalse(model.showGuideAdjust, "and so does the tools popover")

        model.toggleCameraTools()
        model.openGuideAdjust()
        XCTAssertTrue(model.showGuideAdjust, "the reference reopens it")
    }

    /// The sheet's controls write the same state the gesture writes, and the palette is the sheet's four.
    func testTheSheetControlsWriteTheGuidelinesState() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.setGuideOpacity(0.6)
        XCTAssertEqual(model.guideOpacity, 0.6, accuracy: 0.0001)

        model.setGuideScale(1.8)
        XCTAssertEqual(model.guideTransform.scale, 1.8, accuracy: 0.0001, "the slider and the pinch share one value")

        model.setGuideLineColor(.green)
        XCTAssertEqual(model.guideLineColor, .green)

        model.toggleGuideMirror()
        XCTAssertTrue(model.guideFlipped, "Mirror guide flips the reference")
    }

    /// The palette is four swatches and `white` is not one of them; a stored row that still says `white` reads as
    /// the sheet's default (pink), which is what it meant before the palette existed.
    func testThePaletteIsFourSwatchesAndLegacyWhiteMigrates() {
        XCTAssertEqual(GuideLineColor.allCases.map(\.rawValue), ["pink", "black", "yellow", "green"])
        XCTAssertEqual(GuideLineColor.stored("white"), .pink)
        XCTAssertEqual(GuideLineColor.stored("neon"), nil)
        XCTAssertEqual(GuideLineColor.stored(nil), nil)
        XCTAssertEqual(GuideLineColor.stored("green"), .green)

        for color in GuideLineColor.allCases {
            XCTAssertEqual(
                color.accessibilityIdentifier,
                "camera.guideAdjust.lineColor.\(color.rawValue)",
                "each swatch has its own handle"
            )
        }
    }

    /// A row written before the palette existed still opens the camera with its own settings.
    func testALegacyWhiteRowStillDecodes() throws {
        let legacy = #"{"version":1,"lineColor":"white","guideOpacity":0.7}"#
        let decoded = try XCTUnwrap(CameraSettings.decode(legacy))
        XCTAssertEqual(decoded.lineColor, .pink)
        XCTAssertEqual(decoded.guideOpacity, 0.7, accuracy: 0.0001, "and its other settings survive")
    }

    /// The sheet draws its four controls: two sliders, the four swatches and the Mirror button, with Done in the
    /// header. Rendered on its own at the sheet's own size, so the measurement is of the sheet and not of the
    /// camera behind it.
    func testTheSheetDrawsOpacityLineColourScaleAndFlip() throws {
        let size = CGSize(width: 393, height: CameraGuideAdjustSheet.Layout.height)
        let sheet = CameraGuideAdjustSheet(
            opacity: 0.6,
            lineColor: .pink,
            scale: 1,
            isFlipped: false,
            isEnabled: true,
            onOpacityChange: { _ in },
            onLineColorChange: { _ in },
            onScaleChange: { _ in },
            onFlip: {},
            onDone: {}
        )
        .environment(\.colorScheme, .light)
        .background(AP.Color.background)
        let probe = APViewProbe(sheet, size: size, scale: 2)
        let bitmap = probe.capture()
        probe.tearDown()

        // The four swatches are painted, in the palette's own colours.
        for color in GuideLineColor.allCases {
            XCTAssertFalse(
                rowsPainted(bitmap, hex: resolvedHex(color.color), minRun: 30).isEmpty,
                "\(color.rawValue) swatch is drawn"
            )
        }

        // Two sliders: the accent track paints twice (Opacity and Scale), and the Mirror button is one wide
        // controlFill plate.
        let accent = APColorTokens.accent.spec(for: .light).hex ?? 0
        let controlFill = APColorTokens.controlFill.spec(for: .light).hex ?? 0
        let sliderBands = rowBands(rowsPainted(bitmap, hex: accent, minRun: 20))
        XCTAssertGreaterThanOrEqual(sliderBands, 2, "Opacity and Scale are both drawn as sliders")
        XCTAssertFalse(
            rowsPainted(bitmap, hex: controlFill, minRun: 120).isEmpty,
            "the Mirror guide button is drawn"
        )
    }

    // MARK: Helpers

    /// The hex a `Color` paints at, resolved in the light appearance the sheet is rendered in.
    private func resolvedHex(_ color: Color) -> UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (UInt32((red * 255).rounded()) << 16)
            | (UInt32((green * 255).rounded()) << 8)
            | UInt32((blue * 255).rounded())
    }

    private func rowsPainted(_ bitmap: APBitmap, hex: UInt32, minRun: Int) -> [Int] {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        var rows: [Int] = []
        for y in 0..<bitmap.height {
            var run = 0
            var longest = 0
            for x in 0..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y) else { run = 0; continue }
                let matches = abs(pixel.red - target.red) <= 6
                    && abs(pixel.green - target.green) <= 6
                    && abs(pixel.blue - target.blue) <= 6
                run = matches ? run + 1 : 0
                longest = max(longest, run)
            }
            if longest >= minRun { rows.append(y) }
        }
        return rows
    }

    /// How many separated row bands a list of rows forms.
    private func rowBands(_ rows: [Int]) -> Int {
        var bands = 0
        var previous: Int?
        for row in rows.sorted() {
            if let previous, row - previous <= 2 {
                // Same band.
            } else {
                bands += 1
            }
            previous = row
        }
        return bands
    }
}

/// The zoom slider's mapping: what it shows, what the lens receives, and where the thumb sits.
final class CameraZoomScaleTests: XCTestCase {
    /// The camera drives one wide-angle lens, so the displayed factor is the lens's own factor — the round trip
    /// has to be the identity inside the range and a clamp outside it.
    func testTheDisplayedFactorAndTheLensFactorRoundTrip() {
        let lens: ClosedRange<CGFloat> = 1...5
        for factor: CGFloat in [1, 1.4, 2, 3, 4.75, 5] {
            let device = CameraZoomScale.deviceFactor(forDisplay: factor, in: lens)
            XCTAssertEqual(device, factor, accuracy: 0.0001, "\(factor)x reaches the lens unchanged")
            XCTAssertEqual(
                CameraZoomScale.displayFactor(forDevice: device, in: lens),
                factor,
                accuracy: 0.0001,
                "and comes back to the same number on the pill"
            )
        }

        XCTAssertEqual(CameraZoomScale.deviceFactor(forDisplay: 0.2, in: lens), 1, "below the lens' floor")
        XCTAssertEqual(CameraZoomScale.deviceFactor(forDisplay: 9, in: lens), 5, "above the ramp's ceiling")
        XCTAssertEqual(
            CameraZoomScale.deviceFactor(forDisplay: .nan, in: lens), 1,
            "a corrupt value falls back to the lens' floor instead of an impossible one"
        )
    }

    /// A lens that really has the ultra-wide stop keeps it: the range is the device's, capped by the ramp.
    func testTheRangeIsTheLensRubyCappedByTheRamp() {
        XCTAssertEqual(CameraZoomScale.range(lower: 0.5, upper: 15.7), 0.5...CameraZoomScale.maxFactor)
        XCTAssertEqual(CameraZoomScale.range(lower: 1, upper: 2), 1...2)
        XCTAssertEqual(
            CameraZoomScale.range(lower: 2, upper: 1), 2...2,
            "an inverted report cannot make a range the thumb cannot sit in"
        )
    }

    /// The thumb's position and the value it stands for are one mapping, both ways.
    func testTheThumbPositionRoundTrips() {
        let range: ClosedRange<CGFloat> = 1...5
        XCTAssertEqual(CameraZoomScale.fraction(of: 1, in: range), 0, accuracy: 0.0001, "the left end")
        XCTAssertEqual(CameraZoomScale.fraction(of: 5, in: range), 1, accuracy: 0.0001, "the right end")
        XCTAssertEqual(CameraZoomScale.fraction(of: 3, in: range), 0.5, accuracy: 0.0001, "the middle")

        for factor: CGFloat in [1, 1.7, 2.5, 4.2, 5] {
            let x = CameraZoomScale.fraction(of: factor, in: range)
            XCTAssertEqual(
                CameraZoomScale.factor(atFraction: x, in: range), factor, accuracy: 0.0001,
                "\(factor)x sits where dragging to \(x) puts it"
            )
        }
        XCTAssertEqual(CameraZoomScale.factor(atFraction: -3, in: range), 1, "a drag past the end stops at it")
        XCTAssertEqual(CameraZoomScale.factor(atFraction: 7, in: range), 5)
    }

    func testTheLabelsNameTheFactorTheWayTheBoardsDo() {
        XCTAssertEqual(CameraZoomScale.valueLabel(1), "1×", "whole stops have no decimal, as on the boards")
        XCTAssertEqual(CameraZoomScale.valueLabel(0.5), "0.5×")
        XCTAssertEqual(CameraZoomScale.valueLabel(2.46), "2.5×")
        XCTAssertEqual(CameraZoomScale.accessibilityValue(1), "1.0×", "VoiceOver reads one decimal, never \"1x\"")
        XCTAssertEqual(CameraZoomScale.accessibilityValue(0.5), "0.5×")
        XCTAssertEqual(CameraZoomScale.accessibilityValue(3), "3.0×")
    }

    /// The wall of ticks comes from the same range the slider spans, so a label can never sit on a factor the
    /// thumb cannot reach.
    func testTheTicksComeFromTheSliderRange() {
        let lens = CameraZoomScale.range(lower: 0.5, upper: 5)
        XCTAssertEqual(CameraZoomScale.ticks(in: lens), [.half, .one, .two, .three])
        for tick in CameraZoomScale.ticks(in: lens) {
            XCTAssertTrue(lens.contains(tick.factor), "\(tick.factor) is reachable")
            XCTAssertTrue(
                (0...1).contains(CameraZoomScale.fraction(of: tick.factor, in: lens)),
                "\(tick.factor) sits on the track"
            )
        }
    }
}

final class CameraZoomPresetTests: XCTestCase {
    /// The slider's ticks are the stops the lens can actually reach: a phone without the ultra-wide never draws
    /// a 0.5 label, and a lens that starts at 2x never draws a 1.
    func testPresetsFollowTheLensRange() {
        XCTAssertEqual(
            CameraZoomPresets.available(range: 0.5...4),
            [.half, .one, .two, .three],
            "a lens with an ultra-wide stop offers 0.5x"
        )
        XCTAssertEqual(
            CameraZoomPresets.available(range: 1...2),
            [.one, .two],
            "a lens that cannot go below 1x never offers 0.5x"
        )
        XCTAssertEqual(CameraZoomPresets.available(range: 2...5), [.two, .three])
        XCTAssertEqual(CameraZoomPresets.available(range: 3...5), [.three])
        XCTAssertEqual(CameraZoomPresets.available(range: 4...4), [.one], "an empty wall of ticks still names 1x")
    }

    /// The 1x/2x pills are gone; the slider is the zoom control now, and the old pill handles are retired so no
    /// flow can address a control that no longer exists.
    func testTheZoomSliderIsTheOnlyZoomControl() {
        XCTAssertEqual(CameraZoomScale.sliderIdentifier, "camera.zoom.slider")
        XCTAssertTrue(
            CameraZoomScale.retiredIdentifiers.contains("camera.zoom.0.5x"),
            "the old pill spelling is kept as the retirement record"
        )
        for retired in CameraZoomScale.retiredIdentifiers {
            XCTAssertTrue(
                CameraChromeLayout.retiredIdentifiers.contains(retired),
                "\(retired) is retired in one list the chrome reads"
            )
        }
    }

    func testTheStoredLevelMatchesTheNearestFactor() {
        XCTAssertEqual(CameraZoomLevel.nearest(to: 0.5), .one, "the enum has no half stop")
        XCTAssertEqual(CameraZoomLevel.nearest(to: 2), .two)
        XCTAssertEqual(CameraZoomLevel.nearest(to: 2.7), .three)
    }
}

@MainActor
final class CameraGuideScaleModelTests: XCTestCase {
    func testTheScaleControlWritesTheSamePlacementThePinchWrites() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)

        model.setGuideScale(1.5)
        XCTAssertEqual(model.guideTransform.scale, 1.5, accuracy: 0.0001)

        model.resetGuideTransform()
        XCTAssertEqual(model.guideTransform.scale, 1, accuracy: 0.0001, "Reset returns the reference to 1×")
    }

    func testScaleIsGated() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.denied)
        model.setGuideScale(2)
        XCTAssertEqual(model.guideTransform.scale, 1, accuracy: 0.0001, "a control the camera cannot serve does not move")
    }

    /// The simulator has no capture device, so the lens range falls back to 1...2: the slider's ticks are 1x
    /// and 2x, and the 0.5x stop is simply not offered instead of being drawn and refused.
    func testTheSliderTicksAreLensAwareInTheSimulator() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)

        XCTAssertEqual(model.zoomRange, 1...2)
        XCTAssertEqual(CameraZoomScale.ticks(in: model.zoomRange), [.one, .two])

        model.setZoomFactor(2)
        XCTAssertEqual(model.zoomLevel, .two, "the stored level follows the factor for older readers")
        XCTAssertEqual(model.zoomFactor, 2, accuracy: 0.0001)
    }
}

// MARK: - Camera chrome contracts (one host per control · one picker entry · addressable option rows · a popover inside its safe area)

/// The camera chrome's own contracts, kept next to the screens they describe.
///
/// The assertions that need the *rendered* accessibility tree are source-level: SwiftUI does not
/// materialise that tree for a unit-test host (the same reason `JobRowAccessibilityTests` reads its
/// view source). Everything else is the pure layout logic the views are wired to.
@MainActor
final class CameraChromeContractTests: XCTestCase {
    // MARK: One Poses control

    /// The Poses control belongs to the scale row only, and it is drawn there exactly once. It used to
    /// be drawn in the bottom panel as well, so the camera offered two identical buttons and VoiceOver
    /// read the toggle twice.
    func testTheChromeDrawsThePosesControlInOnePlace() throws {
        let source = try cameraFeatureSource()
        let panel = try viewBody(named: "panel", in: source)
        let scaleRow = try viewBody(named: "scaleRow", in: source)

        XCTAssertFalse(
            panel.contains("posesControl"),
            "the panel does not host the Poses control: the scale row is its one home"
        )
        XCTAssertEqual(
            scaleRow.components(separatedBy: "posesControl").count - 1, 1,
            "the scale row draws exactly one Poses control"
        )
        XCTAssertEqual(
            source.components(separatedBy: .newlines)
                .filter { $0.trimmingCharacters(in: .whitespaces) == "posesControl" }
                .count,
            1,
            "one render site for the control: the declaration is not a second one"
        )
    }

    // MARK: The picker's one entry

    /// The inline strip is gone, so the Poses control is the sheet's only entry — and it opens the sheet
    /// directly. There is no strip left for the control to expand, and no second, weaker list of poses in
    /// the bottom bar that could drift from the sheet's.
    func testThePosesControlOpensTheSheetAndTheStripIsGone() throws {
        let source = try cameraFeatureSource()
        let scaleRow = try viewBody(named: "scaleRow", in: source)
        let panel = try viewBody(named: "panel", in: source)
        let control = try viewBody(named: "posesControl", in: source)

        XCTAssertTrue(scaleRow.contains("posesControl"), "the scale row hosts the control")
        XCTAssertTrue(control.contains("onOpenPosePicker"), "and the control opens the picker sheet")
        XCTAssertFalse(source.contains("stripView"), "no strip view is declared")
        XCTAssertFalse(source.contains("CameraStripContent"), "no strip content mapping is declared")
        XCTAssertFalse(source.contains("togglePickerStrip"), "there is no collapse/expand action to call")
        XCTAssertFalse(panel.contains("poses"), "the panel draws the rail only, no catalogue row")
    }

    // MARK: The sheet's own handles

    /// The sheet's surface and each pose row carry their own id, so a flow can assert "the sheet is open"
    /// and pick a *specific* pose. They live on the panel (a real container) and on the row buttons, never
    /// on the sheet's `GeometryReader` root, which is not an accessibility element — an id there collapses
    /// the subtree it wraps and takes the search field and header out of the tree.
    func testTheSheetAndItsRowsCarryTheirOwnIdentifiers() throws {
        let source = try cameraFeatureSource()
        let grid = try viewBody(named: "poseGrid", in: source)

        // The sheet's panel is the container that carries the modal trait; the id belongs on it, so the
        // two declarations are adjacent (`viewBody(named: "panel")` cannot be used here: the bottom bar
        // has its own `panel`).
        XCTAssertTrue(
            source.contains(
                ".accessibilityAddTraits(.isModal)\n        .accessibilityIdentifier(PosePickerLayout.sheetIdentifier)"
            ),
            "the sheet panel is the element that owns the sheet id"
        )
        XCTAssertTrue(
            grid.contains("PosePickerLayout.rowIdentifier(poseID: item.pose.id)"),
            "each grid row is addressable by its pose id"
        )
        XCTAssertTrue(
            grid.contains("Use \\(item.pose.name) pose"),
            "and the row keeps the label the flows already tap"
        )
        XCTAssertEqual(
            source.components(separatedBy: "PosePickerLayout.sheetIdentifier").count - 1,
            1,
            "one place owns the sheet id: the panel, not the GeometryReader root"
        )
    }

    // MARK: Container ids never swallow their children

    /// SwiftUI hands a container's `accessibilityIdentifier` down to the elements inside it, so an id put
    /// on a row without `.accessibilityElement(children: .contain)` *overwrites* every child's own id. The
    /// scope chips were exactly that: the row's `posePicker.scope` replaced `posePicker.scope.all|saved`, so
    /// the chips rendered but no flow could address them. This pins the declaration order — container
    /// first, id second — for every sheet row that carries an id over interactive children.
    func testTheSheetRowsDeclareContainBeforeTheirContainerId() throws {
        let source = try cameraFeatureSource()
        try assertContainPrecedesContainerId(
            after: "var scopeChips: some View {",
            identifier: ".accessibilityIdentifier(\"posePicker.scope\")",
            in: source
        )
        try assertContainPrecedesContainerId(
            after: "var poseGrid: some View {",
            identifier: ".accessibilityIdentifier(PosePickerLayout.gridIdentifier)",
            in: source
        )
        try assertContainPrecedesContainerId(
            after: "private func pickerPanel(",
            identifier: ".accessibilityIdentifier(PosePickerLayout.stateIdentifier)",
            in: source
        )
    }

    // MARK: Everything that belongs to the photo is clipped to it

    /// The canvas is bigger than the photo: a 9:16 frame leaves bars above and below, and they are not part
    /// of the picture the shutter saves. So the scrims must be measured against the frame (they grade the
    /// photo, not the screen), the pinch/drag catcher is the frame (a drag that starts on the bars is
    /// outside the picture), and the guide's layer is clipped to the frame *before* it is positioned —
    /// `.position` makes a view take all the space offered, so a clip after it cuts at the canvas edge and
    /// the guide still reaches the bars.
    ///
    /// Source-level because the geometry a gesture would take is not observable in a unit-test host; what
    /// the pixels look like is asserted on a rendered canvas in `CameraCanvasFramingTests`.
    ///
    /// Mutation target: move `.clipped()` after `.position`, drop the scrims' frame, or let the catcher
    /// stay canvas-sized — each turns one assertion below red.
    func testTheDimTheEdgeAndTheGuideAreBoundedByThePhoto() throws {
        let canvas = try cameraCanvasSource()
        let frameSize = ".frame(width: frame.width, height: frame.height)"

        // One dim layer over everything the photo leaves out — never four strips, never an opaque bar.
        let dimStart = try XCTUnwrap(canvas.range(of: "CameraStageFrameMask(frame: frame)")?.lowerBound)
        let dim = canvas[dimStart...].prefix(260)
        XCTAssertTrue(
            dim.contains("Color.black.opacity(CameraStageFrame.dimOpacity)"),
            "the outside is one translucent black layer at the stage's own opacity"
        )
        XCTAssertTrue(dim.contains("eoFill: true"), "a rect with a hole, so the photo inside is untouched")
        XCTAssertTrue(dim.contains(".allowsHitTesting(false)"), "and it never eats a gesture meant for the photo")

        // The pinch/twist/drag catcher is the photo.
        let catcherStart = try XCTUnwrap(canvas.range(of: "Color.clear")?.lowerBound)
        let catcher = canvas[catcherStart...].prefix(400)
        XCTAssertTrue(catcher.contains(frameSize), "the gesture area is the photo")
        let catcherFrame = try XCTUnwrap(catcher.range(of: frameSize))
        let catcherShape = try XCTUnwrap(catcher.range(of: ".contentShape(Rectangle())"))
        XCTAssertLessThan(
            catcher.distance(from: catcher.startIndex, to: catcherFrame.lowerBound),
            catcher.distance(from: catcher.startIndex, to: catcherShape.lowerBound),
            "the touch area is shaped by the frame, so the dimmed area stays inert"
        )

        // The guide's clip, in the order that actually clips.
        let guideStart = try XCTUnwrap(canvas.range(of: "guideOverlay(for: guide)")?.lowerBound)
        let guide = canvas[guideStart...].prefix(900)
        let clip = try XCTUnwrap(guide.range(of: ".clipped()"), "the guide layer is clipped to the photo")
        let position = try XCTUnwrap(guide.range(of: ".position(x: frame.midX, y: frame.midY)"))
        XCTAssertLessThan(
            guide.distance(from: guide.startIndex, to: clip.lowerBound),
            guide.distance(from: guide.startIndex, to: position.lowerBound),
            "clip before position: after it, the clip is the canvas edge and the guide paints on the bars"
        )
    }

    // MARK: The Poses control names the pose it holds

    /// The strip that used to draw the chosen pose's name is retired, so the control's *value* is the only
    /// place left that says which reference is up. It said "Selected" — true of any pose, and no use to a
    /// VoiceOver user lining up against the guide.
    func testThePosesControlValueIsTheSelectedPoseName() {
        XCTAssertEqual(CameraChromeLayout.posesControlValue(selectedPoseName: "Warrior II"), "Warrior II")
        XCTAssertEqual(
            CameraChromeLayout.posesControlValue(selectedPoseName: "  Tree Pose \n"),
            "Tree Pose",
            "the name is announced as written, not padded"
        )
        XCTAssertEqual(CameraChromeLayout.posesControlValue(selectedPoseName: nil), "None selected")
        XCTAssertEqual(
            CameraChromeLayout.posesControlValue(selectedPoseName: "   "),
            "None selected",
            "a blank name is no name: the control does not announce nothing at all"
        )
        XCTAssertNotEqual(
            CameraChromeLayout.posesControlValue(selectedPoseName: "Warrior II"),
            "Selected",
            "the value names the pose, it does not restate that something is selected"
        )
    }

    /// Source-level, like the picker ids pin below: a hosted SwiftUI view exposes no accessibility tree in
    /// this test host, so the wiring from the guide to the announcement is what is checked.
    ///
    /// Mutation target: put `.accessibilityValue(... = "Selected")` back, or pass only `guide?.id` from the
    /// screen — each turns one assertion below red.
    func testTheControlWiresThePoseNameIntoItsValue() throws {
        let source = try cameraFeatureSource()
        let control = try viewBody(named: "posesControl", in: source)
        XCTAssertTrue(
            control.contains(
                ".accessibilityValue(CameraChromeLayout.posesControlValue(selectedPoseName: selectedPoseName))"
            ),
            "the control announces the reference it holds, through the one rule"
        )
        XCTAssertFalse(
            control.contains("\"Selected\""),
            "and no longer announces the word that says nothing"
        )

        let bottomChrome = try viewBody(named: "bottomChrome", in: source)
        XCTAssertTrue(
            bottomChrome.contains("selectedPoseName: guide?.name"),
            "the bar is handed the name, not only the id"
        )
    }

    /// `contain` must be declared before the id in a view body, or the id is inherited by every child.
    private func assertContainPrecedesContainerId(
        after marker: String,
        identifier: String,
        in source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let start = try XCTUnwrap(
            source.range(of: marker)?.upperBound,
            "no declaration for \(marker)",
            file: file,
            line: line
        )
        let body = source[start...]
        let contain = try XCTUnwrap(
            body.range(of: "children: .contain")?.lowerBound,
            "\(marker) must declare .accessibilityElement(children: .contain) before its id, "
                + "otherwise the id overwrites its children's ids",
            file: file,
            line: line
        )
        let id = try XCTUnwrap(
            body.range(of: identifier)?.lowerBound,
            "\(marker) carries \(identifier)",
            file: file,
            line: line
        )
        XCTAssertLessThan(contain, id, "\(marker): container first, id second", file: file, line: line)
    }

    // MARK: Timer / Ratio option ids

    /// Each Timer and Ratio choice is its own accessibility element with its own id, and each row keeps the
    /// handle the flows already use. The chips are one line per row now, so the row is the container and no chip
    /// inherits its parent's id.
    func testTheTimerAndRatioChoicesKeepTheirOwnIdentifiers() throws {
        // The chips live with the popover they belong to, in the one place that builds a row's control.
        let source = try cameraToolsPopoverSource()
        let control = try XCTUnwrap(
            source.range(of: "private func control(for row: CameraToolsLayout.Row)")?.lowerBound
        )
        let controlBody = source[control...].prefix(2_600)
        XCTAssertTrue(controlBody.contains("setting.accessibilityIdentifier"), "each Timer choice keeps its own id")
        XCTAssertTrue(controlBody.contains("ratio.accessibilityIdentifier"), "each Ratio choice keeps its own id")
        XCTAssertTrue(controlBody.contains("camera.tools.flash."), "and so does each Flash choice")

        // The ids themselves are the QA contract and stay unchanged.
        XCTAssertEqual(CameraTimerSetting.off.accessibilityIdentifier, "camera.tools.timer.off")
        XCTAssertEqual(CameraTimerSetting.threeSeconds.accessibilityIdentifier, "camera.tools.timer.3s")
        XCTAssertEqual(CameraTimerSetting.tenSeconds.accessibilityIdentifier, "camera.tools.timer.10s")
        XCTAssertEqual(CameraAspectRatio.threeFour.accessibilityIdentifier, "camera.tools.ratio.3x4")
        XCTAssertEqual(CameraAspectRatio.oneOne.accessibilityIdentifier, "camera.tools.ratio.1x1")
        XCTAssertEqual(CameraAspectRatio.nineSixteen.accessibilityIdentifier, "camera.tools.ratio.9x16")
    }

    // MARK: The popover, rendered

    /// The popover, measured on a rendered frame: four one-line rows and the artboard's 232 pt, with the Ratio
    /// row's three choices on a single line and the chosen one carrying the selected fill.
    ///
    /// Four rows and no fifth is what says the retired Opacity / Line colour / Scale / Mirror rows are gone. The
    /// popover is rendered on its own because the camera behind it cannot be rendered in a simulator, so the
    /// anchoring to the tools control and the check inside the chosen chip are pinned by their own rules.
    func testThePopoverDrawsFourOneLineRows() throws {
        let rendered = try popoverRender(ratio: .threeFour)

        XCTAssertEqual(rendered.card.width, CameraToolsLayout.width - 4, accuracy: 4, "the artboard's 232 pt")
        XCTAssertLessThanOrEqual(rendered.card.height, CameraToolsLayout.height + 1, "no fifth row on this surface")
        XCTAssertGreaterThan(rendered.card.height, CameraToolsLayout.height - 26, "and all four rows are painted")

        XCTAssertEqual(rendered.ratioChips.count, 3, "the Ratio row paints its three choices on one line")
        XCTAssertEqual(rendered.selectedChips, 1, "and exactly one of them is the chosen one")
    }

    /// The popover hangs under the tools control because the screen pads it by those two rules: its right edge on
    /// the control's inset, its card top under the measured top bar. Source-level, so a change to either padding
    /// has to change this test.
    func testTheScreenAnchorsThePopoverUnderTheToolsControl() throws {
        let source = try cameraFeatureSource()
        XCTAssertTrue(
            source.contains(".padding(.top, CameraToolsLayout.cardTop(belowTopBar: topBarHeight))"),
            "the card starts under the measured top bar"
        )
        XCTAssertTrue(
            source.contains(".padding(.trailing, CameraProto.controlInset)"),
            "and its right edge sits on the tools control's"
        )
        XCTAssertFalse(source.contains("CameraToolsPopupMetrics"), "no height cap: the popover hugs its four rows")
    }

    /// The chosen chip is marked with a check glyph in addition to its fill (the owner's default). A 9 pt glyph is
    /// below what a rendered frame can be asserted on reliably, so the chip's own drawing rule is pinned here.
    func testTheChosenChipDrawsACheckmark() throws {
        let source = try cameraToolsPopoverSource()
        let chip = try XCTUnwrap(source.range(of: "private func chip(")?.lowerBound)
        let chipBody = source[chip...].prefix(1_200)
        XCTAssertTrue(chipBody.contains("if isSelected {"), "the chip branches on being the chosen one")
        XCTAssertTrue(
            chipBody.contains("Image(systemName: \"checkmark\")"),
            "and that branch draws the check glyph beside the word"
        )
        XCTAssertTrue(
            chipBody.contains(".accessibilityValue(isSelected ? \"Selected\" : \"\")"),
            "and announces the choice instead of relying on the glyph alone"
        )
    }

    private struct PopoverRender {
        let card: CGRect
        let ratioChips: [Range<Int>]
        /// How many of those chips carry the selected fill.
        let selectedChips: Int
    }

    private func popoverRender(ratio: CameraAspectRatio) throws -> PopoverRender {
        let popup = CameraToolsPopup(
            flashSetting: .auto,
            isGridVisible: false,
            controlsEnabled: true,
            timerSetting: .off,
            aspectRatio: ratio,
            onFlashChange: { _ in },
            onGridToggle: {},
            onTimerChange: { _ in },
            onAspectRatioChange: { _ in },
            onDismiss: {}
        )
        .environment(\.colorScheme, .dark)
        .background(AP.Color.background)
        let size = CGSize(width: CameraToolsLayout.width + 16, height: CameraToolsLayout.height + 16)
        let bitmap = try XCTUnwrap(render(popup, size: size))

        let surface = APColorTokens.surface.spec(for: .dark).hex ?? 0
        let card = try XCTUnwrap(boxOfColour(bitmap, hex: surface), "the popover's card is painted")

        let selected = APColorTokens.selectedBackground.spec(for: .dark).hex ?? 0
        let unselected = APColorTokens.controlFill.spec(for: .dark).hex ?? 0
        var chips: [Range<Int>] = []
        var selectedCount = 0
        for row in stride(from: Int(card.maxY) - 4, through: Int(card.maxY) - 52, by: -1) {
            // A chip's fill is split by the glyphs drawn on it, so runs separated by a letter gap are one chip —
            // while the gap between two chips (4 pt) keeps them apart.
            let chosen = mergedRuns(bitmap, row: row, hex: selected).filter { $0.count >= 20 && $0.count <= 90 }
            let plain = mergedRuns(bitmap, row: row, hex: unselected).filter { $0.count >= 20 && $0.count <= 90 }
            guard chosen.count + plain.count == 3 else { continue }
            chips = (chosen + plain).sorted { $0.lowerBound < $1.lowerBound }
            selectedCount = chosen.count
            break
        }
        return PopoverRender(card: card, ratioChips: chips, selectedChips: selectedCount)
    }

    private func matches(_ pixel: APPixel, _ hex: UInt32, tolerance: Int = 6) -> Bool {
        let target = (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
        return pixel.alpha > 200
            && abs(pixel.red - target.red) <= tolerance
            && abs(pixel.green - target.green) <= tolerance
            && abs(pixel.blue - target.blue) <= tolerance
    }

    /// The bounding box of `hex`-coloured pixels.
    private func boxOfColour(_ bitmap: APBitmap, hex: UInt32) -> CGRect? {
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y), matches(pixel, hex, tolerance: 4) else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The runs of `hex` on one row with neighbouring runs closer than `maxGap` merged: a chip's fill is split by
    /// the glyphs drawn on top of it, and a chip is what the caller counts.
    private func mergedRuns(_ bitmap: APBitmap, row: Int, hex: UInt32, maxGap: Int = 3) -> [Range<Int>] {
        var merged: [Range<Int>] = []
        for run in allRuns(bitmap, row: row, hex: hex) {
            if let last = merged.last, run.lowerBound - last.upperBound <= maxGap {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, run.upperBound)
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    private func allRuns(_ bitmap: APBitmap, row: Int, hex: UInt32) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for x in 0...bitmap.width {
            let isFill = x < bitmap.width
                ? (bitmap.color(x: x, y: row).map { matches($0, hex, tolerance: 4) } ?? false)
                : false
            if isFill, start == nil {
                start = x
            } else if !isFill, let opened = start {
                runs.append(opened..<x)
                start = nil
            }
        }
        return runs
    }

    /// Deterministic dark render of a screen, as the guide-tint evidence does it.
    private func render<Content: View>(_ view: Content, size: CGSize) -> APBitmap? {
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return APBitmap(image: image)
    }

    // MARK: - Source helpers

    /// The canvas' own source: the dim, the edge and the guide's clip are drawn there now.
    private func cameraCanvasSource() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Features/Camera/CameraCanvas.swift"),
            encoding: .utf8
        )
    }

    /// The tools popover's own source: its rows are asserted here, and it is a file of its own.
    private func cameraToolsPopoverSource() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Features/Camera/CameraToolsPopover.swift"),
            encoding: .utf8
        )
    }

    private func cameraFeatureSource() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Features
                .deletingLastPathComponent() // iosAppTests
                .deletingLastPathComponent() // iosApp (project dir)
                .appendingPathComponent("iosApp/Features/Camera/CameraFeature.swift"),
            encoding: .utf8
        )
    }

    /// The body of `private var <name>: some View { … }`, found by brace counting.
    private func viewBody(named name: String, in source: String) throws -> String {
        let start = try XCTUnwrap(
            source.range(of: "var \(name): some View {")?.upperBound,
            "no declaration for \(name)"
        )
        return try bracedBody(from: start, named: name, in: source)
    }

    /// Everything up to the brace that closes the one just after `start`.
    private func bracedBody(from start: String.Index, named name: String, in source: String) throws -> String {
        var depth = 1
        var index = start
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start..<index]) }
            }
            index = source.index(after: index)
        }
        XCTFail("unterminated body for \(name)")
        return ""
    }
}

/// The picker sheet's *drawn* geometry: the results scroll content has to fill the panel under the chips.
///
/// The panel used to render every row through a `ForEach`, including the results `ScrollView` — the one
/// flexible child, re-parented under a `ForEach` instead of being a direct child of the `VStack`. The order
/// array stayed green either way, so nothing could see the scroll content being proposed the wrong height.
/// This renders the real screen with the sheet open and measures what was painted.
@MainActor
final class CameraPickerSheetGeometryTests: XCTestCase {
    private let size = CGSize(width: 393, height: 852)

    func testTheResultsFillThePanelBelowTheChips() throws {
        let bitmap = try renderSheet()

        // The camera canvas behind the sheet is dark and full-width; the sheet is the light surface, so the
        // first row that is not full-width ink is the sheet's top edge.
        let sheetTop = try XCTUnwrap(
            (0..<bitmap.height).first { ink(in: bitmap, row: $0) < bitmap.width / 2 },
            "the sheet is drawn over the canvas"
        )
        let bands = inkBands(in: bitmap, rows: sheetTop..<bitmap.height, minimumInk: 20)

        // handle · header · search field · chips, then the results. The search field is the band that paints
        // the whole width (it is a full-width control fill); the chips are the pills under it.
        let search = try XCTUnwrap(
            bands.first { $0.widest >= bitmap.width * 3 / 4 },
            "the search field is drawn (bands: \(bands))"
        )
        let chips = try XCTUnwrap(
            bands.first { $0.range.lowerBound > search.range.upperBound },
            "the scope chips are drawn"
        )

        let results = bands.filter { $0.range.lowerBound > chips.range.upperBound }.map(\.range)
        XCTAssertGreaterThanOrEqual(
            results.count, 2,
            "below the chips the row's card and its name are painted, not an empty panel: \(bands.map(\.range))"
        )
        let first = try XCTUnwrap(results.first)
        let last = try XCTUnwrap(results.last)
        XCTAssertGreaterThanOrEqual(
            last.upperBound - first.lowerBound, 80,
            "the results area is a real block of the panel, not a sliver (\(first)–\(last))"
        )
        XCTAssertGreaterThan(
            CGFloat(last.upperBound), CGFloat(chips.range.upperBound) + 60,
            "and it extends well below the chips"
        )
    }

    private func renderSheet() throws -> APBitmap {
        var guide: NativePose?
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.openPosePicker()
        let screen = CameraScreen(
            guide: Binding(get: { guide }, set: { guide = $0 }),
            poseService: PreviewPoseService(),
            model: model
        )
        let host = UIHostingController(rootView: screen)
        // The sheet follows the app's appearance, which the test host resolves to light: pin it, so the
        // measurement is "dark ink on a light surface" whatever the simulator is set to.
        host.overrideUserInterfaceStyle = .light
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()
        // The sheet loads its catalogue in a `.task`; give the immediate stub service its turn.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return try XCTUnwrap(APBitmap(image: image))
    }

    /// Pixels in one row that are not the sheet's white surface.
    private func ink(in bitmap: APBitmap, row: Int) -> Int {
        var count = 0
        for x in 0..<bitmap.width {
            guard let pixel = bitmap.color(x: x, y: row) else { continue }
            let luminance = (pixel.red * 299 + pixel.green * 587 + pixel.blue * 114) / 1000
            if luminance < 235 { count += 1 }
        }
        return count
    }

    /// One run of rows that paints at least `minimumInk` non-surface pixels, with the widest row in it.
    private struct InkBand {
        let range: ClosedRange<Int>
        /// The most pixels any row in the band painted: a full-width control fill fills the row, a pill or a
        /// line of text does not.
        let widest: Int
    }

    /// Runs of rows that paint at least `minimumInk` non-surface pixels.
    private func inkBands(in bitmap: APBitmap, rows: Range<Int>, minimumInk: Int) -> [InkBand] {
        var bands: [InkBand] = []
        var start: Int?
        var widest = 0
        func close(_ lastRow: Int) {
            guard let opened = start else { return }
            if lastRow - opened >= 2 { bands.append(InkBand(range: opened...lastRow, widest: widest)) }
            start = nil
            widest = 0
        }
        for row in rows {
            let painted = ink(in: bitmap, row: row)
            if painted >= minimumInk {
                if start == nil { start = row }
                widest = max(widest, painted)
            } else {
                close(row - 1)
            }
        }
        close(rows.upperBound - 1)
        return bands
    }
}
