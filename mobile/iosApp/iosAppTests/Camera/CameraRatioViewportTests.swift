import AVFoundation
import ImageIO
import SwiftUI
import XCTest
@testable import iosApp

/// The camera's ratio setting is **framing**, not only a saved-file crop.
///
/// The model the boards describe: the preview is always full screen, and the ratio only draws the full-width
/// frame the shutter will save — everything outside it is dimmed, never blacked out. These are business
/// assertions (what the screen frames versus what the file keeps), not view snapshots, and they run on two
/// phones so "full width" and "on screen" are rules instead of one screen's luck.
final class CameraRatioViewportTests: XCTestCase {
    /// The artboards' phone (393×852, safe top 59) and a small one (375×667, safe top 20).
    private let phones: [(name: String, screen: CGSize, safeTop: CGFloat)] = [
        ("393x852", CGSize(width: 393, height: 852), 59),
        ("375x667", CGSize(width: 375, height: 667), 20),
    ]

    // MARK: - The frame is full width, of the ratio's height, hung from the top controls

    func testTheFrameIsAlwaysAsWideAsTheScreen() {
        for phone in phones {
            for ratio in CameraAspectRatio.allCases {
                let stage = CameraStageFrame.make(ratio: ratio, screen: phone.screen, safeTop: phone.safeTop)
                XCTAssertEqual(stage.frame.minX, 0, "\(ratio.rawValue) on \(phone.name) starts at the screen's edge")
                XCTAssertEqual(
                    stage.frame.width, phone.screen.width,
                    "\(ratio.rawValue) on \(phone.name): the photo is never narrower than the screen"
                )
            }
        }
    }

    /// 3:4 = w·4/3, 1:1 = w, 9:16 = w·16/9 — and on the boards' phone those are 524, 393 and 699 points.
    func testTheFrameHasTheRatiosHeight() {
        let reference = CameraStageFrame.make(
            ratio: .threeFour,
            screen: CGSize(width: 393, height: 852),
            safeTop: 59
        )
        XCTAssertEqual(reference.frame.height, 524, accuracy: 0.01, "3:4 on the boards' phone")
        XCTAssertEqual(
            CameraStageFrame.make(ratio: .oneOne, screen: reference.screen, safeTop: 59).frame.height,
            393, accuracy: 0.01
        )
        XCTAssertEqual(
            CameraStageFrame.make(ratio: .nineSixteen, screen: reference.screen, safeTop: 59).frame.height,
            393 * 16.0 / 9.0, accuracy: 0.01
        )

        for phone in phones {
            for ratio in CameraAspectRatio.allCases {
                let stage = CameraStageFrame.make(ratio: ratio, screen: phone.screen, safeTop: phone.safeTop)
                XCTAssertEqual(
                    stage.frame.width / stage.frame.height,
                    ratio.widthOverHeight,
                    accuracy: 0.0005,
                    "\(ratio.rawValue) on \(phone.name) is the ratio the shutter saves"
                )
            }
        }
    }

    /// 3:4 and 1:1 hang from just under the top control row (safe top + 45); 9:16 starts at the safe top.
    func testTheFrameHangsFromJustUnderTheTopControls() {
        XCTAssertEqual(
            CameraStageFrame.make(ratio: .threeFour, screen: CGSize(width: 393, height: 852), safeTop: 59).frame.minY,
            104, accuracy: 0.01, "the artboard's 3:4 frame starts at y 104"
        )
        XCTAssertEqual(
            CameraStageFrame.make(ratio: .oneOne, screen: CGSize(width: 393, height: 852), safeTop: 59).frame.minY,
            104, accuracy: 0.01
        )
        XCTAssertEqual(
            CameraStageFrame.make(ratio: .nineSixteen, screen: CGSize(width: 393, height: 852), safeTop: 59).frame.minY,
            60, accuracy: 0.01, "the artboard's 9:16 frame starts at y 60"
        )
        // The insets are relative to the safe area, not to one phone's notch — until the frame no longer fits,
        // which is the clamp `testAShortPhoneKeepsTheTallFrameOnScreen` pins.
        for phone in phones {
            for ratio in CameraAspectRatio.allCases {
                let stage = CameraStageFrame.make(ratio: ratio, screen: phone.screen, safeTop: phone.safeTop)
                let wanted = phone.safeTop + CameraStageFrame.topInset(for: ratio)
                let fits = wanted + stage.frame.height <= phone.screen.height + 0.01
                guard fits else { continue }
                XCTAssertEqual(
                    stage.frame.minY, wanted, accuracy: 0.01,
                    "\(ratio.rawValue) on \(phone.name)"
                )
            }
        }
    }

