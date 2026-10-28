import SwiftUI
import UIKit
import XCTest
@testable import iosApp

final class PoseDetailFeatureTests: XCTestCase {
    func testSharedDockScrollInsetMatchesNeoDockTabBarFootprint() {
        XCTAssertEqual(PoseDetailLayoutMetrics.sharedDockScrollInset, 48 + AIPoseSpacing.sm + AIPoseSpacing.lg)
    }

    @MainActor func testTryPoseCallbackPreservesPoseIdentity() {
        var received: NativePose?
        let pose = sampleDetailPose
        let onTryPose: (NativePose) -> Void = { received = $0 }
        onTryPose(pose)
        XCTAssertEqual(received?.id, pose.id)
        XCTAssertEqual(received?.name, pose.name)
    }

    @MainActor func testLocalBookmarkToggleUpdatesViewModelState() async {
        let pose = sampleDetailPose
        let model = PosesViewModel(service: StubPoseService(result: [pose]))
        model.state = .loaded([pose])
        model.updateSavedLocally(poseID: pose.id, saved: true)
        guard case .loaded(let poses) = model.state else { return XCTFail("Expected loaded") }
        XCTAssertTrue(poses[0].isSaved)
    }

    @MainActor func testDetailHeroPhotoFillsItsCardAtThePhotoRatio() throws {
        AppImage.configure()
        PoseAspectRatioCache.shared.resetForTesting()
        defer { PoseAspectRatioCache.shared.resetForTesting() }
        // Portrait and landscape sources: the card must take each photo's own box, and the photo
        // must reach the card's edges (no white gutter left by an inset).
        try assertHeroFillsCard(photoWidth: 900, photoHeight: 1200)
        try assertHeroFillsCard(photoWidth: 1200, photoHeight: 900)
    }

    @MainActor func testDetailHeroPlaceholderSettlesOnFailedLoad() throws {
        AppImage.configure()
        PoseAspectRatioCache.shared.resetForTesting()
        defer { PoseAspectRatioCache.shared.resetForTesting() }
        let poseID = "hero-failure-\(UUID().uuidString)"
        // A file URL that never resolves: the hero's load fails, so the card must stay on the
        // prototype ratio with a still placeholder rather than sweeping forever.
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString)-missing.png")
        let pose = NativePose(
            id: poseID,
            name: "Missing Photo Pose",
            category: "Standing",
            imageURL: missing,
            instructions: ["Step one"],
            isSaved: false
        )

        let screen = HeroHarness(pose: pose)
        defer { screen.tearDown() }
        // Bounded wait for the failure callback to land (the placeholder is what is on screen), then
        // one discarded capture so the window's own appearance animation cannot masquerade as motion.
        screen.spin(seconds: 1.0)
        let first = screen.captureSettled()

        XCTAssertNil(
            PoseAspectRatioCache.shared.ratios[poseID],
            "a failed load must not invent a photo ratio"
        )
        XCTAssertEqual(
            PoseDetailLayoutMetrics.heroAspectRatio(cachedPhotoRatio: PoseAspectRatioCache.shared.ratios[poseID]),
            PoseDetailLayoutMetrics.heroCardAspectRatio,
            accuracy: 0.0001
        )

        // No photo pixels anywhere: the load never produced artwork.
        XCTAssertEqual(first.greenPixelCount(), 0, "a failed load must not paint a photo")

        // Placeholder is drawn at the fallback card size. The tint is sampled from the render itself
        // and then flood-measured, so the assertion does not depend on any colour-space conversion.
        let card = try XCTUnwrap(
            first.paintedCardRect(),
            "placeholder must paint the hero card"
        )
        XCTAssertEqual(card.width, PoseDetailLayoutMetrics.heroCardWidth, accuracy: 8)
        XCTAssertEqual(
            card.height,
            PoseDetailLayoutMetrics.heroCardWidth / PoseDetailLayoutMetrics.heroCardAspectRatio,
            accuracy: 8
        )

        // The card is filled with the placeholder tint, not left as bare page background.
        let interior = try XCTUnwrap(first.color(x: Int(card.midX), y: Int(card.midY)))
        let page = try XCTUnwrap(first.color(x: 4, y: 4))
        XCTAssertLessThan(
            interior.g, page.g - 10,
            "the hero card must show the placeholder tint, not the page background"
        )

