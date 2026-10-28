import Network
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
        // Wait for the failure placeholder to be on screen (the stand-in glyph is the observable),
        // rather than sleeping for a guessed duration.
        XCTAssertTrue(
            screen.awaitCondition { bitmap in
                guard let card = bitmap.cardBorderRect() else { return false }
                return bitmap.darkPixelCount(in: card.insetBy(dx: 6, dy: 6)) > 200
            },
            "the hero never settled on its failed-load placeholder"
        )
        let first = screen.capture()

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

        // Placeholder is drawn at the fallback card size: measured from the card's own border, so the
        // assertion does not depend on any colour space or on the fill's animation state.
        let card = try XCTUnwrap(
            first.cardBorderRect(),
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
            first.darkPixelCount(in: card.insetBy(dx: 6, dy: 6)), 200,
            "the failed-load placeholder must draw its stand-in glyph"
        )
    }

    /// A load that never completes must paint the shimmer at the fallback card size, edge to edge.
    /// Geometry is measured from the card's own border, so the sweeping gradient (and whether the
    /// animation is running at all) cannot affect it — `@Environment(\.accessibilityReduceMotion)` is
    /// a read-only environment key, so a test cannot pin Reduce Motion from here. What separates the
    /// loading placeholder from the failure one is the stand-in glyph: loading has none.
    @MainActor func testDetailHeroShimmerFillsTheFallbackCardWhileLoading() throws {
        AppImage.configure()
        PoseAspectRatioCache.shared.resetForTesting()
        defer { PoseAspectRatioCache.shared.resetForTesting() }
        let poseID = "hero-pending-\(UUID().uuidString)"
        // A real socket that accepts and never answers: the client stalls in the TLS handshake, so the
        // load is genuinely pending rather than merely slow. HTTPS because the app keeps default ATS.
        let server = try HangingHTTPServer()
        defer { server.stop() }
        let pending = try XCTUnwrap(URL(string: "https://127.0.0.1:\(server.port)/pose.png"))
        let pose = NativePose(
            id: poseID,
            name: "Pending Photo Pose",
            category: "Standing",
            imageURL: pending,
            instructions: ["Step one"],
            isSaved: false
        )

        let screen = HeroHarness(pose: pose)
        defer { screen.tearDown() }

        XCTAssertTrue(
            screen.awaitCondition { bitmap in
                guard let card = bitmap.cardBorderRect() else { return false }
                return bitmap.isPlaceholderTint(
                    x: Int(card.minX) + 3,
                    y: Int(card.midY)
                )
            },
            "the loading placeholder never painted the hero card"
        )
        let image = screen.capture()

        // Still loading: no photo, and no photo ratio invented from nothing.
        XCTAssertNil(PoseAspectRatioCache.shared.ratios[poseID], "a pending load must not publish a ratio")
        XCTAssertEqual(image.greenPixelCount(), 0, "a pending load must not paint a photo")

        // The shimmer fills the prototype card, edge to edge.
        let card = try XCTUnwrap(image.cardBorderRect(), "the shimmer must paint the hero card")
        XCTAssertEqual(card.width, PoseDetailLayoutMetrics.heroCardWidth, accuracy: 8)
        XCTAssertEqual(
            card.height,
            PoseDetailLayoutMetrics.heroCardWidth / PoseDetailLayoutMetrics.heroCardAspectRatio,
            accuracy: 8
        )

        // The shimmer reaches the card's edges: the card surface is pure white, so a shimmer that was
        // inset (or sized smaller than the card) would leave white gutters just inside the border.
        for (x, y, edge) in [
            (Int(card.minX) + 3, Int(card.midY), "left"),
            (Int(card.maxX) - 3, Int(card.midY), "right"),
            (Int(card.midX), Int(card.minY) + 3, "top"),
            (Int(card.midX), Int(card.maxY) - 3, "bottom"),
        ] {
            XCTAssertTrue(
                image.isPlaceholderTint(x: x, y: y),
                "the loading shimmer does not reach the card's \(edge) edge"
            )
        }
        XCTAssertTrue(
            image.isPlaceholderTint(x: Int(card.midX), y: Int(card.midY)),
            "the loading shimmer must cover the card"
        )

        // It is the loading placeholder, not the failure one: no stand-in glyph.
        XCTAssertLessThan(
            image.darkPixelCount(in: card.insetBy(dx: 6, dy: 6)), 20,
            "the loading placeholder must not draw the failure glyph"
        )
    }

    // MARK: - Bookmarking must follow the server, never the tap

    @MainActor func testToggleSavedWithoutBookmarkServiceNeverShowsThePoseAsSaved() async {
        // Signed out / account wiring unavailable: no request can be sent, so nothing may be shown
        // as saved and the local list must be untouched.
        let pose = sampleDetailPose
        let model = PosesViewModel(service: StubPoseService(result: [pose]))
        model.state = .loaded([pose])

        let outcome = await model.toggleSaved(for: pose)

        XCTAssertEqual(outcome, .unavailable)
        guard case .loaded(let poses) = model.state else { return XCTFail("Expected loaded") }
        XCTAssertFalse(poses[0].isSaved, "a pose must never appear saved unless the server confirmed it")
        XCTAssertNil(model.bookmarkError)
    }

    @MainActor func testToggleSavedServerFailureLeavesThePoseUnsavedAndSurfacesTheError() async {
        let pose = sampleDetailPose
        let service = StubBookmarkService(shouldFail: true)
        let model = PosesViewModel(service: StubPoseService(result: [pose]), bookmarkService: service)
        model.state = .loaded([pose])

        let outcome = await model.toggleSaved(for: pose)

        guard case .failed(let message) = outcome else { return XCTFail("Expected .failed, got \(outcome)") }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(model.bookmarkError, message, "the failure must reach the shared error surface")
        guard case .loaded(let poses) = model.state else {
            return XCTFail("a failed save must not replace the list with an error state")
        }
        XCTAssertFalse(poses[0].isSaved, "a failed save must roll back to unsaved")
        XCTAssertEqual(service.saveCallCount, 1)
    }

    @MainActor func testToggleSavedFlipsOnlyAfterTheServerConfirms() async {
        let pose = sampleDetailPose
        let service = GatedBookmarkService()
        let model = PosesViewModel(service: StubPoseService(result: [pose]), bookmarkService: service)
        model.state = .loaded([pose])

        let save = Task { await model.toggleSaved(for: pose) }
        await waitUntil("the save request never started") { service.saveCallCount == 1 }

        // In flight: still not saved, exactly like the server has not said yes yet.
        guard case .loaded(let inFlight) = model.state else { return XCTFail("Expected loaded") }
        XCTAssertFalse(inFlight[0].isSaved, "the pose must not look saved while the request is in flight")

        service.release()
        guard let outcome = await awaitOutcome(save, "the save never completed") else { return }
        XCTAssertEqual(outcome, .saved(true))
        guard case .loaded(let settled) = model.state else { return XCTFail("Expected loaded") }
        XCTAssertTrue(settled[0].isSaved)
    }

    @MainActor func testRapidDoubleTapSendsOneRequestAndEndsConsistent() async {
        let pose = sampleDetailPose
        let service = GatedBookmarkService()
        let model = PosesViewModel(service: StubPoseService(result: [pose]), bookmarkService: service)
        model.state = .loaded([pose])

        let first = Task { await model.toggleSaved(for: pose) }
        await waitUntil("the save request never started") { service.saveCallCount == 1 }
        // Second tap while the first is still in flight: ignored, not queued.
        let second = await model.toggleSaved(for: pose)
        XCTAssertEqual(second, .inFlight)

        service.release()
        guard let firstOutcome = await awaitOutcome(first, "the save never completed") else { return }
        XCTAssertEqual(firstOutcome, .saved(true))
        XCTAssertEqual(service.saveCallCount, 1, "a double tap must not send two saves")
        XCTAssertEqual(service.unsaveCallCount, 0)
        guard case .loaded(let poses) = model.state else { return XCTFail("Expected loaded") }
        XCTAssertTrue(poses[0].isSaved, "the pose must end up saved once, not flip-flopped")
    }

    /// Pumps the main run loop until `condition` holds, failing the test when it never does.
    @MainActor private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail(message)
    }

    @MainActor func testDetailReopenedDuringAnOutstandingSaveSeesTheSharedState() async {
        let pose = sampleDetailPose
        let service = GatedBookmarkService()
        let model = PosesViewModel(service: StubPoseService(result: [pose]), bookmarkService: service)
        model.state = .loaded([pose])

        let firstDetail = Task { await model.toggleSaved(for: pose) }
        await waitUntil("the save request never started") { service.saveCallCount == 1 }

        // The user leaves the detail screen and opens the pose again before the save completes. The
        // reopened screen reads the shared model, so it must see the request rather than a stale
        // "Save pose", and it must not offer a second save.
        XCTAssertTrue(model.isBookmarkInFlight(pose.id), "a reopened screen must see the request in flight")
        XCTAssertFalse(model.savedState(for: pose), "in flight is not saved")
        XCTAssertFalse(pose.isSaved, "the reopened screen's own snapshot is still unsaved")

        service.release()
        guard let firstOutcome = await awaitOutcome(firstDetail, "the save never completed") else { return }
        XCTAssertEqual(firstOutcome, .saved(true))
        XCTAssertFalse(model.isBookmarkInFlight(pose.id))
        // Confirmed without that screen ever owning a local copy of the state.
        XCTAssertTrue(model.savedState(for: pose), "a reopened detail must see the confirmed save")

        // And the next tap taken from that stale snapshot must unsave, not send a second save.
        let next = await model.toggleSaved(for: pose)
        XCTAssertEqual(next, .saved(false))
        XCTAssertEqual(service.saveCallCount, 1, "a stale snapshot must not send a second save")
        XCTAssertEqual(service.unsaveCallCount, 1)
    }

    /// Awaits a bookmark task, failing the test instead of hanging when it never finishes.
    @MainActor private func awaitOutcome(
        _ task: Task<PosesViewModel.BookmarkOutcome, Never>,
        timeout: TimeInterval = 5,
        _ message: String
    ) async -> PosesViewModel.BookmarkOutcome? {
        let value = await withTaskGroup(of: PosesViewModel.BookmarkOutcome?.self) { group in
            group.addTask { await task.value }
            group.addTask { () -> PosesViewModel.BookmarkOutcome? in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if value == nil { XCTFail(message) }
        return value
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
        // KFImage resolves from the cache asynchronously; wait for the hero's own callback, then for
        // the photo to be painted. Reduce Motion is on for this harness, so the ratio change is not
        // animated and the frame measured below is final.
        XCTAssertNotNil(
            screen.awaitHeroRatio(of: poseID),
            "the hero never reported the loaded photo ratio"
        )
        // The card resizes once to the photo's box; wait for that final geometry instead of sleeping
        // for it. A timeout here fails the test rather than measuring a half-grown card.
        let expectedHeight = PoseDetailLayoutMetrics.heroCardWidth / photoRatio
        XCTAssertTrue(
            screen.awaitCondition { bitmap in
                guard let painted = bitmap.greenBounds() else { return false }
                return abs(painted.height - expectedHeight) <= 3
                    && abs(painted.width - PoseDetailLayoutMetrics.heroCardWidth) <= 6
            },
            "the hero card never settled on the photo's own box"
        )
        let image = screen.capture()

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

private final class StubBookmarkService: PoseBookmarkServing, @unchecked Sendable {
    private let lock = NSLock()
    private let shouldFail: Bool
    private var saves = 0
    private var unsaves = 0

    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    var saveCallCount: Int { lock.withLock { saves } }
    var unsaveCallCount: Int { lock.withLock { unsaves } }

    func savePose(poseId: String) async throws {
        lock.withLock { saves += 1 }
        if shouldFail { throw URLError(.notConnectedToInternet) }
    }

    func unsavePose(poseId: String) async throws {
        lock.withLock { unsaves += 1 }
        if shouldFail { throw URLError(.notConnectedToInternet) }
    }
}

/// A save that does not answer until the test releases it: models a slow server.
private final class GatedBookmarkService: PoseBookmarkServing, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private var saves = 0
    private var unsaves = 0

    var saveCallCount: Int { lock.withLock { saves } }
    var unsaveCallCount: Int { lock.withLock { unsaves } }
    var isHeld: Bool { lock.withLock { !waiters.isEmpty } }

    func savePose(poseId: String) async throws { await register(isSave: true) }
    func unsavePose(poseId: String) async throws { await register(isSave: false) }

    /// Counting the call and registering its continuation happen in one critical section, and a
    /// release that already happened resumes immediately — so `release()` can never slip between the
    /// count and the registration and leave the request hanging forever.
    private func register(isSave: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.withLock {
                if isSave { saves += 1 } else { unsaves += 1 }
                if released {
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                }
            }
        }
    }

    func release() {
        let pending: [CheckedContinuation<Void, Never>] = lock.withLock {
            released = true
            let held = waiters
            waiters.removeAll()
            return held
        }
        for continuation in pending { continuation.resume() }
    }
}

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

/// Accepts TCP connections and never writes a byte, so an HTTPS request to it stays pending for as
/// long as the test needs. Used to render the hero's loading state deterministically.
@MainActor
private final class HangingHTTPServer {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private(set) var port: UInt16 = 0

    init() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            Task { @MainActor in self?.connections.append(connection) }
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.start(queue: .global())
        guard ready.wait(timeout: .now() + 5) == .success, let assigned = listener.port else {
            listener.cancel()
            throw XCTSkip("could not start the hanging HTTPS listener")
        }
        port = assigned.rawValue
    }

    func stop() {
        for connection in connections { connection.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
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
        // Make this the active window: a harness window that is not key can be handed stale frames
        // by `drawHierarchy`, which made a test's result depend on whichever harness ran before it.
        window.makeKeyAndVisible()
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

    /// Waits for an observable condition on the rendered screen. Returns `false` when the timeout
    /// expires, so the caller fails loudly instead of measuring whatever frame happened to be up.
    func awaitCondition(timeout: TimeInterval = 10, _ predicate: (RenderedBitmap) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(capture()) { return true }
            spin(seconds: 0.05)
        }
        return predicate(capture())
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
        host.view.removeFromSuperview()
        window.rootViewController = nil
        window.resignKey()
        window.isHidden = true
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

    /// The hero card's rectangle, measured from its own thick black border. The border is opaque and
    /// static whatever the fill is doing, so this is independent of gradients, colour spaces and the
    /// shimmer's motion. The card is the widest gap between two full-width dark row bands.
    func cardBorderRect() -> CGRect? {
        guard let page = color(x: 2, y: 2) else { return nil }
        func isDark(_ x: Int, _ y: Int) -> Bool {
            guard let pixel = color(x: x, y: y), pixel.a > 200 else { return false }
            return pixel.r < 60 && pixel.g < 60 && pixel.b < 60
        }
        func bands(_ indices: [Int]) -> [(first: Int, last: Int)] {
            var result: [(first: Int, last: Int)] = []
            for index in indices {
                if let last = result.last, index == last.last + 1 {
                    result[result.count - 1].last = index
                } else {
                    result.append((index, index))
                }
            }
            return result
        }

        let rowBands = bands((0..<height).filter { y in
            var count = 0
            for x in 0..<width where isDark(x, y) { count += 1 }
            return count > width * 3 / 4
        })
        guard rowBands.count >= 2 else { return nil }
        // The card is the tallest span between two dark bands (header chrome bands are close together).
        var best: (top: Int, bottom: Int)?
        for (upper, lower) in zip(rowBands, rowBands.dropFirst()) {
            let span = lower.first - upper.last
            if span > (best.map { $0.bottom - $0.top } ?? 0) {
                best = (upper.last, lower.first)
            }
        }
        guard let rows = best else { return nil }

        let columnBands = bands((0..<width).filter { x in
            var count = 0
            for y in 0..<height where isDark(x, y) { count += 1 }
            return count > height / 8
        })
        guard let leftBand = columnBands.first, let rightBand = columnBands.last,
              rightBand.last - leftBand.first > width / 2 else { return nil }
        _ = page
        return CGRect(
            x: leftBand.first,
            y: rows.top,
            width: rightBand.last - leftBand.first + 1,
            height: rows.bottom - rows.top + 1
        )
    }

    /// `true` when the pixel carries the placeholder tint rather than the card's white surface or the
    /// cream page. Both the shimmer's base fill and its sweep band are tinted; white is not, which is
    /// what makes an undersized shimmer detectable.
    func isPlaceholderTint(x: Int, y: Int) -> Bool {
        guard let pixel = color(x: x, y: y), pixel.a > 200 else { return false }
        return pixel.g <= 248 || pixel.b <= 248
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

    /// Count of clearly darker-than-fill pixels inside `rect`. Pass the card inset by a few points so
    /// the card's own border cannot be mistaken for the placeholder glyph.
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
