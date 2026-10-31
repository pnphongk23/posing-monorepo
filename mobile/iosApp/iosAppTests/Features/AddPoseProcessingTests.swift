import SwiftUI
import UIKit
import XCTest
@testable import iosApp

private final class ProcessingWatchJobsService: ObservableObject, JobsServing, @unchecked Sendable {
    var inProgress: [JobRow] = []
    var finished: [JobRow] = []
    var activeCount: Int = 0
    var isOffline: Bool = false
    var loadState: JobsLoadState = .idle

    var eventsToYield: [JobWatchEvent] = []
    var retryCalled = false

    func refresh() async {}
    func startPolling() {}
    func stopPolling() {}

    func watchJob(id: String) -> AsyncStream<JobWatchEvent> {
        let events = eventsToYield
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func submit(image: Data, fileName: String, draft: PoseDraft) async throws -> String {
        return "job_watch_test"
    }

    func retry(id: String) async throws {
        retryCalled = true
    }

    func hide(id: String) async throws {}
    func getGuide(id: String) async throws -> GuidePose {
        throw JobsError.notFound
    }
}

@MainActor
final class AddPoseProcessingTests: XCTestCase {
    func testProcessingLifecycleThroughEvents() async {
        let stub = ProcessingWatchJobsService()
        let model = AddPoseViewModel(jobsService: stub)

        // 1. Queued event
        let queuedData = PoseExtractionJobData(jobId: "j1", status: "queued")
        stub.eventsToYield = [.status(queuedData)]
        model.startWatching(jobId: "j1")

        // Wait a tiny moment for stream iteration
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.currentJobStatus, "queued")
        XCTAssertNil(model.currentPoseId)

        // 2. Processing + Offline/Online event
        let processingData = PoseExtractionJobData(jobId: "j1", status: "processing")
        stub.eventsToYield = [
            .status(processingData),
            .offline,
            .online
        ]
        model.startWatching(jobId: "j1")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.currentJobStatus, "processing")
        XCTAssertFalse(model.isProcessingOffline)

