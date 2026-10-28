import XCTest
@testable import iosApp

private let sessionPose = NativePose(
    id: "session-pose-1",
    name: "Session Pose",
    category: "Standing",
    imageURL: URL(string: "https://example.com/session.jpg"),
    instructions: ["Step one"],
    isSaved: false
)

private let credentialsA = SessionCredentials(accessToken: "access-a", refreshToken: "refresh-a")
private let credentialsB = SessionCredentials(accessToken: "access-b", refreshToken: "refresh-b")

private final class PosesTestTokenStorage: TokenStoring, @unchecked Sendable {
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials?) { self.credentials = credentials }
    func saveCredentials(_ credentials: SessionCredentials) { self.credentials = credentials }
    func loadCredentials() -> SessionCredentials? { credentials }
    func clearCredentials() { credentials = nil }
}

/// Holds the first `poses` answer until the test releases it, so the answer can be made to land after
/// a session change. Later loads answer immediately.
private final class GatedPoseService: PoseServing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[NativePose], Never>?
    private var calls = 0
    let firstAnswer: [NativePose]
    let laterAnswers: [NativePose]

    init(firstAnswer: [NativePose], laterAnswers: [NativePose]) {
        self.firstAnswer = firstAnswer
        self.laterAnswers = laterAnswers
    }

    var callCount: Int { lock.withLock { calls } }

    func poses(query: String?) async throws -> [NativePose] {
        let shouldHold: Bool = lock.withLock {
            calls += 1
            return calls == 1
        }
        guard shouldHold else { return laterAnswers }
        return await withCheckedContinuation { (pending: CheckedContinuation<[NativePose], Never>) in
            lock.withLock { continuation = pending }
        }
    }

    func pose(id: String) async throws -> NativePose { firstAnswer[0] }

    func releaseFirst(_ value: [NativePose]) {
        let pending: CheckedContinuation<[NativePose], Never>? = lock.withLock {
            let held = continuation
            continuation = nil
            return held
        }
        pending?.resume(returning: value)
    }
}

/// Holds every bookmark call until the test releases that specific call, so two accounts' requests can
/// be in flight at the same time.
private final class GatedBookmarkService: PoseBookmarkServing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var saves = 0
    private var unsaves = 0

    var callCount: Int { lock.withLock { saves + unsaves } }
    var saveCallCount: Int { lock.withLock { saves } }
    var unsaveCallCount: Int { lock.withLock { unsaves } }

    func savePose(poseId: String) async throws {
        lock.withLock { saves += 1 }
        await hold()
    }

    func unsavePose(poseId: String) async throws {
        lock.withLock { unsaves += 1 }
        await hold()
    }

    private func hold() async {
        await withCheckedContinuation { (pending: CheckedContinuation<Void, Never>) in
            lock.withLock { continuations.append(pending) }
        }
    }

    /// Releases the oldest held call, in call order.
    func releaseNext() {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock {
            guard !continuations.isEmpty else { return nil }
            return continuations.removeFirst()
        }
        pending?.resume()
    }
}

/// The two session-scope Low bugs from ARCH-261029 P2, both ordinary flows: a community load that was
/// on the wire when the session changed, and a save that was on the wire when the session changed.
@MainActor
final class PosesSessionBoundaryTests: XCTestCase {
    /// A community load discarded across a session boundary must not leave the list in `.loading`
    /// forever: the answer belongs to the previous Account and is thrown away, so nothing else would
    /// ever settle the state. The feed holds no Account data, so it is re-read.
    @MainActor func testCommunityLoadAcrossASessionChangeSettlesAndReloads() async {
        let boundary = SessionBoundary(tokenStorage: PosesTestTokenStorage(credentials: credentialsA))
        let ours = NativePose(
            id: "b-pose",
            name: "B Pose",
            category: "Standing",
            imageURL: nil,
            instructions: [],
            isSaved: false
        )
        let service = GatedPoseService(firstAnswer: [sessionPose], laterAnswers: [ours])
        let model = PosesViewModel(service: service, boundary: boundary)
        model.filter = .community
        await waitForSessionSubscription(boundary)

        let aLoad = Task { await model.load() }
        await waitUntil("A's community load started") { service.callCount == 1 && isLoading(model) }

        await boundary.signOut()
        await boundary.saveCredentials(credentialsB)

        // The reload the reset kicked must land, so the list is no longer loading.
        await waitUntil("the list settled for B") {
            if case .loaded(let poses) = model.state { return poses.map(\.id) == [ours.id] }
            return false
        }
        XCTAssertGreaterThanOrEqual(service.callCount, 2, "the community feed is re-read after the change")

        // A's answer arrives last and must be discarded, not painted over B's list.
        service.releaseFirst([sessionPose])
        _ = await aLoad.value

        guard case .loaded(let poses) = model.state else {
            return XCTFail("Expected B's loaded community list, got \(model.state)")
        }
        XCTAssertEqual(poses.map(\.id), [ours.id], "A's late community answer must not reach the screen")
    }

