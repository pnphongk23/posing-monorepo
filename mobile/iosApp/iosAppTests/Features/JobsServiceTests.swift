import XCTest
@testable import iosApp

private final class TestTokenStorage: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: SessionCredentials?

    init(credentials: SessionCredentials? = nil) {
        self.credentials = credentials
    }

    func saveCredentials(_ credentials: SessionCredentials) {
        lock.lock()
        self.credentials = credentials
        lock.unlock()
    }

    func loadCredentials() -> SessionCredentials? {
        lock.lock()
        defer { lock.unlock() }
        return credentials
    }

    func clearCredentials() {
        lock.lock()
        credentials = nil
        lock.unlock()
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("No MockURLProtocol requestHandler provided")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class JobsServiceTests: XCTestCase {
    private var sessionBoundary: SessionBoundary!
    private var tokenStorage: TestTokenStorage!
    private var urlSession: URLSession!
    private var apiClient: APIClient!
    private var apiService: PoseAPIService!

    override func setUp() {
        super.setUp()
        AppConfig.shared.applyExtractPoseEnabled(true)
        tokenStorage = TestTokenStorage(credentials: SessionCredentials(accessToken: "test_access", refreshToken: "test_refresh"))
        sessionBoundary = SessionBoundary(tokenStorage: tokenStorage)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        urlSession = URLSession(configuration: config)

        apiClient = APIClient(baseURL: "https://test.local", session: urlSession, boundary: sessionBoundary)
        apiService = PoseAPIService(client: apiClient)
    }

    override func tearDown() {
        AppConfig.shared.applyExtractPoseEnabled(true)
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - 1. Model Decoding Tests
    func testDecodeQueuedJobStatus() throws {
        let data = Data(JobsFixtures.queuedJobJSON.utf8)
        let status = try JSONDecoder().decode(PoseExtractionJobStatus.self, from: data)
        XCTAssertEqual(status.data.jobId, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(status.data.status, "queued")
        XCTAssertNil(status.data.poseId)
        XCTAssertNil(status.data.result)
        XCTAssertNil(status.data.error)
    }

    func testDecodeProcessingJobStatus() throws {
        let data = Data(JobsFixtures.processingJobJSON.utf8)
        let status = try JSONDecoder().decode(PoseExtractionJobStatus.self, from: data)
        XCTAssertEqual(status.data.status, "processing")
    }

    func testDecodeSucceededJobStatusWithPoseId() throws {
        let data = Data(JobsFixtures.succeededJobJSON.utf8)
        let status = try JSONDecoder().decode(PoseExtractionJobStatus.self, from: data)
        XCTAssertEqual(status.data.status, "succeeded")
        XCTAssertEqual(status.data.poseId, "550e8400-e29b-41d4-a716-446655440001")
        XCTAssertNotNil(status.data.result)
        XCTAssertEqual(status.data.result?.mimeType, "image/png")
    }

    func testDecodeSucceededJobWithOmittedProcessingTimeAndImages() throws {
        let json = """
        {
          "data": {
            "jobId": "job_omitted",
            "status": "succeeded",
            "poseId": "pose_123",
            "result": {},
            "error": null,
            "updatedAt": "2026-09-26T12:00:05.000Z"
          }
        }
        """
        let status = try JSONDecoder().decode(PoseExtractionJobStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.data.status, "succeeded")
        XCTAssertEqual(status.data.poseId, "pose_123")
        XCTAssertNotNil(status.data.result)
        XCTAssertNil(status.data.result?.processingTimeMs)
        XCTAssertNil(status.data.result?.imageBase64)
        XCTAssertNil(status.data.result?.mimeType)
    }

    func testDecodeFailedJobStatusWithError() throws {
        let data = Data(JobsFixtures.failedJobJSON.utf8)
        let status = try JSONDecoder().decode(PoseExtractionJobStatus.self, from: data)
        XCTAssertEqual(status.data.status, "failed")
        XCTAssertEqual(status.data.error?.code, "PROVIDER_AUTH_REQUIRED")
        XCTAssertEqual(status.data.error?.message, "Provider authentication required")
    }

    func testDecodeExtractionJobList() throws {
        let data = Data(JobsFixtures.extractionJobListJSON.utf8)
        let response = try JSONDecoder().decode(ExtractionJobListResponse.self, from: data)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data.count, 3)

        let items = response.data
        XCTAssertEqual(items[0].status, "processing")
        XCTAssertEqual(items[0].poseDraft?.name, "Active Hero Pose")
        XCTAssertEqual(items[1].status, "succeeded")
        XCTAssertEqual(items[1].thumbnailUrl, "https://example.com/thumb.jpg")
        XCTAssertEqual(items[2].status, "failed")
        XCTAssertEqual(items[2].errorCode, "LINEART_BG_REMOVAL_FAILED")
    }

    func testDecodeExtractionJobListItemWithNullPoseDraft() throws {
        let json = """
        {
          "jobId": "job_null_draft",
          "status": "queued",
          "poseDraft": null,
          "poseId": null,
          "thumbnailUrl": null,
          "errorCode": null,
          "errorMessage": null,
          "createdAt": "2026-09-26T12:00:00Z",
          "updatedAt": "2026-09-26T12:00:00Z"
        }
        """
        let item = try JSONDecoder().decode(ExtractionJobListItem.self, from: Data(json.utf8))
        XCTAssertNil(item.poseDraft)
        let row = JobRow(item: item)
        XCTAssertEqual(row.name, "Untitled Pose")
    }

    func testDecodeGuidePoseDetail() throws {
        let data = Data(JobsFixtures.guidePoseDetailJSON.utf8)
        let response = try JSONDecoder().decode(GuidePoseDetailResponse.self, from: data)
        let guide = response.data
        XCTAssertEqual(guide.poseId, "550e8400-e29b-41d4-a716-446655440003")
        XCTAssertEqual(guide.name, "Completed Warrior Pose")
        XCTAssertEqual(guide.skeletonUrl, "https://example.com/poses/skeleton.png")
        XCTAssertEqual(guide.thumbnailUrl, "https://example.com/poses/thumbnail.png")
    }

    // MARK: - 2. JobRow Status & Action Mapping
    func testJobRowStatusAndActionMapping() {
        let queuedRow = JobRow(jobId: "1", name: "Q", status: .queued)
        XCTAssertEqual(queuedRow.statusLabel, "Queued")
        XCTAssertEqual(queuedRow.action, .none)

        let processingRow = JobRow(jobId: "2", name: "P", status: .processing)
        XCTAssertEqual(processingRow.statusLabel, "Processing")
        XCTAssertEqual(processingRow.action, .none)

        let failedRow = JobRow(jobId: "3", name: "F", status: .failed)
        XCTAssertEqual(failedRow.statusLabel, "Failed")
        XCTAssertEqual(failedRow.action, .retry)

        let readyRow = JobRow(jobId: "4", name: "R", status: .succeeded, poseId: "p4")
        // Board copy for a finished job: "Done · added to Poses" (the earlier bare "Ready" word was
        // replaced by the owner's board decision).
        XCTAssertEqual(readyRow.statusLabel, "Done")
        XCTAssertEqual(readyRow.statusText, "Done · added to Poses")
        XCTAssertEqual(readyRow.action, .viewPose)
    }

    // MARK: - 3. Guest Guard
    func testGuestGuardOnRefreshIssuesNoNetworkRequests() async {
        await sessionBoundary.signOut()
        var requestMade = false
        MockURLProtocol.requestHandler = { _ in
            requestMade = true
            return (HTTPURLResponse(url: URL(string: "https://test.local")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        await service.refresh()

        XCTAssertFalse(requestMade)
        XCTAssertEqual(service.activeCount, 0)
        XCTAssertEqual(service.inProgress, [])
        XCTAssertEqual(service.finished, [])
    }

    func testGuestGuardOnWritePathsThrowsSignInRequired() async {
        await sessionBoundary.signOut()
        var requestMade = false
        MockURLProtocol.requestHandler = { _ in
            requestMade = true
            return (HTTPURLResponse(url: URL(string: "https://test.local")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        let draft = PoseDraft(name: "Test", tags: ["tag"])

        do {
            _ = try await service.submit(image: Data(), fileName: "test.jpg", draft: draft)
            XCTFail("Expected signInRequired error")
        } catch JobsError.signInRequired {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await service.retry(id: "job1")
            XCTFail("Expected signInRequired error")
        } catch JobsError.signInRequired {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await service.hide(id: "job1")
            XCTFail("Expected signInRequired error")
        } catch JobsError.signInRequired {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(requestMade)
    }

    func testExtractKillSwitchBlocksServiceRetryWithoutRequest() async {
        var requestMade = false
        MockURLProtocol.requestHandler = { request in
            requestMade = true
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        AppConfig.shared.applyExtractPoseEnabled(false)
        do {
            try await service.retry(id: "job1")
            XCTFail("Expected extraction-disabled error")
        } catch JobsError.extractPoseDisabled {
            // Expected: kill switch blocks retry before any request.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(requestMade)
    }

    // MARK: - 4. Refresh and State Splitting
    func testRefreshSplitsInProgressAndFinished() async {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/me/extract-jobs")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.extractionJobListJSON.utf8)
            )
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        await service.refresh()

        XCTAssertEqual(service.inProgress.count, 1)
        XCTAssertEqual(service.inProgress[0].name, "Active Hero Pose")
        XCTAssertEqual(service.activeCount, 1)

        XCTAssertEqual(service.finished.count, 2)
        XCTAssertEqual(service.finished[0].name, "Completed Warrior Pose")
        XCTAssertEqual(service.finished[0].status, .succeeded)
        XCTAssertEqual(service.finished[1].name, "Failed Tree Pose")
        XCTAssertEqual(service.finished[1].status, .failed)
    }

    func testJobMovingFromProcessingToSucceededMovesToFinished() async {
        var refreshCount = 0
        MockURLProtocol.requestHandler = { request in
            refreshCount += 1
            if refreshCount == 1 {
                let json = """
                {
                  "success": true,
                  "data": [
                    {
                      "jobId": "job1",
                      "status": "processing",
                      "poseDraft": { "name": "Pose 1", "tags": ["tag"], "description": null },
                      "poseId": null,
                      "thumbnailUrl": null,
                      "errorCode": null,
                      "errorMessage": null,
                      "createdAt": "2026-09-26T12:00:00Z",
                      "updatedAt": "2026-09-26T12:00:00Z"
                    }
                  ],
                  "meta": { "nextCursor": null }
                }
                """
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            } else {
                let json = """
                {
                  "success": true,
                  "data": [
                    {
                      "jobId": "job1",
                      "status": "succeeded",
                      "poseDraft": { "name": "Pose 1", "tags": ["tag"], "description": null },
                      "poseId": "pose1",
                      "thumbnailUrl": "https://example.com/pose1.png",
                      "errorCode": null,
                      "errorMessage": null,
                      "createdAt": "2026-09-26T12:00:00Z",
                      "updatedAt": "2026-09-26T12:00:05Z"
                    }
                  ],
                  "meta": { "nextCursor": null }
                }
                """
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        await service.refresh()
        XCTAssertEqual(service.inProgress.count, 1)
        XCTAssertEqual(service.finished.count, 0)
        XCTAssertEqual(service.activeCount, 1)

        await service.refresh()
        XCTAssertEqual(service.inProgress.count, 0)
        XCTAssertEqual(service.finished.count, 1)
        XCTAssertEqual(service.finished[0].status, .succeeded)
        XCTAssertEqual(service.activeCount, 0)
    }

    // MARK: - 5. WatchJob Polling & Termination
    func testWatchJobTerminatesOnSucceeded() async {
        MockURLProtocol.requestHandler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.succeededJobJSON.utf8)
            )
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        var events: [JobWatchEvent] = []
        for await event in service.watchJob(id: "550e8400-e29b-41d4-a716-446655440000") {
            events.append(event)
        }

        XCTAssertEqual(events.count, 1)
        if case .status(let data) = events[0] {
            XCTAssertEqual(data.status, "succeeded")
            XCTAssertEqual(data.poseId, "550e8400-e29b-41d4-a716-446655440001")
        } else {
            XCTFail("Expected .status event")
        }
    }

    func testWatchJobTerminatesWithGoneOn404() async {
        MockURLProtocol.requestHandler = { request in
            let errorJson = """
            {
              "error": {
                "code": "NOT_FOUND",
                "message": "Job not found"
              }
            }
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data(errorJson.utf8)
            )
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        var events: [JobWatchEvent] = []
        for await event in service.watchJob(id: "non-existent") {
            events.append(event)
        }

        XCTAssertEqual(events, [.gone])
    }

    func testWatchJobRecoversFromOfflineAndEmitsOnline() async {
        var attempt = 0
        MockURLProtocol.requestHandler = { request in
            attempt += 1
            if attempt == 1 {
                throw URLError(.notConnectedToInternet)
            } else {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(JobsFixtures.succeededJobJSON.utf8)
                )
            }
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        var events: [JobWatchEvent] = []
        for await event in service.watchJob(id: "job1") {
            events.append(event)
        }

        XCTAssertTrue(events.contains(.offline))
        XCTAssertTrue(events.contains(.online))
        if case .status(let data) = events.last {
            XCTAssertEqual(data.status, "succeeded")
        } else {
            XCTFail("Expected .status as final event")
        }
    }

    func testWatchJobTerminatesOnFailed() async {
        MockURLProtocol.requestHandler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.failedJobJSON.utf8)
            )
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        var events: [JobWatchEvent] = []
        for await event in service.watchJob(id: "550e8400-e29b-41d4-a716-446655440000") {
            events.append(event)
        }

        XCTAssertEqual(events.count, 1)
        if case .status(let data) = events[0] {
            XCTAssertEqual(data.status, "failed")
            XCTAssertEqual(data.error?.code, "PROVIDER_AUTH_REQUIRED")
        } else {
            XCTFail("Expected .status failed event")
        }
    }

    func testWatchJobEarlyStreamTerminationCancelsInternalPollingTask() async {
        let requestCount = Counter()
        MockURLProtocol.requestHandler = { request in
            requestCount.increment()
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.processingJobJSON.utf8)
            )
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        for await _ in service.watchJob(id: "job1") {
            break
        }

        let initialCount = requestCount.value
        XCTAssertGreaterThanOrEqual(initialCount, 1)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let laterCount = requestCount.value
        XCTAssertEqual(initialCount, laterCount, "Internal polling task must halt after consumer terminates stream early")
    }

    // MARK: - 6. Offline URLError & Cache Preservation
    func testOfflineNetworkErrorPreservesCachedJobsAndSetsOffline() async {
        MockURLProtocol.requestHandler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.extractionJobListJSON.utf8)
            )
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        await service.refresh()

        XCTAssertFalse(service.isOffline)
        XCTAssertEqual(service.inProgress.count, 1)
        XCTAssertEqual(service.finished.count, 2)
        XCTAssertEqual(service.activeCount, 1)

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        await service.refresh()

        XCTAssertTrue(service.isOffline)
        XCTAssertEqual(service.inProgress.count, 1)
        XCTAssertEqual(service.finished.count, 2)
        XCTAssertEqual(service.activeCount, 1)
    }

    func testSuccessfulRefreshAfterOfflineFailureClearsIsOffline() async {
        MockURLProtocol.requestHandler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.extractionJobListJSON.utf8)
            )
        }
        let service = JobsService(api: apiService, boundary: sessionBoundary)
        await service.refresh()
        XCTAssertFalse(service.isOffline)

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        await service.refresh()
        XCTAssertTrue(service.isOffline)

        MockURLProtocol.requestHandler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.extractionJobListJSON.utf8)
            )
        }
        await service.refresh()
        XCTAssertFalse(service.isOffline)
        XCTAssertEqual(service.loadState, .loaded)
    }

    func testPoseExtractionJobStatusEnvelopeSymmetry() throws {
        let jsonWithSuccess = """
        {
          "success": true,
          "data": {
            "jobId": "job123",
            "status": "queued"
          }
        }
        """
        let decoded = try JSONDecoder().decode(PoseExtractionJobStatus.self, from: Data(jsonWithSuccess.utf8))
        XCTAssertEqual(decoded.success, true)
        XCTAssertEqual(decoded.data.jobId, "job123")
    }

    // MARK: - 7. Lifecycle, Polling & Session Teardown
    func testPollingLifecycleAndIdempotency() async {
        let requestCount = Counter()
        MockURLProtocol.requestHandler = { request in
            requestCount.increment()
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.extractionJobListJSON.utf8)
            )
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        service.startPolling()
        service.startPolling()

        try? await Task.sleep(nanoseconds: 50_000_000)
        let countAfterStart = requestCount.value
        XCTAssertEqual(countAfterStart, 1)

        service.stopPolling()
        service.stopPolling()

        try? await Task.sleep(nanoseconds: 100_000_000)
        let countAfterStop = requestCount.value
        XCTAssertEqual(countAfterStop, countAfterStart, "stopPolling must halt further requests")
    }

    func testSessionTeardownStopsPollingAndClearsState() async {
        MockURLProtocol.requestHandler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.extractionJobListJSON.utf8)
            )
        }

        let service = JobsService(api: apiService, boundary: sessionBoundary)
        await service.refresh()
        XCTAssertEqual(service.inProgress.count, 1)

        service.startPolling()
        await sessionBoundary.signOut()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(service.inProgress, [])
        XCTAssertEqual(service.finished, [])
        XCTAssertEqual(service.activeCount, 0)
        XCTAssertFalse(service.isOffline)
    }

    // MARK: - 8. Multipart Body Verification
    func testStartPoseExtractionIncludesDraftFields() async throws {
        var capturedBodyData: Data?
        MockURLProtocol.requestHandler = { request in
            capturedBodyData = request.bodyData
            return (
                HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.startPoseExtractionJSON.utf8)
            )
        }

        let draft = PoseDraft(name: "My Custom Pose", tags: ["stand", "stretch"], description: "Hold for 30s")
        let response = try await apiService.startPoseExtraction(
            imageBytes: Data("fake_image_data".utf8),
            fileName: "photo.jpg",
            draft: draft
        )

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data.jobId, "550e8400-e29b-41d4-a716-446655440000")

        guard let bodyData = capturedBodyData, let bodyString = String(data: bodyData, encoding: .utf8) else {
            XCTFail("No multipart body captured")
            return
        }

        XCTAssertTrue(bodyString.contains("name=\"name\"\r\n\r\nMy Custom Pose"))
        XCTAssertTrue(bodyString.contains("name=\"tags\"\r\n\r\nstand"))
        XCTAssertTrue(bodyString.contains("name=\"tags\"\r\n\r\nstretch"))
        XCTAssertTrue(bodyString.contains("name=\"description\"\r\n\r\nHold for 30s"))
        XCTAssertTrue(bodyString.contains("name=\"image\"; filename=\"photo.jpg\""))
    }

    func testStartPoseExtractionExactMultipartPayloadAndNilDraft() async throws {
        var capturedBodyData: Data?
        var capturedContentType: String?
        MockURLProtocol.requestHandler = { request in
            capturedBodyData = request.bodyData
            capturedContentType = request.value(forHTTPHeaderField: "Content-Type")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!,
                Data(JobsFixtures.startPoseExtractionJSON.utf8)
            )
        }

        let rawImageBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        let response = try await apiService.startPoseExtraction(
            imageBytes: rawImageBytes,
            fileName: "capture.jpeg",
            draft: nil
        )

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data.jobId, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(capturedContentType, "multipart/form-data; boundary=AIPoseBoundary")

        guard let bodyData = capturedBodyData else {
            XCTFail("No body captured")
            return
        }

        XCTAssertNotNil(bodyData.range(of: rawImageBytes))

        guard let bodyString = String(data: bodyData, encoding: .isoLatin1) else {
            XCTFail("Cannot decode multipart body string")
            return
        }

        XCTAssertTrue(bodyString.hasPrefix("--AIPoseBoundary\r\n"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"image\"; filename=\"capture.jpeg\"\r\nContent-Type: image/jpeg\r\n\r\n"))
        XCTAssertTrue(bodyString.hasSuffix("\r\n--AIPoseBoundary--\r\n"))
        XCTAssertFalse(bodyString.contains("name=\"name\""))
    }
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
