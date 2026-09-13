import XCTest
@testable import iosApp

@MainActor
final class CameraFeatureTests: XCTestCase {
    /// `app.js:380` — `setCameraStatus(`${selectedPose.title} selected`, 'success', 2400)`. The copy
    /// is `<name> selected`; the earlier `Matching: <name>` was a native invention, and the prototype
    /// has no separate chip for pose selection (it reuses `#camera-status`, `app.js:349-356`).
    func testPoseSelectionFeedbackMatchesCameraStatusCopy() {
        let model = CameraViewModel()
        let pose = NativePose(
            id: "dancing",
            name: "Dancing Pose",
            category: "Standing",
            imageURL: nil,
            instructions: [],
            isSaved: false
        )
        XCTAssertEqual(model.matchingFeedbackLabel(for: pose), "Dancing Pose selected")
        XCTAssertNil(model.matchingFeedbackLabel(for: nil))
    }

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

    /// `clear-pose-row`: clears the reference and resets the pose-specific controls to their
    /// prototype defaults (visible, 50%, Black) — the general Flash/Grid settings survive.
    func testResetPoseGuideRestoresDefaultsAndKeepsGeneralSettings() {
        let model = CameraViewModel()
        model.coordinator.onPermissionResult(.authorized)
        model.togglePoseGuideVisibility()
        model.setGuideOpacity(0.9)
        model.setGuideLineColor(.white)
        model.toggleGrid()
        model.cycleFlash()
        // Capture rather than hardcode: the point is that the general Flash setting SURVIVES the pose
        // reset. (The old `.auto` literal only held because the default used to be `.off`; the
        // prototype default is `Auto` per `camera-live.html:87`, so one cycle now lands on `.on`.)
        let flashAfterCycle = model.flashSetting

        model.resetPoseGuide()

        XCTAssertTrue(model.isPoseGuideVisible)
        XCTAssertEqual(model.guideOpacity, 0.5, accuracy: 0.001)
        XCTAssertEqual(model.guideLineColor, .black)
        XCTAssertTrue(model.isGridVisible)
        XCTAssertEqual(model.flashSetting, flashAfterCycle, "general Flash setting survives the pose reset")
        XCTAssertNotEqual(model.flashSetting, .auto, "resetting the pose guide must not reset Flash")
    }

    // MARK: Zoom pill (`.nb-camera-zoom-slider` stops 1x → 2x → 3x)

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
}
