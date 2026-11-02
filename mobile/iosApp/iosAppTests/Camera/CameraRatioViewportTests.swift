import AVFoundation
import XCTest
@testable import iosApp

/// The camera's ratio setting is **framing**, not only a saved-file crop.
///
/// The bug this file pins: `CameraAspectRatio.widthOverHeight` used to reach only
/// `CameraAspectCrop` / `CameraImagePostProcess`, so choosing 1:1 or 9:16 cropped the saved photo while
/// the preview stayed full-bleed — the user framed one picture and kept another. These are business
/// assertions (what the screen shows versus what the file keeps), not view snapshots.
final class CameraRatioViewportTests: XCTestCase {
    /// Two real phone viewports: the canvas is the space left under the top chrome and above the bottom
    /// bar, so both a narrow (393×852) and a wide (430×932) device are checked.
    private let containers = [
        CGSize(width: 393, height: 852),
        CGSize(width: 430, height: 932),
    ]

    // MARK: - The frame has the selected ratio

    func testThePreviewFrameHasTheSelectedRatioOnEveryScreen() {
        for container in containers {
            for ratio in CameraAspectRatio.allCases {
                let frame = CameraViewportFrame.rect(for: ratio, in: container)
                XCTAssertGreaterThan(frame.width, 0, "\(ratio) in \(container)")
                XCTAssertEqual(
                    frame.width / frame.height,
                    ratio.widthOverHeight,
                    accuracy: 0.0005,
                    "the framing rect is \(ratio.rawValue) in \(container), got \(frame)"
                )
            }
        }
    }

    func testTheFrameIsCentredAndStaysInsideTheContainer() {
        for container in containers {
            for ratio in CameraAspectRatio.allCases {
                let frame = CameraViewportFrame.rect(for: ratio, in: container)
                XCTAssertEqual(frame.midX, container.width / 2, accuracy: 0.001, "\(ratio) is horizontally centred")
                XCTAssertEqual(frame.midY, container.height / 2, accuracy: 0.001, "\(ratio) is vertically centred")
                XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(ratio) does not leave the container")
                XCTAssertGreaterThanOrEqual(frame.minY, 0, "\(ratio) does not leave the container")
                XCTAssertLessThanOrEqual(frame.maxX, container.width + 0.001, "\(ratio) does not overflow")
                XCTAssertLessThanOrEqual(frame.maxY, container.height + 0.001, "\(ratio) does not overflow")
            }
        }
    }

    /// "Largest that fits": the frame touches one pair of container edges, and growing it would leave the
    /// container. A frame that merely had the right ratio could be a stamp in the middle of the screen.
    /// A wide canvas (landscape host, split view) is included so the height-limited branch is covered too.
    func testTheFrameIsTheLargestRectOfThatRatioThatFits() {
        for container in containers + [CGSize(width: 852, height: 393)] {
            for ratio in CameraAspectRatio.allCases {
                let frame = CameraViewportFrame.rect(for: ratio, in: container)
                let fillsWidth = abs(frame.width - container.width) <= 0.001
                let fillsHeight = abs(frame.height - container.height) <= 0.001
                XCTAssertTrue(
                    fillsWidth || fillsHeight,
                    "\(ratio.rawValue) in \(container) must use every point it can: \(frame)"
                )
                XCTAssertEqual(
                    fillsWidth,
                    container.width / container.height <= ratio.widthOverHeight,
                    "\(ratio.rawValue) keeps the full width exactly when the screen is narrower than the ratio"
                )
            }
        }
    }

    /// A 3:4 phone viewport is the camera's own framing: nothing is letterboxed away.
    func testTheDefaultRatioFillsAPortraitScreenWithNoBars() {
        let container = CGSize(width: 393, height: 524) // 3:4, the framing the default ratio produces
        let frame = CameraViewportFrame.rect(for: .threeFour, in: container)
        XCTAssertEqual(frame.width, container.width, accuracy: 0.001)
        XCTAssertEqual(frame.height, container.height, accuracy: 0.001)
    }

    func testADegenerateContainerDoesNotCrash() {
        XCTAssertEqual(CameraViewportFrame.rect(for: .oneOne, in: .zero), .zero)
        XCTAssertEqual(CameraViewportFrame.rect(for: .nineSixteen, in: CGSize(width: 0, height: 852)), .zero)
        XCTAssertEqual(CameraViewportFrame.guideRect(in: .zero), .zero)
    }