    /// A short phone keeps the tall 9:16 frame on screen by moving its top up — the width never gives way, so
    /// the photo is still the full screen wide.
    func testAShortPhoneKeepsTheTallFrameOnScreen() {
        let small = CGSize(width: 375, height: 667)
        let stage = CameraStageFrame.make(ratio: .nineSixteen, screen: small, safeTop: 20)
        XCTAssertEqual(stage.frame.width, small.width, "the width is the screen's, whatever the height costs")
        XCTAssertLessThan(
            stage.frame.minY, 20 + CameraStageFrame.tallRatioTopInset,
            "the top is what moves when the tall frame no longer fits"
        )
        XCTAssertEqual(stage.frame.maxY, small.height, accuracy: 0.01, "the frame fills the screen it cannot fit in")
    }

    func testTheFrameIsOnScreenForEveryRatioAndPhone() {
        for phone in phones {
            for ratio in CameraAspectRatio.allCases {
                let stage = CameraStageFrame.make(ratio: ratio, screen: phone.screen, safeTop: phone.safeTop)
                XCTAssertGreaterThanOrEqual(stage.frame.minY, 0, "\(ratio.rawValue) on \(phone.name) stays on screen")
                XCTAssertLessThanOrEqual(
                    stage.frame.maxY, phone.screen.height + 0.01,
                    "\(ratio.rawValue) on \(phone.name) stays on screen"
                )
            }
        }
    }

    func testADegenerateScreenDoesNotCrash() {
        XCTAssertEqual(
            CameraStageFrame.make(ratio: .oneOne, screen: .zero, safeTop: 59).frame,
            .zero
        )
        XCTAssertEqual(CameraViewportFrame.guideRect(in: .zero), .zero)
    }

    /// The enum is the product's three ratios. A fourth one would be a product change, not a fix.
    func testTheRatioSetIsUnchanged() {
        XCTAssertEqual(CameraAspectRatio.allCases, [.threeFour, .oneOne, .nineSixteen])
    }

    // MARK: - The pose reference lives inside the frame

    func testTheGuideSitsInsideTheFrame() {
        for phone in phones {
            for ratio in CameraAspectRatio.allCases {
                let stage = CameraStageFrame.make(ratio: ratio, screen: phone.screen, safeTop: phone.safeTop)
                let guide = stage.guideFrame
                XCTAssertGreaterThan(guide.width, 0, "\(ratio) has a guide area")
                XCTAssertGreaterThan(guide.height, 0, "\(ratio) has a guide area")
                XCTAssertGreaterThanOrEqual(guide.minX, stage.frame.minX - 0.001)
                XCTAssertGreaterThanOrEqual(guide.minY, stage.frame.minY - 0.001)
                XCTAssertLessThanOrEqual(guide.maxX, stage.frame.maxX + 0.001)
                XCTAssertLessThanOrEqual(guide.maxY, stage.frame.maxY + 0.001)
            }
        }
    }

    /// The guide keeps the prototype's inset fractions — of the frame, so the same reference covers the same
    /// share of the photo at every ratio.
    func testTheGuideKeepsThePrototypeInsetFractionsOfTheFrame() {
        let stage = CameraStageFrame.make(ratio: .nineSixteen, screen: CGSize(width: 393, height: 852), safeTop: 59)
        let frame = stage.frame
        let guide = stage.guideFrame

        XCTAssertEqual((guide.minX - frame.minX) / frame.width, CameraProto.poseReferenceHorizontalInset, accuracy: 0.0005)
        XCTAssertEqual((guide.minY - frame.minY) / frame.height, CameraProto.poseReferenceTopInset, accuracy: 0.0005)
        XCTAssertEqual(guide.width / frame.width, 1 - CameraProto.poseReferenceHorizontalInset * 2, accuracy: 0.0005)
        XCTAssertEqual(
            guide.height / frame.height,
            1 - CameraProto.poseReferenceTopInset - CameraProto.poseReferenceBottomInset,
            accuracy: 0.0005
        )
    }

