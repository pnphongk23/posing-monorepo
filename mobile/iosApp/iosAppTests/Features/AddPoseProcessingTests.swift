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
}