    /// The enum is the product's three ratios. A fourth one would be a product change, not a fix.
    func testTheRatioSetIsUnchanged() {
        XCTAssertEqual(CameraAspectRatio.allCases, [.threeFour, .oneOne, .nineSixteen])
    }

    // MARK: - The pose reference lives inside the frame

    func testTheGuideSitsInsideTheFramingRect() {
        for container in containers {
            for ratio in CameraAspectRatio.allCases {
                let frame = CameraViewportFrame.rect(for: ratio, in: container)
                let guide = CameraViewportFrame.guideRect(in: frame)
                XCTAssertGreaterThan(guide.width, 0, "\(ratio) has a guide area")
                XCTAssertGreaterThan(guide.height, 0, "\(ratio) has a guide area")
                XCTAssertGreaterThanOrEqual(guide.minX, frame.minX - 0.001, "\(ratio): the guide stays in the photo")
                XCTAssertGreaterThanOrEqual(guide.minY, frame.minY - 0.001, "\(ratio): the guide stays in the photo")
                XCTAssertLessThanOrEqual(guide.maxX, frame.maxX + 0.001, "\(ratio): the guide stays in the photo")
                XCTAssertLessThanOrEqual(guide.maxY, frame.maxY + 0.001, "\(ratio): the guide stays in the photo")
            }
        }
    }

    /// The guide keeps the prototype's inset fractions — of the frame, so the same reference covers the
    /// same share of the photo at every ratio.
    func testTheGuideKeepsThePrototypeInsetFractionsOfTheFrame() {
        let frame = CameraViewportFrame.rect(for: .nineSixteen, in: CGSize(width: 393, height: 852))
        let guide = CameraViewportFrame.guideRect(in: frame)

        XCTAssertEqual(
            (guide.minX - frame.minX) / frame.width,
            CameraProto.poseReferenceHorizontalInset,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            (guide.minY - frame.minY) / frame.height,
            CameraProto.poseReferenceTopInset,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            guide.width / frame.width,
            1 - CameraProto.poseReferenceHorizontalInset * 2,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            guide.height / frame.height,
            1 - CameraProto.poseReferenceTopInset - CameraProto.poseReferenceBottomInset,
            accuracy: 0.0005
        )
    }

    /// A taller frame (9:16, the narrowest ratio) must not draw the guide where the 3:4 frame put it: the
    /// reference follows the photo, not the screen.
    func testTheGuideMovesWithTheFrameNotWithTheScreen() {
        let container = CGSize(width: 393, height: 852)
        let threeFour = CameraViewportFrame.guideRect(
            in: CameraViewportFrame.rect(for: .threeFour, in: container)
        )
        let story = CameraViewportFrame.guideRect(
            in: CameraViewportFrame.rect(for: .nineSixteen, in: container)
        )
        XCTAssertNotEqual(threeFour.minY, story.minY, accuracy: 0.5)
        XCTAssertGreaterThan(story.height, threeFour.height, "the narrower ratio is the taller frame")
        XCTAssertEqual(story.width, threeFour.width, accuracy: 0.001, "both frames are as wide as the screen")
    }

    // MARK: - The saved file matches what was framed

    /// The capture crop and the visible frame are the same ratio, so "what you see is what you get".
    /// 3024×4032 is the 12 MP portrait sensor size the camera actually writes.
    func testTheCaptureCropHasTheSameRatioAsTheViewportFrame() {
        let sensor = CGSize(width: 3024, height: 4032)
        for ratio in CameraAspectRatio.allCases {
            let frame = CameraViewportFrame.rect(for: ratio, in: CGSize(width: 393, height: 852))
            let crop = CameraAspectCrop.rect(for: ratio, imageSize: sensor)
            XCTAssertEqual(
                crop.width / crop.height,
                frame.width / frame.height,
                accuracy: 0.0005,
                "\(ratio.rawValue): the saved crop and the framed preview describe the same picture"
            )
            XCTAssertLessThanOrEqual(crop.maxX, sensor.width, "the crop stays inside the sensor")
            XCTAssertLessThanOrEqual(crop.maxY, sensor.height, "the crop stays inside the sensor")
        }
    }

