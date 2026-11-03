import AVFoundation
import ImageIO
import SwiftUI
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
    ///
    /// The size under test is the one the camera *displays*, not the one it stores: a portrait capture is
    /// a landscape 4032×3024 buffer carrying an EXIF orientation, so the picture is 3024×4032. The old
    /// version of this test fed the display size while claiming it was "the sensor size the camera
    /// writes", which is exactly the mistake the crop itself made.
    func testTheCaptureCropHasTheSameRatioAsTheViewportFrame() throws {
        let photo = try CameraCaptureFixture.decode(CameraCaptureFixture.jpeg(orientation: .right))
        XCTAssertEqual(photo.size, CGSize(width: 3024, height: 4032), "the tag is what makes this portrait")
        for ratio in CameraAspectRatio.allCases {
            let frame = CameraViewportFrame.rect(for: ratio, in: CGSize(width: 393, height: 852))
            let crop = CameraAspectCrop.rect(for: ratio, imageSize: photo.size)
            XCTAssertEqual(
                crop.width / crop.height,
                frame.width / frame.height,
                accuracy: 0.0005,
                "\(ratio.rawValue): the saved crop and the framed preview describe the same picture"
            )
            XCTAssertLessThanOrEqual(crop.maxX, photo.size.width, "the crop stays inside the picture")
            XCTAssertLessThanOrEqual(crop.maxY, photo.size.height, "the crop stays inside the picture")
        }
    }

    /// The default ratio is the sensor's own: a 3:4 capture is saved untouched, no re-encode, no quality
    /// loss — measured on the *displayed* size, and with the raw buffer shape asserted to be the wrong
    /// space (so this test cannot go back to agreeing with the old bug).
    func testACaptureAlreadyMatchingTheRatioNeedsNoCrop() throws {
        let picture = try CameraCaptureFixture.decode(CameraCaptureFixture.jpeg(orientation: .right)).size
        XCTAssertFalse(CameraAspectCrop.needsCrop(ratio: .threeFour, imageSize: picture))
        XCTAssertEqual(
            CameraAspectCrop.rect(for: .threeFour, imageSize: picture),
            CGRect(origin: .zero, size: picture)
        )
        // The other two ratios do change the file — that is exactly why the preview has to show it.
        XCTAssertTrue(CameraAspectCrop.needsCrop(ratio: .oneOne, imageSize: picture))
        XCTAssertTrue(CameraAspectCrop.needsCrop(ratio: .nineSixteen, imageSize: picture))

        // A raw buffer is 4:3 landscape. Reading the ratio off it is the old defect, in one line.
        let raw = CameraCaptureFixture.rawSize
        XCTAssertEqual(raw, CGSize(width: 4032, height: 3024))
        XCTAssertTrue(
            CameraAspectCrop.needsCrop(ratio: .threeFour, imageSize: raw),
            "a 3:4 portrait picture is not 4:3 landscape: the buffer shape is not the picture's shape"
        )
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

// MARK: - The photo is the frame: nothing is painted on the bars

/// What the canvas actually paints, per ratio.
///
/// The framing math was already asserted; this renders `CameraScreen.cameraCanvas` at a known size and
/// looks at the pixels. The black bars are not part of the picture the shutter saves, so nothing belonging
/// to the photo may be painted there: the old canvas drew the scrims full-bleed and let a scaled or dragged
/// pose reference (box-limited, but not clipped) spill over the bars.
@MainActor
final class CameraCanvasFramingTests: XCTestCase {
    private let canvasSize = CGSize(width: 393, height: 760)
    private let renderScale: CGFloat = 2

    func testTheCanvasPaintsNothingOnTheBarsForEveryRatio() throws {
        for ratio in CameraAspectRatio.allCases {
            let probe = APViewProbe(
                try canvas(ratio: ratio),
                size: canvasSize,
                scale: renderScale
            )
            let bitmap = probe.capture()
            probe.tearDown()

            let frame = CameraViewportFrame.rect(for: ratio, in: canvasSize)
            // The frame's own edge is antialiased, and the guide is clipped *at* it: a pixel within 2 pt
            // of the edge is edge, not spill.
            let allowed = frame.insetBy(dx: -2, dy: -2)

            var outside: [(x: Int, y: Int)] = []
            var inside = 0
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    guard let pixel = bitmap.color(x: x, y: y) else { continue }
                    // Ink is anything clearly brighter than the canvas background (the guide's strokes and
                    // the thirds grid: white, or white at 30 %).
                    let luminance = (pixel.red * 299 + pixel.green * 587 + pixel.blue * 114) / 1000
                    guard luminance >= 60 else { continue }
                    let point = CGPoint(x: CGFloat(x) / renderScale, y: CGFloat(y) / renderScale)
                    if allowed.contains(point) {
                        inside += 1
                    } else {
                        outside.append((x, y))
                    }
                }
            }

            XCTAssertGreaterThan(
                inside, 200,
                "\(ratio.rawValue): the reference and the grid are painted inside the photo — otherwise this test proves nothing"
            )
            XCTAssertTrue(
                outside.isEmpty,
                "\(ratio.rawValue): \(outside.count) painted pixels sit on the black bars, e.g. \(outside.prefix(5)) — "
                    + "the photo frame is \(frame) in \(canvasSize)"
            )
        }
    }

    /// A guide pushed hard against the frame's edge is clipped, not wrapped: the strokes stop at the frame
    /// and the picture keeps its own edge. (The check above proves nothing is outside; this proves the
    /// clipping does not also swallow the guide.)
    func testATransformedGuideIsStillDrawnInsideTheFrame() throws {
        let ratio = CameraAspectRatio.nineSixteen
        let probe = APViewProbe(try canvas(ratio: ratio), size: canvasSize, scale: renderScale)
        let bitmap = probe.capture()
        probe.tearDown()

        let frame = CameraViewportFrame.rect(for: ratio, in: canvasSize)
        let guideBand = CGRect(
            x: frame.minX,
            y: frame.midY - frame.height * 0.1,
            width: frame.width,
            height: frame.height * 0.2
        )
        var ink = 0
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                guard let pixel = bitmap.color(x: x, y: y) else { continue }
                let luminance = (pixel.red * 299 + pixel.green * 587 + pixel.blue * 114) / 1000
                guard luminance >= 60 else { continue }
                let point = CGPoint(x: CGFloat(x) / renderScale, y: CGFloat(y) / renderScale)
                if guideBand.contains(point) { ink += 1 }
            }
        }
        XCTAssertGreaterThan(ink, 100, "the guide is still visible where the user put it")
    }

    /// The camera and the canvas under test: no session, no permission prompt, just the framing.
    private func canvas(ratio: CameraAspectRatio) throws -> some View {
        let model = CameraViewModel(camera: RatioStubCamera())
        model.coordinator.onPermissionResult(.authorized)
        model.setAspectRatio(ratio)
        model.setGuideOpacity(1)
        model.setGuideLineColor(.white)
        if !model.isGridVisible { model.toggleGrid() }
        // The reference at the far end of its scale range, rotated and dragged towards the frame's edge:
        // exactly the state the review says used to paint over the bars.
        model.commitGuideGesture(
            GuideTransform.Delta(scale: 2.5, rotation: .degrees(24), translation: CGSize(width: 0, height: 220))
        )
        let pose = NativePose(
            id: "clip-check",
            name: "Jumping Jack",
            category: "Standing",
            imageURL: nil,
            instructions: [],
            isSaved: false
        )
        var guide: NativePose? = pose
        let screen = CameraScreen(
            guide: Binding(get: { guide }, set: { guide = $0 }),
            poseService: PreviewPoseService(),
            model: model
        )
        // `CameraScreen.body` sets both of these; rendering the canvas on its own inherits neither. Without
        // the dark scheme the tokens resolve to their light values, and without ignoring the safe area the
        // canvas sits below the status bar and the probe's white window shows through above it.
        return screen.cameraCanvas(size: canvasSize)
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()
    }
}
