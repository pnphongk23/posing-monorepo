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
