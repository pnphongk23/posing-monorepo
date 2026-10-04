import XCTest
@testable import iosApp

private final class StubJobsService: ObservableObject, JobsServing, @unchecked Sendable {
    var inProgress: [JobRow] = []
    var finished: [JobRow] = []
    var activeCount: Int = 0
    var isOffline: Bool = false
    var loadState: JobsLoadState = .idle

    var submitResult: Result<String, Error> = .success("stub_job_123")
    var submitCallCount = 0

    func refresh() async {}
    func startPolling() {}
    func stopPolling() {}
    func watchJob(id: String) -> AsyncStream<JobWatchEvent> {
        AsyncStream { $0.finish() }
    }

    func submit(image: Data, fileName: String, draft: PoseDraft) async throws -> String {
        submitCallCount += 1
        switch submitResult {
        case .success(let jobId):
            return jobId
        case .failure(let error):
            throw error
        }
    }

    func retry(id: String) async throws {}
    func hide(id: String) async throws {}
    func getGuide(id: String) async throws -> GuidePose {
        throw JobsError.notFound
    }
}

@MainActor
final class AddPoseFormTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppConfig.shared.applyExtractPoseEnabled(true)
    }

    override func tearDown() {
        AppConfig.shared.applyExtractPoseEnabled(true)
        super.tearDown()
    }

    func testFormValidationRequiresImageNameAndTags() {
        let stub = StubJobsService()
        let model = AddPoseViewModel(jobsService: stub)

        XCTAssertFalse(model.isFormValid)

        // Add image only
        model.selectedImageData = Data("image".utf8)
        model.selectedFileName = "pose.jpg"
        XCTAssertFalse(model.isFormValid)

        // Add whitespace-only name
        model.name = "   "
        XCTAssertFalse(model.isFormValid)

        // Add valid name
        model.name = "Warrior One"
        XCTAssertFalse(model.isFormValid) // still needs tags

        // Add tags
        model.tagsText = "standing, yoga, warrior"
        XCTAssertTrue(model.isFormValid)
        XCTAssertEqual(model.parsedTags, ["standing", "yoga", "warrior"])

        // Test tags exceeding 10
        model.tagsText = "1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11"
        XCTAssertFalse(model.isFormValid)

        // Test description exceeding 500 chars
        model.tagsText = "yoga"
        model.descriptionText = String(repeating: "a", count: 501)
        XCTAssertFalse(model.isFormValid)

        // Description <= 500 chars
        model.descriptionText = String(repeating: "a", count: 500)
        XCTAssertTrue(model.isFormValid)
    }

    func testSubmitFailurePreservesFormDraftAndSetsError() async {
        let stub = StubJobsService()
        let model = AddPoseViewModel(jobsService: stub)

        model.selectedImageData = Data("test_photo".utf8)
        model.selectedFileName = "photo.jpg"
        model.name = "Test Pose"
        model.tagsText = "standing, balance"
        model.descriptionText = "Keep core tight"

        // 1. Offline failure
        stub.submitResult = .failure(JobsError.offline)
        let offlineResult = await model.submit()
        XCTAssertFalse(offlineResult)
        XCTAssertEqual(model.name, "Test Pose")
        XCTAssertEqual(model.tagsText, "standing, balance")
        XCTAssertEqual(model.descriptionText, "Keep core tight")
        XCTAssertNotNil(model.selectedImageData)
        XCTAssertTrue(model.isOffline)
        XCTAssertEqual(model.submitError, "You're offline. Check your connection.")
        XCTAssertEqual(stub.submitCallCount, 1)

        // 2. Invalid Image (400 / 413)
        stub.submitResult = .failure(JobsError.invalidImage)
        let invalidImageResult = await model.submit()
        XCTAssertFalse(invalidImageResult)
        XCTAssertEqual(model.name, "Test Pose")
        XCTAssertEqual(model.submitError, "Only JPEG and PNG images are supported. Choose another photo.")

        // 3. Invalid Metadata (400)
        stub.submitResult = .failure(JobsError.invalidMetadata)
        let invalidMetaResult = await model.submit()
        XCTAssertFalse(invalidMetaResult)
        XCTAssertEqual(model.name, "Test Pose")
        XCTAssertEqual(model.submitError, "Please check the pose name and tags.")

        // 4. Server error (5xx)
        stub.submitResult = .failure(JobsError.serverError("Internal Server Error"))
        let serverErrorResult = await model.submit()
        XCTAssertFalse(serverErrorResult)
        XCTAssertEqual(model.name, "Test Pose")
        XCTAssertEqual(model.submitError, "Couldn't send. Try again.")

        // 5. Sign In Required
        stub.submitResult = .failure(JobsError.signInRequired)
        let signInResult = await model.submit()
        XCTAssertFalse(signInResult)
        XCTAssertEqual(model.name, "Test Pose")
        XCTAssertEqual(model.submitError, "Sign in to add a pose.")
    }

    func testExtractKillSwitchBlocksFormAndSubmitThenAllowsWhenEnabled() async {
        let stub = StubJobsService()
        let model = AddPoseViewModel(jobsService: stub)
        model.selectedImageData = Data("test_photo".utf8)
        model.selectedFileName = "photo.jpg"
        model.name = "Test Pose"
        model.tagsText = "standing, balance"

        AppConfig.shared.applyExtractPoseEnabled(false)
        XCTAssertFalse(model.isFormValid)
        let blockedResult = await model.submit()
        XCTAssertFalse(blockedResult)
        XCTAssertEqual(model.submitError, JobsError.extractPoseDisabled.localizedDescription)
        XCTAssertEqual(stub.submitCallCount, 0)

        AppConfig.shared.applyExtractPoseEnabled(true)
        XCTAssertTrue(model.isFormValid)
        let allowedResult = await model.submit()
        XCTAssertTrue(allowedResult)
        XCTAssertNil(model.submitError)
        XCTAssertEqual(stub.submitCallCount, 1)
    }
}