    /// A taller frame (9:16) must not put the guide where the 3:4 frame did: the reference follows the photo.
    func testTheGuideMovesWithTheFrameNotWithTheScreen() {
        let screen = CGSize(width: 393, height: 852)
        let threeFour = CameraStageFrame.make(ratio: .threeFour, screen: screen, safeTop: 59).guideFrame
        let story = CameraStageFrame.make(ratio: .nineSixteen, screen: screen, safeTop: 59).guideFrame
        XCTAssertGreaterThan(story.height, threeFour.height, "the narrower ratio is the taller frame")
        XCTAssertEqual(story.width, threeFour.width, accuracy: 0.001, "both frames are as wide as the screen")
        XCTAssertNotEqual(story.minY, threeFour.minY, accuracy: 0.5)
    }

    // MARK: - The saved photo is the frame

    /// The crop the shutter writes and the frame the screen draws describe the same picture: same aspect, same
    /// centred region. Measured through the real file path on both phones, so a change to either rule that
    /// forgets the other fails here.
    func testTheSavedPhotoMatchesTheFrameForEveryRatioAndPhone() throws {
        for phone in phones {
            for ratio in CameraAspectRatio.allCases {
                let stage = CameraStageFrame.make(ratio: ratio, screen: phone.screen, safeTop: phone.safeTop)

                let original = CameraCaptureFixture.jpeg(orientation: .right)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("frame-\(phone.name)-\(ratio.rawValue)-\(UUID().uuidString).jpg")
                try original.write(to: url)
                defer { try? FileManager.default.removeItem(at: url) }

                CameraImagePostProcess.cropFileInPlace(at: url.path, ratio: ratio)
                let saved = try CameraCaptureFixture.decode(try Data(contentsOf: url))

                XCTAssertEqual(
                    saved.size.width / saved.size.height,
                    stage.frame.width / stage.frame.height,
                    accuracy: 0.005,
                    "\(ratio.rawValue) on \(phone.name): the saved photo is the frame, not an approximation of it"
                )
                // The largest centred region of the picture with the frame's aspect: the frame is centred on the
                // screen and the preview is filled into it, so the crop has to be centred too.
                let expected = CameraAspectCrop.rect(for: ratio, imageSize: saved.size).integral
                XCTAssertEqual(
                    expected.size.width / expected.size.height,
                    stage.frame.width / stage.frame.height,
                    accuracy: 0.005,
                    "\(ratio.rawValue) on \(phone.name): the crop and the frame agree on the region"
                )
            }
        }
    }

    /// The default ratio is the capture's own: a 3:4 capture is saved untouched — measured on the *displayed*
    /// size, with the raw buffer shape asserted to be the wrong space.
    func testACaptureAlreadyMatchingTheRatioNeedsNoCrop() throws {
        let picture = try CameraCaptureFixture.decode(CameraCaptureFixture.jpeg(orientation: .right)).size
        XCTAssertFalse(CameraAspectCrop.needsCrop(ratio: .threeFour, imageSize: picture))
        XCTAssertEqual(CameraAspectCrop.rect(for: .threeFour, imageSize: picture), CGRect(origin: .zero, size: picture))
        XCTAssertTrue(CameraAspectCrop.needsCrop(ratio: .oneOne, imageSize: picture))
        XCTAssertTrue(CameraAspectCrop.needsCrop(ratio: .nineSixteen, imageSize: picture))

        // A raw buffer is 4:3 landscape. Reading the ratio off it is the old defect, in one line.
        let raw = CameraCaptureFixture.rawSize
        XCTAssertEqual(raw, CGSize(width: 4032, height: 3024))
        XCTAssertTrue(CameraAspectCrop.needsCrop(ratio: .threeFour, imageSize: raw))
    }

    // MARK: - The published ratio is what the stage draws

    @MainActor
    func testChoosingARatioChangesTheFrameTheScreenDraws() {
        let screen = CGSize(width: 393, height: 852)
        let model = ratioModel()
        model.coordinator.onPermissionResult(.authorized)

        func stage() -> CameraStageFrame {
            CameraStageFrame.make(ratio: model.aspectRatio, screen: screen, safeTop: 59)
        }

        let threeFour = stage()
        XCTAssertEqual(threeFour.frame.height, 524, accuracy: 0.01)

        model.setAspectRatio(.oneOne)
        let square = stage()
        XCTAssertNotEqual(square, threeFour, "the published ratio is what the stage reads")
        XCTAssertEqual(square.frame.height, 393, accuracy: 0.01)

        model.setAspectRatio(.nineSixteen)
        let story = stage()
        XCTAssertNotEqual(story, square)
        XCTAssertEqual(story.frame.height, 393 * 16.0 / 9.0, accuracy: 0.01)
        XCTAssertLessThan(story.frame.minY, threeFour.frame.minY, "9:16 hangs from the safe top, the others sit lower")
    }