    /// A save that was on the wire when the session changed must not release the next session's claim
    /// for the same pose: the in-flight flag is owned per request, not cleared by whoever finishes.
    @MainActor func testLateSaveFromThePreviousAccountCannotClearTheNextAccountsClaim() async {
        let boundary = SessionBoundary(tokenStorage: PosesTestTokenStorage(credentials: credentialsA))
        let bookmarks = GatedBookmarkService()
        let model = PosesViewModel(
            service: GatedPoseService(firstAnswer: [sessionPose], laterAnswers: [sessionPose]),
            bookmarkService: bookmarks,
            boundary: boundary
        )
        await waitForSessionSubscription(boundary)

        // A's save goes on the wire and stays there.
        let aSave = Task { await model.toggleSaved(for: sessionPose) }
        await waitUntil("A's save started") { bookmarks.callCount == 1 && model.isBookmarkInFlight(sessionPose.id) }

        // A signs out, B signs in.
        await boundary.signOut()
        await boundary.saveCredentials(credentialsB)
        await waitUntil("the reset released A's claim") { !model.isBookmarkInFlight(sessionPose.id) }

        // B taps the same pose; its claim is now the only one standing.
        let bSave = Task { await model.toggleSaved(for: sessionPose) }
        await waitUntil("B's save started") { bookmarks.callCount == 2 && model.isBookmarkInFlight(sessionPose.id) }

        // A's request finishes last: its cleanup must not touch B's claim.
        bookmarks.releaseNext()
        let aOutcome = await aSave.value
        XCTAssertEqual(aOutcome, .discarded, "A's answer belongs to A's session")
        XCTAssertTrue(
            model.isBookmarkInFlight(sessionPose.id),
            "A's late completion must not clear B's in-flight claim for the same pose"
        )

        bookmarks.releaseNext()
        let bOutcome = await bSave.value
        XCTAssertEqual(bOutcome, .saved(true))
        XCTAssertFalse(model.isBookmarkInFlight(sessionPose.id))
        XCTAssertEqual(bookmarks.unsaveCallCount, 0, "B's tap must save, not unsave A's save")
    }

    /// The ordinary switcher path for the two account-scoped lists: A's Saved rows are dropped and
    /// re-read for B instead of standing as B's answer.
    @MainActor func testSavedListIsDroppedAndRereadForTheNextAccount() async {
        let boundary = SessionBoundary(tokenStorage: PosesTestTokenStorage(credentials: credentialsA))
        let savedForA = NativePose(
            id: "saved-a",
            name: "Saved by A",
            category: "Standing",
            imageURL: nil,
            instructions: [],
            isSaved: true
        )
        let pending = NativePose(
            id: "saved-b",
            name: "B's saved pose",
            category: "Standing",
            imageURL: nil,
            instructions: [],
            isSaved: true
        )
        let service = GatedPoseService(firstAnswer: [savedForA], laterAnswers: [pending])
        let model = PosesViewModel(service: service, boundary: boundary)
        model.filter = .saved
        await waitForSessionSubscription(boundary)

        let aLoad = Task { await model.load() }
        await waitUntil("A's saved list started") { service.callCount == 1 && isLoading(model) }
        service.releaseFirst([savedForA])
        _ = await aLoad.value
        guard case .loaded(let aRows) = model.state else {
            return XCTFail("Expected A's saved list, got \(model.state)")
        }
        XCTAssertEqual(aRows.map(\.id), [savedForA.id])

        await boundary.signOut()
        await boundary.saveCredentials(credentialsB)

        await waitUntil("B's saved list loaded") {
            if case .loaded(let poses) = model.state { return poses.map(\.id) == [pending.id] }
            return false
        }
        XCTAssertGreaterThanOrEqual(service.callCount, 2, "B's saved list is re-read, not inherited")
    }

    // MARK: - helpers

    private func isLoading(_ model: PosesViewModel) -> Bool {
        if case .loading = model.state { return true }
        return false
    }

    private func waitForSessionSubscription(_ boundary: SessionBoundary, timeout: TimeInterval = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await boundary.subscriberCountForTests() > 0 { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("the model never subscribed to the session boundary")
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("timed out waiting for \(description)")
    }
}