        // The settled placeholder is a flat card fill plus the stand-in glyph. The live shimmer is a
        // bright band sweeping across that fill, so a row through the card would vary in lightness:
        // measuring two rows away from the glyph is a timing-independent "no sweep" check.
        for row in [Int(card.minY) + 30, Int(card.maxY) - 30] {
            let range = try XCTUnwrap(
                first.channelRange(alongRow: row, from: Int(card.minX) + 8, to: Int(card.maxX) - 8),
                "the placeholder fill must be measurable"
            )
            XCTAssertLessThanOrEqual(
                range.g, 6,
                "row \(row) across the hero card is not a flat fill: the shimmer is still sweeping"
            )
        }
        // ...and the stand-in glyph is what is drawn, not an empty card.
        XCTAssertGreaterThan(
            first.darkPixelCount(in: card), 200,
            "the failed-load placeholder must draw its stand-in glyph"
        )
    }

    // MARK: - Real PoseDetailScreen render harness

    /// Renders the real `PoseDetailScreen` offscreen at the device width, so the assertions measure
    /// what SwiftUI actually lays out and paints rather than a re-derivation of the metrics.
    @MainActor private func assertHeroFillsCard(photoWidth: Int, photoHeight: Int) throws {
        let photoRatio = CGFloat(photoWidth) / CGFloat(photoHeight)
        let poseID = "hero-render-\(photoWidth)x\(photoHeight)-\(UUID().uuidString)"
        let url = try SolidPhotoFixture.write(width: photoWidth, height: photoHeight)
        defer { try? FileManager.default.removeItem(at: url) }

        // Seed exactly the cache entry the hero asks for: same URL, same decode box. This is the
        // same pipeline call the view makes, so no private Kingfisher API is involved.
        _ = try awaitLoad(url: url)

        let pose = NativePose(
            id: poseID,
            name: "Rendered Hero Pose",
            category: "Standing",
            imageURL: url,
            instructions: ["Step one"],
            isSaved: false
        )
        let screen = HeroHarness(pose: pose)
        defer { screen.tearDown() }
        // KFImage resolves from the cache asynchronously; wait for the hero's own callback.
        XCTAssertNotNil(
            screen.awaitHeroRatio(of: poseID),
            "the hero never reported the loaded photo ratio"
        )
        // Let the card's ratio change finish animating before measuring it.
        let image = screen.captureSettled()

        // (a) the cache now holds the photo's ratio, and the card height follows it.
        let cached = try XCTUnwrap(PoseAspectRatioCache.shared.ratios[poseID])
        XCTAssertEqual(cached, photoRatio, accuracy: 0.01, "hero must cache the photo's own ratio")

        // (b) the artwork reaches the card edges: measure the painted photo.
        let bounds = try XCTUnwrap(image.greenBounds(), "the hero photo was never painted")
        XCTAssertEqual(
            bounds.width,
            PoseDetailLayoutMetrics.heroCardWidth,
            accuracy: 6,
            "the photo must span the full card width, not an inset box"
        )
        XCTAssertEqual(
            bounds.height,
            PoseDetailLayoutMetrics.heroCardWidth / photoRatio,
            accuracy: 8,
            "the card height must follow the photo ratio"
        )
        // Edge samples just inside the card border must be photo, not the card's white surface:
        // this is what an inset (padding) would break. The card corners are rounded (radius 14), so
        // the samples sit on the straight edges instead of the clipped arcs.
        let left = Int(bounds.minX), right = Int(bounds.maxX)
        let top = Int(bounds.minY), bottom = Int(bounds.maxY)
        let midX = (left + right) / 2, midY = (top + bottom) / 2
        for (x, y, edge) in [
            (left + 3, midY, "left"),
            (right - 3, midY, "right"),
            (midX, top + 3, "top"),
            (midX, bottom - 3, "bottom"),
            (left + 16, top + 16, "inset top-left"),
            (right - 16, bottom - 16, "inset bottom-right"),
        ] {
            XCTAssertTrue(
                image.isPhotoPixel(x: x, y: y),
                "the \(edge) edge of the card is not photo: artwork is inset"
            )
        }
        // ...and the card itself is bounded: one point outside must not be photo.
        XCTAssertFalse(
            image.isPhotoPixel(x: left - 2, y: (top + bottom) / 2),
            "photo paint leaked outside the card"
        )

        // The artwork decode box must cover the drawn card, so the photo is never upscaled.
        XCTAssertGreaterThanOrEqual(
            PoseDetailLayoutMetrics.heroArtworkPoints.height,
            bounds.height,
            "hero decode box must cover the drawn card height"
        )
    }

    @MainActor private func awaitLoad(url: URL) throws -> AppImage.Loaded {
        var loaded: AppImage.Loaded?
        var failure: Error?
        Task { @MainActor in
            do { loaded = try await AppImage.load(from: url, points: PoseDetailLayoutMetrics.heroArtworkPoints, contentMode: .fit) }
            catch { failure = error }
        }
        let deadline = Date().addingTimeInterval(5)
        while loaded == nil, failure == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        if let failure { throw failure }
        return try XCTUnwrap(loaded, "pre-seed load timed out")
    }
}