    /// The ratio is persisted like every other camera setting, so the frame a relaunch draws is the one the
    /// user chose.
    @MainActor
    func testTheChosenFrameSurvivesARelaunch() throws {
        var settings = CameraSettings()
        settings.aspectRatio = .oneOne
        let restored = try XCTUnwrap(CameraSettings.decode(try settings.encodedJSON()))

        let screen = CGSize(width: 393, height: 852)
        XCTAssertEqual(
            CameraStageFrame.make(ratio: restored.aspectRatio, screen: screen, safeTop: 59),
            CameraStageFrame.make(ratio: .oneOne, screen: screen, safeTop: 59)
        )
    }

    /// The model under test with a stub camera: the framing is pure layout, so these tests must not spin up a
    /// real `AVCaptureSession` (a running session in a unit test leaks work into later test classes).
    @MainActor
    private func ratioModel() -> CameraViewModel {
        CameraViewModel(camera: RatioStubCamera(), settingsStore: InMemoryCameraSettingsStore())
    }

    /// A camera that cannot serve the control does not move the frame either.
    @MainActor
    func testTheFrameDoesNotMoveWhenTheControlIsDisabled() {
        let model = ratioModel()
        model.coordinator.onPermissionResult(.denied)

        XCTAssertEqual(model.aspectRatio, .threeFour)
        model.setAspectRatio(.nineSixteen)
        XCTAssertEqual(model.aspectRatio, .threeFour, "a control the camera cannot serve does not move")
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

// MARK: - WYSIWYG: the saved file is cropped in the space the user saw

/// A JPEG in the shape a real capture comes in: a **landscape 4032×3024 pixel buffer** plus an EXIF
/// orientation tag. Four quadrant colours and a marker at the buffer's centre make it possible to say,
/// from the saved file alone, which part of the *displayed* picture survived the crop.
enum CameraCaptureFixture {
    static let rawSize = CGSize(width: 4032, height: 3024)

    static let topLeft: UInt32 = 0xC0_20_20
    static let topRight: UInt32 = 0x20_B0_30
    static let bottomLeft: UInt32 = 0x20_40_C0
    static let bottomRight: UInt32 = 0xD0_C0_20
    /// Painted at the buffer's centre, which is the displayed picture's centre for every rotation.
    static let centreMarker: UInt32 = 0xC0_30_B0

    /// The buffer, in buffer space (top-left first, like the renderer's coordinate system).
    static let quadrants: [(fraction: (x: CGFloat, y: CGFloat), hex: UInt32)] = [
        ((0.25, 0.25), topLeft),
        ((0.75, 0.25), topRight),
        ((0.25, 0.75), bottomLeft),
        ((0.75, 0.75), bottomRight),
    ]

    static func jpeg(orientation: UIImage.Orientation) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: rawSize, format: format).image { context in
            for quadrant in quadrants {
                let x = quadrant.fraction.x < 0.5 ? 0 : rawSize.width / 2
                let y = quadrant.fraction.y < 0.5 ? 0 : rawSize.height / 2
                UIColor(rgb: quadrant.hex).setFill()
                context.fill(CGRect(x: x, y: y, width: rawSize.width / 2, height: rawSize.height / 2))
            }
            let side = rawSize.width * 0.03
            UIColor(rgb: centreMarker).setFill()
            context.fill(CGRect(
                x: (rawSize.width - side) / 2,
                y: (rawSize.height - side) / 2,
                width: side,
                height: side
            ))
        }
        guard let buffer = rendered.cgImage,
              let data = UIImage(cgImage: buffer, scale: 1, orientation: orientation)
                  .jpegData(compressionQuality: 0.95) else {
            XCTFail("could not build the capture fixture")
            return Data()
        }
        return data
    }