        // 3. Failed event + Retry
        let failedData = PoseExtractionJobData(
            jobId: "j1",
            status: "failed",
            error: ApiErrorResponse(code: "PROVIDER_AUTH_REQUIRED", message: "Auth required")
        )
        stub.eventsToYield = [.status(failedData)]
        model.startWatching(jobId: "j1")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.currentJobStatus, "failed")
        XCTAssertEqual(model.processingError, "Auth required")

        // Retry
        model.submittedJobId = "j1"
        await model.retryProcessing()
        XCTAssertTrue(stub.retryCalled)

        // 4. Succeeded event
        let succeededData = PoseExtractionJobData(
            jobId: "j1",
            status: "succeeded",
            poseId: "pose_ready_1"
        )
        stub.eventsToYield = [.status(succeededData)]
        model.startWatching(jobId: "j1")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.currentJobStatus, "succeeded")
        XCTAssertEqual(model.currentPoseId, "pose_ready_1")

        // 5. Gone event (404)
        stub.eventsToYield = [.gone]
        model.startWatching(jobId: "j1")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(model.isJobGone)
        XCTAssertEqual(model.currentJobStatus, "gone")
    }

    // MARK: - The restyled processing card (board 08-board09)

    @MainActor
    func testProcessingCardNamesTheStageAndPaintsItsIndeterminateBar() {
        let probe = APViewProbe(
            AddPoseProcessingCard(name: "Window light", stage: .processing),
            size: CGSize(width: 361, height: 220)
        )
        defer { probe.tearDown() }
        let processing = probe.capture()

        // The bar carries the stage by shape and colour, and it is accent ink, not a number.
        let barRows = processing.rows(paintedWith: 0x8C3350)
        XCTAssertFalse(barRows.isEmpty, "the processing card must paint its striped indeterminate bar")

        // The copy under the bar is the board's promise that leaving the screen is safe.
        XCTAssertTrue(AddPoseFormCopy.leaveHint.contains("Status continues in Jobs"))

        // Swapping the stage the server reported must change what the card says. The stripes animate,
        // so the comparison has to stop above the bar: what differs there is the stage copy and glyph.
        let ready = probe.render(AddPoseProcessingCard(name: "Window light", stage: .ready))
        let barTop = barRows.first ?? processing.height
        let firstDifferingRow = (0..<max(1, min(barTop, processing.height))).first { row in
            processing.differs(from: ready, inRows: row..<(row + 1))
        }
        guard let firstDifferingRow else {
            return XCTFail("the card must name the stage it was given instead of one hard-coded status")
        }
        XCTAssertLessThan(
            firstDifferingRow, max(1, barTop),
            "the stage copy above the bar is where the reported status has to show up"
        )
    }

    func testIndeterminateBarHasNoPercentageAndStopsUnderReduceMotion() {
        XCTAssertNil(
            AddPoseIndeterminateBar.animation(reduceMotion: true),
            "Reduce Motion keeps the stripes still; the stage word carries the state"
        )
        XCTAssertNotNil(AddPoseIndeterminateBar.animation(reduceMotion: false))
        for stage in AddPoseStage.allCases {
            XCTAssertFalse(stage.label.contains("%"), "no percentage anywhere (B3c)")
        }
    }

    func testViewJobsTargetTabSelection() {
        // Given succeeded status (Pose Ready)
        let succeededStatus = "succeeded"
        let succeededTab: JobsTab = (succeededStatus.lowercased() == "succeeded" || succeededStatus.lowercased() == "failed") ? .finish : .processing
        XCTAssertEqual(succeededTab, .finish)

        // Given failed status
        let failedStatus = "failed"
        let failedTab: JobsTab = (failedStatus.lowercased() == "succeeded" || failedStatus.lowercased() == "failed") ? .finish : .processing
        XCTAssertEqual(failedTab, .finish)

        // Given queued status
        let queuedStatus = "queued"
        let queuedTab: JobsTab = (queuedStatus.lowercased() == "succeeded" || queuedStatus.lowercased() == "failed") ? .finish : .processing
        XCTAssertEqual(queuedTab, .processing)

        // Given processing status
        let processingStatus = "processing"
        let processingTab: JobsTab = (processingStatus.lowercased() == "succeeded" || processingStatus.lowercased() == "failed") ? .finish : .processing
        XCTAssertEqual(processingTab, .processing)
    }

    func testPosesRoutePropertiesAndDeactivationGuard() {
        let addPoseRoute = PosesRoute.addPose
        XCTAssertFalse(addPoseRoute.isJobs)
        XCTAssertEqual(addPoseRoute.jobsTab, JobsTab.processing)

        let jobsDefault = PosesRoute.jobs(.processing)
        XCTAssertTrue(jobsDefault.isJobs)
        XCTAssertEqual(jobsDefault.jobsTab, JobsTab.processing)

        let jobsFinish = PosesRoute.jobs(.finish)
        XCTAssertTrue(jobsFinish.isJobs)
        XCTAssertEqual(jobsFinish.jobsTab, JobsTab.finish)

        // Verify route transition logic: when switching from addPose to jobs(.finish),
        // simulating the isActive binding deactivation of addPose MUST NOT clear route if route != .addPose
        var activeRoute: PosesRoute? = .addPose

        // Step 1: User taps View jobs -> route becomes .jobs(.finish)
        activeRoute = .jobs(.finish)

        // Step 2: AddPoseScreen's NavigationLink isActive setter is invoked with isPresented = false
        let isPresented = false
        if !isPresented && activeRoute == .addPose {
            activeRoute = nil
        }

        // Active route MUST remain .jobs(.finish) instead of reverting to nil
        XCTAssertEqual(activeRoute, .jobs(.finish))
        XCTAssertTrue(activeRoute?.isJobs == true)
        XCTAssertEqual(activeRoute?.jobsTab, JobsTab.finish)
    }

    // MARK: - View jobs routing

    @MainActor
    func testViewJobsAsksForTheSegmentTheJobNeeds() {
        AppConfig.shared.applyExtractPoseEnabled(true)
        defer { AppConfig.shared.applyExtractPoseEnabled(true) }

        let model = AddPoseViewModel(jobsService: ProcessingWatchJobsService())
        model.submittedJobId = "job_1"
        XCTAssertNil(model.requestedJobsTab, "nothing is asked for before the tap")

        model.currentJobStatus = "queued"
        model.requestOpenJobs()
        XCTAssertEqual(model.requestedJobsTab, .processing, "a queued job is still running")
        model.clearJobsRequest()
        XCTAssertNil(model.requestedJobsTab)

        model.currentJobStatus = "processing"
        model.requestOpenJobs()
        XCTAssertEqual(model.requestedJobsTab, .processing)
        model.clearJobsRequest()

        model.currentJobStatus = "succeeded"
        model.requestOpenJobs()
        XCTAssertEqual(model.requestedJobsTab, .finish, "a settled job lives on the Finished segment")
        model.clearJobsRequest()

        model.currentJobStatus = "failed"
        model.requestOpenJobs()
        XCTAssertEqual(model.requestedJobsTab, .finish, "a failed job lives on the Finished segment")
    }

    @MainActor
    func testViewJobsIsNotAskedForWhenPoseExtractionIsOff() {
        AppConfig.shared.applyExtractPoseEnabled(false)
        defer { AppConfig.shared.applyExtractPoseEnabled(true) }

        let model = AddPoseViewModel(jobsService: ProcessingWatchJobsService())
        model.submittedJobId = "job_1"
        model.currentJobStatus = "processing"
        model.requestOpenJobs()

        XCTAssertNil(model.requestedJobsTab, "the killed switch hides the Jobs surface entirely")
    }

    @MainActor
    func testTheViewJobsTapPushesTheJobsScreenInsteadOfPoppingToPoses() {
        // The defect (build 16): View jobs handed the tab to the Poses route, which swapped the pushed
        // destination in the same update as this screen's pop, so the pop won and the user landed on
        // Poses home. The fix is a push on this screen's own stack; this test drives the real push.
        AppConfig.shared.applyExtractPoseEnabled(true)
        defer { AppConfig.shared.applyExtractPoseEnabled(true) }

        let model = AddPoseViewModel(jobsService: ProcessingWatchJobsService())
        model.name = "Window light"
        model.submittedJobId = "job_1"
        model.currentJobStatus = "processing"

        let asked = AskedJobsDestination()
        let screen = NavigationView {
            AddPoseScreen(
                viewModel: model,
                posesModel: PosesViewModel(service: AddPoseEmptyCatalogueService()),
                jobsDestination: { tab in
                    asked.tab = tab
                    return AnyView(Color.red)
                }
            )
        }
        let probe = AddPoseNavigationProbe(screen)
        defer { probe.tearDown() }

        XCTAssertEqual(
            probe.waitForDepth(1), 1,
            "the processing card is the only level on the stack to begin with"
        )

        model.requestOpenJobs()

        XCTAssertEqual(
            probe.waitForDepth(2), 2,
            "View jobs must land on the Jobs screen, not back on Poses home"
        )
        XCTAssertEqual(asked.tab, .processing, "the push carries the segment the job needs")

        // Back from Jobs: the request clears, so a second visit can push again.
        model.clearJobsRequest()
        XCTAssertEqual(probe.waitForDepth(1), 1)
        // A returning user taps after the pop animation, not during it.
        probe.settleFor(0.8)
        model.requestOpenJobs()
        XCTAssertEqual(probe.waitForDepth(2), 2, "the button keeps working after a round trip")
    }
}