    /// The default ratio is the sensor's own: a 3:4 capture is saved untouched, no re-encode, no quality
    /// loss — and the preview frame of that ratio needs no letterboxing on a 3:4 viewport.
    func testACaptureAlreadyMatchingTheRatioNeedsNoCrop() {
        let sensor = CGSize(width: 3024, height: 4032)
        XCTAssertFalse(CameraAspectCrop.needsCrop(ratio: .threeFour, imageSize: sensor))
        XCTAssertEqual(
            CameraAspectCrop.rect(for: .threeFour, imageSize: sensor),
            CGRect(origin: .zero, size: sensor)
        )
        // The other two ratios do change the file — that is exactly why the preview has to show it.
        XCTAssertTrue(CameraAspectCrop.needsCrop(ratio: .oneOne, imageSize: sensor))
        XCTAssertTrue(CameraAspectCrop.needsCrop(ratio: .nineSixteen, imageSize: sensor))
    }

    // MARK: - The published frame follows the setting

    @MainActor
    func testChoosingARatioChangesTheFrameTheScreenDraws() {
        let container = CGSize(width: 393, height: 852)
        let model = ratioModel()
        model.coordinator.onPermissionResult(.authorized)

        let threeFour = model.viewportFrame(in: container)
        XCTAssertEqual(threeFour.width / threeFour.height, CameraAspectRatio.threeFour.widthOverHeight, accuracy: 0.0005)

        model.setAspectRatio(.oneOne)
        let square = model.viewportFrame(in: container)
        XCTAssertNotEqual(square, threeFour, "the published ratio is what the viewport reads")
        XCTAssertEqual(square.width / square.height, 1, accuracy: 0.0005)
        XCTAssertEqual(square.height, container.width, accuracy: 0.001, "1:1 in a tall viewport is a square as wide as the screen")

        model.setAspectRatio(.nineSixteen)
        let story = model.viewportFrame(in: container)
        XCTAssertNotEqual(story, square)
        XCTAssertEqual(story.width / story.height, 9.0 / 16.0, accuracy: 0.0005)
        XCTAssertGreaterThan(
            story.height, threeFour.height,
            "9:16 is the narrowest ratio, so its frame is the tallest and fills the viewport best"
        )
    }

    /// The ratio is persisted like every other camera setting, so the frame a relaunch draws is the one
    /// the user chose.
    @MainActor
    func testTheChosenFrameSurvivesARelaunch() throws {
        var settings = CameraSettings()
        settings.aspectRatio = .oneOne
        let restored = try XCTUnwrap(CameraSettings.decode(try settings.encodedJSON()))

        let container = CGSize(width: 393, height: 852)
        XCTAssertEqual(
            CameraViewportFrame.rect(for: restored.aspectRatio, in: container),
            CameraViewportFrame.rect(for: .oneOne, in: container)
        )
    }

    /// The model under test with a stub camera: the framing is pure layout, so these tests must not spin
    /// up a real `AVCaptureSession` (a running session in a unit test leaks work into later test classes).
    @MainActor
    private func ratioModel() -> CameraViewModel {
        CameraViewModel(camera: RatioStubCamera())
    }

    /// A camera that cannot serve the control does not move the frame either.
    @MainActor
    func testTheFrameDoesNotMoveWhenTheControlIsDisabled() {
        let container = CGSize(width: 393, height: 852)
        let model = ratioModel()
        model.coordinator.onPermissionResult(.denied)

        let before = model.viewportFrame(in: container)
        model.setAspectRatio(.nineSixteen)
        XCTAssertEqual(model.viewportFrame(in: container), before)
    }
}

/// A camera that is never started: these tests read the framing the ratio produces, not the hardware.
@MainActor
private final class RatioStubCamera: CameraSessionControlling {
    let session = AVCaptureSession()
    var facing: CameraFacing = .back
    private(set) var isSessionRunning = false

    func currentPermissionState() -> CameraPermissionState { .authorized }
    func requestPermission(onResult: @escaping @Sendable (CameraPermissionState) -> Void) {
        onResult(.authorized)
    }

    func capture(captureId: String, onResult: @escaping @Sendable (CameraCaptureResult) -> Void) {}
    func cancelCapture() {}
    func switchCamera() {}
    func setFlashMode(_ mode: CameraFlashSetting) {}
    func setTorchEnabled(_ enabled: Bool) {}
    func setZoomFactor(_ factor: CGFloat) {}
    func start() async throws { isSessionRunning = true }
    func stop() { isSessionRunning = false }
}