    /// Reads the file the way a viewer does: ImageIO applies the EXIF transform, so `size` and the pixels
    /// describe what the user sees. Independent of the code under test.
    static func decode(_ data: Data) throws -> (bitmap: APBitmap, size: CGSize) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceShouldCache: false,
        ]
        let transformed = try XCTUnwrap(
            CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            "the fixture is not a decodable image"
        )
        let size = CGSize(width: transformed.width, height: transformed.height)
        let bitmap = try XCTUnwrap(APBitmap(image: UIImage(cgImage: transformed)))
        return (bitmap, size)
    }

    static func colour(_ bitmap: APBitmap, at fraction: (x: CGFloat, y: CGFloat)) -> UInt32? {
        let x = min(max(Int(fraction.x * CGFloat(bitmap.width)), 0), bitmap.width - 1)
        let y = min(max(Int(fraction.y * CGFloat(bitmap.height)), 0), bitmap.height - 1)
        guard let pixel = bitmap.color(x: x, y: y) else { return nil }
        return UInt32((pixel.red << 16) | (pixel.green << 8) | pixel.blue)
    }

    static func isNear(_ hex: UInt32?, _ target: UInt32, tolerance: Int = 28) -> Bool {
        guard let hex else { return false }
        let channel: (UInt32) -> Int = { Int(($0 >> 16) & 0xFF) }
        let green: (UInt32) -> Int = { Int(($0 >> 8) & 0xFF) }
        let blue: (UInt32) -> Int = { Int($0 & 0xFF) }
        return abs(channel(hex) - channel(target)) <= tolerance
            && abs(green(hex) - green(target)) <= tolerance
            && abs(blue(hex) - blue(target)) <= tolerance
    }
}

/// The saved photo, read back: its **displayed** aspect is the ratio the user framed, and it shows the
/// centred region of the picture they framed rather than a strip of the raw sensor buffer.
///
/// This is a file-level test: a real JPEG in the camera's own shape (landscape buffer + EXIF tag) goes
/// through `CameraImagePostProcess.cropFileInPlace`, and the assertions read the file a viewer reads.
final class CameraCaptureCropOrientationTests: XCTestCase {
    /// `.right` is the back camera in portrait, `.left` the front camera in portrait, `.up` a capture whose
    /// pixels are already upright (the phone held in landscape). All three must save the picture the
    /// viewport showed; the first two are the ones the old code got wrong.
    private let orientations: [(name: String, orientation: UIImage.Orientation, displayed: CGSize)] = [
        ("up (landscape capture)", .up, CGSize(width: 4032, height: 3024)),
        ("right (back camera, portrait)", .right, CGSize(width: 3024, height: 4032)),
        ("left (front camera, portrait)", .left, CGSize(width: 3024, height: 4032)),
    ]

    func testEveryCaptureSavesTheRatioTheUserFramed() throws {
        for entry in orientations {
            for ratio in CameraAspectRatio.allCases {
                try assertSavedPhoto(
                    orientation: entry.orientation,
                    displayed: entry.displayed,
                    orientationName: entry.name,
                    ratio: ratio
                )
            }
        }
    }