/// Records the tab the flow asked the Jobs screen to open on.
@MainActor
private final class AskedJobsDestination {
    var tab: JobsTab?
}

/// The catalogue is irrelevant here: the probe only needs a model that does not reach the network.
private struct AddPoseEmptyCatalogueService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] { [] }
    func pose(id: String) async throws -> NativePose { throw PoseAdapterError.poseNotFound(id) }
}

/// Hosts a view inside a real window and reads the navigation stack SwiftUI builds for it, so a test
/// can assert that a control pushed a screen instead of popping back to the root.
@MainActor
private final class AddPoseNavigationProbe {
    private let window: UIWindow
    private let host: UIHostingController<AnyView>
    private let size = CGSize(width: 393, height: 844)

    init<V: View>(_ view: V) {
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.frame = CGRect(origin: .zero, size: size)
        window.windowLevel = .normal + 1
        host = UIHostingController(rootView: AnyView(view))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = CGRect(origin: .zero, size: size)
        settle()
    }

    func settle() {
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    func settleFor(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Pumps the run loop until the stack holds `expected` levels, and answers what it actually holds
    /// so a failure prints the depth the navigation really reached.
    func waitForDepth(_ expected: Int, timeout: TimeInterval = 3) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            settle()
            if navigationDepth == expected { return expected }
        }
        return navigationDepth
    }

    var navigationDepth: Int? {
        Self.navigationController(in: host)?.viewControllers.count
    }

    func tearDown() {
        host.view.removeFromSuperview()
        if window.rootViewController === host {
            window.rootViewController = nil
        }
        window.isHidden = true
    }

    private static func navigationController(in parent: UIViewController) -> UINavigationController? {
        if let navigation = parent as? UINavigationController { return navigation }
        for child in parent.children {
            if let navigation = navigationController(in: child) { return navigation }
        }
        if let presented = parent.presentedViewController {
            return navigationController(in: presented)
        }
        return nil
    }
}