private let sampleDetailPose = NativePose(
    id: "detail-1",
    name: "Detail Pose",
    category: "Standing",
    imageURL: URL(string: "https://example.com/detail.jpg"),
    instructions: ["Step one"],
    isSaved: false
)

private struct StubPoseService: PoseServing {
    let result: [NativePose]
    func poses(query: String?) async throws -> [NativePose] { result }
    func pose(id: String) async throws -> NativePose { result[0] }
}

// MARK: - Offscreen render harness for the real PoseDetailScreen

/// A solid, saturated photo fixture: every pixel inside the hero card is the same colour, so the
/// painted bounds of that colour *are* the artwork's bounds. Inset padding would expose the card's
/// white surface inside those bounds and fail the edge sampling.
private enum SolidPhotoFixture {
    static let green = UIColor(red: 0.05, green: 0.85, blue: 0.25, alpha: 1)

    static func write(width: Int, height: Int) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hero-photo-\(width)x\(height)-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }
}

/// Hosts the production `PoseDetailScreen` in a real window at device width, so what the test
/// measures is what SwiftUI lays out and paints (including its async image callbacks).
@MainActor
private final class HeroHarness {
    private let window: UIWindow
    private let host: UIHostingController<AnyView>
    private let size: CGSize

    init(pose: NativePose) {
        // Tall enough that the whole screen fits without scrolling: a ScrollView that can bounce
        // would make the captured layout depend on timing instead of on the hero card.
        size = CGSize(width: UIScreen.main.bounds.width, height: 2000)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.frame = CGRect(origin: .zero, size: size)
        window.windowLevel = .normal + 1
        let model = PosesViewModel(service: StubPoseService(result: [pose]))
        host = UIHostingController(rootView: AnyView(
            PoseDetailScreen(pose: pose, model: model, onTryPose: { _ in })
        ))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    /// Pumps the main run loop so Kingfisher's completion (and SwiftUI) can make progress.
    func spin(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Waits for the hero's own `onSuccess` to publish a ratio for this pose.
    func awaitHeroRatio(of poseID: String, timeout: TimeInterval = 8) -> CGFloat? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let ratio = PoseAspectRatioCache.shared.ratios[poseID] { return ratio }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return nil
    }

    /// Captures until two consecutive frames are identical (bounded), so measurements never land on
    /// a frame that is still animating in.
    func captureSettled(maxFrames: Int = 60) -> RenderedBitmap {
        var previous = capture()
        for _ in 0..<maxFrames {
            spin(seconds: 0.1)
            let next = capture()
            if next == previous { return next }
            previous = next
        }
        return previous
    }

    func capture() -> RenderedBitmap {
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return RenderedBitmap(image: image) ?? RenderedBitmap(width: Int(size.width), height: Int(size.height))
    }

    func tearDown() {
        window.isHidden = true
        window.rootViewController = nil
    }
}

/// Pixel view of a rendered frame. Coordinates are top-down, like the screen.
private struct RenderedBitmap: Equatable {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    init?(image: UIImage) {
        guard let cg = image.cgImage else { return nil }
        // Locals only: referencing `self.width` inside the closure below would capture `self`
        // before every stored property is initialized.
        let pixelWidth = cg.width
        let pixelHeight = cg.height
        width = pixelWidth
        height = pixelHeight
        var buffer = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        guard drawn else { return nil }
        bytes = buffer
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    func color(x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int)? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        // CoreGraphics drew the image bottom-up.
        let row = height - 1 - y
        let index = (row * width + x) * 4
        guard index >= 0, index + 3 < bytes.count else { return nil }
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]), Int(bytes[index + 3]))
    }

    func isPhotoPixel(x: Int, y: Int) -> Bool {
        guard let pixel = color(x: x, y: y), pixel.a > 200 else { return false }
        return pixel.g >= 150 && pixel.r <= 120 && pixel.b <= 140
    }

    func greenPixelCount() -> Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where isPhotoPixel(x: x, y: y) { count += 1 }
        }
        return count
    }

    /// The hero card's rectangle: the longest contiguous run of rows that are solidly painted inside
    /// the widest painted column band. Measured from the render itself, so it does not depend on the
    /// card's tint (shimmer gradient included), the colour space, or where SwiftUI placed the card.
    func paintedCardRect() -> CGRect? {
        guard let page = color(x: 2, y: 2) else { return nil }
        func isPainted(_ x: Int, _ y: Int) -> Bool {
            guard let pixel = color(x: x, y: y), pixel.a > 200 else { return false }
            return abs(pixel.r - page.r) > 10 || abs(pixel.g - page.g) > 10 || abs(pixel.b - page.b) > 10
        }
        func longestRun(_ indices: [Int]) -> (first: Int, last: Int)? {
            var best: (first: Int, last: Int)?
            var runStart: Int?
            var previous: Int?
            for index in indices {
                if let previous, index == previous + 1 {
                    // still in the run
                } else {
                    if let start = runStart, let last = previous,
                       last - start > (best.map { $0.last - $0.first } ?? -1) {
                        best = (start, last)
                    }
                    runStart = index
                }
                previous = index
            }
            if let start = runStart, let last = previous,
               last - start > (best.map { $0.last - $0.first } ?? -1) {
                best = (start, last)
            }
            return best
        }

        let paintedColumns = (0..<width).filter { x in
            var count = 0
            for y in 0..<height where isPainted(x, y) { count += 1 }
            return count > height / 6
        }
        guard let columns = longestRun(paintedColumns), columns.last - columns.first > width / 2 else {
            return nil
        }
        let cardWidth = columns.last - columns.first + 1

        let solidRows = (0..<height).filter { y in
            var count = 0
            for x in columns.first...columns.last where isPainted(x, y) { count += 1 }
            return count > cardWidth / 2
        }
        guard let rows = longestRun(solidRows), rows.last - rows.first > 50 else { return nil }
        return CGRect(x: columns.first, y: rows.first, width: cardWidth, height: rows.last - rows.first + 1)
    }

    /// Per-channel spread along one row: 0 for a flat fill, large when a gradient band crosses it.
    func channelRange(alongRow y: Int, from x0: Int, to x1: Int) -> (r: Int, g: Int, b: Int)? {
        var minR = 255, maxR = 0, minG = 255, maxG = 0, minB = 255, maxB = 0
        var sampled = 0
        for x in Swift.max(0, x0)...Swift.max(0, x1) {
            guard let pixel = color(x: x, y: y), pixel.a > 200 else { continue }
            sampled += 1
            minR = Swift.min(minR, pixel.r); maxR = Swift.max(maxR, pixel.r)
            minG = Swift.min(minG, pixel.g); maxG = Swift.max(maxG, pixel.g)
            minB = Swift.min(minB, pixel.b); maxB = Swift.max(maxB, pixel.b)
        }
        guard sampled > 0 else { return nil }
        return (maxR - minR, maxG - minG, maxB - minB)
    }

    /// Count of clearly darker-than-fill pixels inside `rect` (the placeholder glyph).
    func darkPixelCount(in rect: CGRect) -> Int {
        var count = 0
        let x0 = Swift.max(0, Int(rect.minX)), x1 = Swift.min(width, Int(rect.maxX))
        let y0 = Swift.max(0, Int(rect.minY)), y1 = Swift.min(height, Int(rect.maxY))
        guard x0 < x1, y0 < y1 else { return 0 }
        for y in y0..<y1 {
            for x in x0..<x1 {
                guard let pixel = color(x: x, y: y), pixel.a > 200 else { continue }
                if pixel.r < 170, pixel.g < 170, pixel.b < 170 { count += 1 }
            }
        }
        return count
    }

    /// Bounding box of the painted photo (nil when no artwork was drawn).
    func greenBounds() -> CGRect? { bounds(where: isPhotoPixel) }

    private func bounds(where matches: (Int, Int) -> Bool) -> CGRect? {
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<height {
            for x in 0..<width where matches(x, y) {
                minX = Swift.min(minX, x)
                maxX = Swift.max(maxX, x)
                minY = Swift.min(minY, y)
                maxY = Swift.max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The pixels inside `rect`, for frame-to-frame comparison.
    func cropCard(_ rect: CGRect) -> [UInt8] {
        var pixels: [UInt8] = []
        let x0 = Swift.max(0, Int(rect.minX)), x1 = Swift.min(width, Int(rect.maxX))
        let y0 = Swift.max(0, Int(rect.minY)), y1 = Swift.min(height, Int(rect.maxY))
        guard x0 < x1, y0 < y1 else { return pixels }
        pixels.reserveCapacity((x1 - x0) * (y1 - y0) * 4)
        for y in y0..<y1 {
            for x in x0..<x1 {
                guard let pixel = color(x: x, y: y) else { continue }
                pixels.append(contentsOf: [UInt8(pixel.r), UInt8(pixel.g), UInt8(pixel.b), UInt8(pixel.a)])
            }
        }
        return pixels
    }
}