    private func assertSavedPhoto(
        orientation: UIImage.Orientation,
        displayed expectedDisplay: CGSize,
        orientationName: String,
        ratio: CameraAspectRatio
    ) throws {
        let original = CameraCaptureFixture.jpeg(orientation: orientation)
        let displayed = try CameraCaptureFixture.decode(original)
        XCTAssertEqual(
            displayed.size,
            expectedDisplay,
            "the fixture must display as the camera's picture, not as its buffer (\(orientationName))"
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-\(orientationName.prefix(5))-\(ratio.rawValue)-\(UUID().uuidString).jpg")
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        CameraImagePostProcess.cropFileInPlace(at: url.path, ratio: ratio)

        let saved = try CameraCaptureFixture.decode(try Data(contentsOf: url))
        let label = "\(ratio.rawValue), stored \(orientationName)"

        // (a) The picture's displayed shape is the framed shape. This is the assertion that fails on the
        // old code: a 3:4 frame used to save a 4:3 landscape photo of a vertical strip.
        XCTAssertEqual(
            saved.size.width / saved.size.height,
            ratio.widthOverHeight,
            accuracy: 0.005,
            "\(label): the saved photo displays \(saved.size), which is not \(ratio.rawValue)"
        )
        // The largest centred crop of the displayed picture, to the pixel.
        let expected = CameraAspectCrop.rect(for: ratio, imageSize: displayed.size).integral.size
        XCTAssertEqual(saved.size.width, expected.width, accuracy: 1, "\(label): displayed width")
        XCTAssertEqual(saved.size.height, expected.height, accuracy: 1, "\(label): displayed height")

        // (b) The region is the centred region the viewport showed: the marker painted at the displayed
        // centre is still at the displayed centre.
        let centre = (x: CGFloat(0.5), y: CGFloat(0.5))
        XCTAssertTrue(
            CameraCaptureFixture.isNear(
                CameraCaptureFixture.colour(saved.bitmap, at: centre),
                CameraCaptureFixture.centreMarker,
                tolerance: 40
            ),
            "\(label): the centre of the saved photo is \(CameraCaptureFixture.colour(saved.bitmap, at: centre).map { String($0, radix: 16) } ?? "nothing"), not the frame's centre"
        )

        // (c) Nothing was rotated or flipped on the way out: every quadrant of the picture keeps its
        // colour, so the saved photo is the same picture, cropped — not the same buffer, re-tagged.
        for quadrant in CameraCaptureFixture.quadrants {
            let expectedColour = CameraCaptureFixture.colour(displayed.bitmap, at: quadrant.fraction)
            let savedColour = CameraCaptureFixture.colour(saved.bitmap, at: quadrant.fraction)
            XCTAssertTrue(
                CameraCaptureFixture.isNear(savedColour, expectedColour ?? 0),
                "\(label): the \(quadrant.fraction) quadrant is \(savedColour.map { String($0, radix: 16) } ?? "nothing"), expected \(expectedColour.map { String($0, radix: 16) } ?? "nothing")"
            )
        }
    }

    /// The default ratio is the picture's own aspect, so a portrait capture needs no crop at all: the file
    /// is not re-encoded and keeps its full resolution. The old code re-encoded every single capture,
    /// because it compared 3:4 against a 4:3 buffer.
    func testAPortraitCaptureAtTheDefaultRatioIsNotReencoded() throws {
        let original = CameraCaptureFixture.jpeg(orientation: .right)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-nocrop-\(UUID().uuidString).jpg")
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(
            CameraImagePostProcess.cropFileInPlace(at: url.path, ratio: .threeFour),
            "3:4 is the capture's own aspect, so there is nothing to crop"
        )
        XCTAssertEqual(try Data(contentsOf: url), original, "the file is left byte-identical")
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - What the canvas paints: the photo untouched, everything else dimmed

/// The stage's own drawn rules, measured on pixels.
///
/// The framing maths is asserted above; this renders `CameraCanvas` at a known size with a flat colour standing
/// in for the preview (the simulator has no camera feed, and "dimmed but not opaque" is a claim about pixels) and
/// checks the three things a screenshot would otherwise be the only evidence for: the photo is untouched inside
/// the frame, everything outside it is dimmed to 35 % of the photo, and the frame's edge is one white hairline.
@MainActor
final class CameraCanvasFramingTests: XCTestCase {
    private let screen = CGSize(width: 393, height: 852)
    private let safeTop: CGFloat = 59
    private let renderScale: CGFloat = 2
    /// The stand-in preview: a saturated colour, so "dimmed" is measurable and cannot be confused with black.
    private let previewColour = Color(red: 1, green: 0, blue: 1)

    func testTheFrameLeavesThePhotoUntouchedAndDimsOnlyWhatItLeavesOut() throws {
        for ratio in CameraAspectRatio.allCases {
            let stage = CameraStageFrame.make(ratio: ratio, screen: screen, safeTop: safeTop)
            let bitmap = try render(ratio: ratio)

            // Inside: exactly the preview, undimmed.
            let inside = try XCTUnwrap(
                pixel(in: bitmap, at: CGPoint(x: stage.frame.midX, y: stage.frame.midY)),
                "\(ratio.rawValue): the photo is drawn"
            )
            XCTAssertEqual(inside.red, 255, "the frame does not dim what the shutter keeps")
            XCTAssertEqual(inside.green, 0)
            XCTAssertEqual(inside.blue, 255)

            // Outside: the same preview at 35 % (the 65 % dim), never an opaque bar.
            let outsidePoint = CGPoint(x: stage.frame.midX, y: max(2, stage.frame.minY / 2))
            let outside = try XCTUnwrap(pixel(in: bitmap, at: outsidePoint), "\(ratio.rawValue): outside is drawn")
            XCTAssertGreaterThan(outside.red, 40, "\(ratio.rawValue): the preview still shows under the dim")
            XCTAssertLessThan(outside.red, 130, "\(ratio.rawValue): and it is dimmed, not untouched")
            XCTAssertEqual(outside.green, 0, "\(ratio.rawValue): the dim is black, so it adds no colour")
            XCTAssertEqual(
                outside.blue, outside.red,
                accuracy: 12,
                "\(ratio.rawValue): the dim is neutral — it scales the colour, it does not tint it"
            )
            XCTAssertEqual(
                Double(outside.red) / 255,
                1 - CameraStageFrame.dimOpacity,
                accuracy: 0.06,
                "\(ratio.rawValue): 65 % black over the preview leaves 35 % of it"
            )
        }
    }

    /// The frame's edge is a hairline, not a border: one point of white at 40 % on the boundary.
    func testTheFramesEdgeIsAHairline() throws {
        let stage = CameraStageFrame.make(ratio: .threeFour, screen: screen, safeTop: safeTop)
        let bitmap = try render(ratio: .threeFour)
        let edge = try XCTUnwrap(pixel(in: bitmap, at: CGPoint(x: stage.frame.midX, y: stage.frame.minY + 0.5)))
        let outside = try XCTUnwrap(pixel(in: bitmap, at: CGPoint(x: stage.frame.midX, y: stage.frame.minY - 4)))
        XCTAssertGreaterThan(
            edge.green, outside.green + 40,
            "the edge is brighter than the dim it separates: white over the photo, not a seam"
        )
        XCTAssertLessThan(edge.green, 255, "and it is 40 %, not a solid white rule")
    }

    /// A guide pushed hard against the frame's edge is clipped, not wrapped: the line art stops at the photo.
    func testATransformedGuideIsClippedToTheFrame() throws {
        for ratio in CameraAspectRatio.allCases {
            let stage = CameraStageFrame.make(ratio: ratio, screen: screen, safeTop: safeTop)
            let bitmap = try render(ratio: ratio, withGuide: true)
            var spilledPastFrame = 0
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    guard let pixel = bitmap.color(x: x, y: y) else { continue }
                    let point = CGPoint(x: CGFloat(x) / renderScale, y: CGFloat(y) / renderScale)
                    guard !stage.frame.contains(point) else { continue }
                    // Outside the frame everything is the dimmed magenta: a white guide stroke would be grey.
                    if pixel.red > 150, pixel.green > 150, pixel.blue > 150 {
                        spilledPastFrame += 1
                    }
                }
            }
            XCTAssertEqual(
                spilledPastFrame, 0,
                "\(ratio.rawValue): \(spilledPastFrame) guide pixels are drawn outside the photo"
            )
        }
    }

    // MARK: Helpers

    private func render(ratio: CameraAspectRatio, withGuide: Bool = false) throws -> APBitmap {
        let model = CameraViewModel(camera: RatioStubCamera(), settingsStore: InMemoryCameraSettingsStore())
        model.coordinator.onPermissionResult(.authorized)
        model.setAspectRatio(ratio)
        if withGuide {
            model.setGuideOpacity(1)
            model.setGuideLineColor(.black)
            model.commitGuideGesture(
                GuideTransform.Delta(scale: 2.5, rotation: .degrees(24), translation: CGSize(width: 0, height: 220))
            )
        }
        var guide: NativePose? = withGuide
            ? NativePose(
                id: "clip-check",
                name: "Jumping Jack",
                category: "Standing",
                imageURL: nil,
                instructions: [],
                isSaved: false
            )
            : nil
        let screen = CameraScreen(
            guide: Binding(get: { guide }, set: { guide = $0 }),
            poseService: PreviewPoseService(),
            model: model
        )
        let stage = CameraStageFrame.make(ratio: ratio, screen: self.screen, safeTop: safeTop)
        let canvas = CameraCanvas(
            model: model,
            guide: guide,
            isAuthorized: true,
            stage: stage,
            onClose: {},
            previewOverride: AnyView(previewColour)
        )
        _ = screen // the screen's own wiring is asserted elsewhere; the canvas is the subject here
        let probe = APViewProbe(
            canvas
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea(),
            size: self.screen,
            scale: renderScale
        )
        let bitmap = probe.capture()
        probe.tearDown()
        return bitmap
    }

    private func pixel(in bitmap: APBitmap, at point: CGPoint) -> APPixel? {
        let x = Int((point.x * renderScale).rounded())
        let y = Int((point.y * renderScale).rounded())
        return bitmap.color(x: x, y: y)
    }
}
