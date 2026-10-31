import SwiftUI
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

    // MARK: - Restyled form (direction B, boards 08-board04..08)

    func testFieldErrorsStayQuietUntilTheUserTriesToAddThePose() {
        let model = AddPoseViewModel(jobsService: StubJobsService())

        // An untouched form accuses nobody, even though it is not valid yet.
        XCTAssertFalse(model.isFormValid)
        XCTAssertNil(model.nameFieldError)
        XCTAssertNil(model.tagsFieldError)

        model.showsFieldErrors = true
        XCTAssertEqual(model.nameFieldError, AddPoseFormCopy.nameRequired)
        XCTAssertEqual(model.tagsFieldError, AddPoseFormCopy.tagsRequired)

        model.name = "Window light"
        model.tagsText = "standing"
        XCTAssertNil(model.nameFieldError)
        XCTAssertNil(model.tagsFieldError)
    }

    func testDescriptionOverflowIsReportedAsCharactersOverTheLimit() {
        let model = AddPoseViewModel(jobsService: StubJobsService())
        model.descriptionText = String(repeating: "a", count: AddPoseViewModel.descriptionLimit)
        XCTAssertNil(model.descriptionFieldError)
        XCTAssertEqual(model.descriptionOverflow, 0)

        model.descriptionText += "abc"
        XCTAssertEqual(model.descriptionOverflow, 3)
        XCTAssertEqual(model.descriptionFieldError, "3 characters too long.")
        XCTAssertFalse(model.isFormValid)

        model.descriptionText = String(repeating: "a", count: AddPoseViewModel.descriptionLimit + 1)
        XCTAssertEqual(model.descriptionFieldError, "1 character too long.")
    }

    func testTagsAreChipsOverTheSameCommaSeparatedText() {
        let model = AddPoseViewModel(jobsService: StubJobsService())
        model.tagsText = "standing, indoor"
        XCTAssertEqual(model.parsedTags, ["standing", "indoor"])

        // Typing is committed a comma at a time, so the chip appears while the next tag is typed.
        model.tagDraft = "outdoor, "
        model.commitCompletedTags()
        XCTAssertEqual(model.parsedTags, ["standing", "indoor", "outdoor"])
        XCTAssertEqual(model.tagDraft, "", "nothing is left in the field once the comma committed it")

        // Return commits the rest of the field.
        model.tagDraft = "studio"
        model.commitTagDraft()
        XCTAssertEqual(model.parsedTags, ["standing", "indoor", "outdoor", "studio"])
        XCTAssertEqual(model.tagDraft, "")

        // Duplicates and blanks never become chips.
        model.commitTagDraft()
        model.tagDraft = "  STANDING ,  , studio"
        model.commitTagDraft()
        XCTAssertEqual(model.parsedTags, ["standing", "indoor", "outdoor", "studio"])

        // Tapping a chip removes exactly that tag.
        model.removeTag("indoor")
        XCTAssertEqual(model.parsedTags, ["standing", "outdoor", "studio"])
    }

    func testTheEleventhTagIsDroppedInsteadOfFailingTheFormLater() {
        let model = AddPoseViewModel(jobsService: StubJobsService())
        for index in 0..<(AddPoseViewModel.maxTags + 2) {
            model.tagDraft = "tag\(index)"
            model.commitTagDraft()
        }
        XCTAssertEqual(model.parsedTags.count, AddPoseViewModel.maxTags)
        XCTAssertEqual(model.parsedTags.last, "tag\(AddPoseViewModel.maxTags - 1)")
    }

    func testPhotoFailuresLandOnThePhotoInsteadOfTheSnackbar() async {
        let stub = StubJobsService()
        let model = AddPoseViewModel(jobsService: stub)
        model.selectedImageData = Data("test_photo".utf8)
        model.selectedFileName = "photo.jpg"
        model.name = "Window light"
        model.tagsText = "standing"

        stub.submitResult = .failure(JobsError.invalidImage)
        _ = await model.submit()
        XCTAssertEqual(model.photoError, .unreadable)
        XCTAssertNil(model.snackbarMessage, "a photo that cannot be read is not a transient toast")

        model.clearPhotoError()
        XCTAssertNil(model.photoError)

        stub.submitResult = .failure(JobsError.imageTooLarge)
        _ = await model.submit()
        XCTAssertEqual(model.photoError, .tooLarge)
        XCTAssertTrue(
            AddPosePhotoError.tooLarge.message.contains("10 MB"),
            "the copy names the documented 10 MB upload limit, not the board's 20 MB"
        )

        // A transient failure is a snackbar, with the model's original copy kept intact.
        stub.submitResult = .failure(JobsError.serverError("boom"))
        _ = await model.submit()
        XCTAssertNil(model.photoError, "a new attempt starts clean")
        XCTAssertEqual(model.snackbarMessage, "Couldn't send. Try again.")
    }

    func testOfflineSubmitDisablesTheFooterAndExplainsWhy() async {
        let stub = StubJobsService()
        let model = AddPoseViewModel(jobsService: stub)
        model.name = "Window light"
        model.tagsText = "standing"

        // No photo yet: the footer says what to do instead of silently disabling.
        XCTAssertEqual(model.submitHint, AddPoseFormCopy.photoRequiredHint)
        XCTAssertTrue(model.isSubmitEnabled, "an incomplete form must still be able to explain itself")

        model.selectedImageData = Data("test_photo".utf8)
        model.selectedFileName = "photo.jpg"
        XCTAssertNil(model.submitHint)

        stub.submitResult = .failure(JobsError.offline)
        _ = await model.submit()
        XCTAssertTrue(model.isOffline)
        XCTAssertFalse(model.isSubmitEnabled, "board 08-board06 disables the CTA while offline")
        XCTAssertEqual(model.submitHint, AddPoseFormCopy.offlineSubmitHint)
    }

    func testProcessingCopyComesFromTheStatusTheServerReported() {
        XCTAssertEqual(AddPoseStage(status: "QUEUED"), .queued)
        XCTAssertEqual(AddPoseStage(status: "processing"), .processing)
        XCTAssertEqual(AddPoseStage(status: "succeeded"), .ready)
        XCTAssertEqual(AddPoseStage(status: "failed"), .failed)
        XCTAssertEqual(AddPoseStage(status: "something-new"), .processing, "an unknown state never claims it is ready")

        XCTAssertEqual(AddPoseStage.queued.label, "Queued")
        XCTAssertEqual(AddPoseStage.processing.label, "Processing")
        XCTAssertEqual(AddPoseStage.ready.label, "Pose ready")
        XCTAssertEqual(AddPoseStage.failed.label, "Failed")

        for stage in AddPoseStage.allCases {
            XCTAssertFalse(stage.label.contains("%"), "no percentage is ever invented (B3c)")
            XCTAssertFalse(stage.glyph.isEmpty, "the stage pairs a glyph with its word")
        }
        XCTAssertTrue(AddPoseStage.queued.isInFlight)
        XCTAssertTrue(AddPoseStage.processing.isInFlight)
        XCTAssertFalse(AddPoseStage.ready.isInFlight)
        XCTAssertFalse(AddPoseStage.failed.isInFlight)
    }

    func testTheFormCarriesNoLegacyOrCountCopy() {
        // F3 bans result counts, and the legacy screen's CTA and labels are gone with the restyle.
        let copy = [
            AddPoseFormCopy.screenTitle, AddPoseFormCopy.nameLabel, AddPoseFormCopy.tagsLabel,
            AddPoseFormCopy.descriptionLabel, AddPoseFormCopy.addPose, AddPoseFormCopy.changePhoto,
            AddPoseFormCopy.choosePhoto, AddPoseFormCopy.done, AddPoseFormCopy.viewJobs,
            AddPoseFormCopy.leaveHint, AddPoseFormCopy.offlineBanner
        ]
        XCTAssertFalse(copy.contains("Extract Pose"))
        for value in copy {
            XCTAssertFalse(value.contains("1–10"), "the tag limit is enforced, not printed")
            XCTAssertFalse(value.lowercased().contains("pose name *"), "labels are no longer marked with an asterisk")
        }
        XCTAssertEqual(AddPoseFormCopy.screenTitle, "Add pose", "the board's sentence-case inline title")
        XCTAssertEqual(AddPoseFormCopy.processingTitle, "Processing")
    }

    func testConsentIdentifiersAreUntouched() {
        // The App Review 5.1.2(i) surface is not part of the restyle: same ids, same wording.
        XCTAssertEqual(AddPoseConsentSheet.Identifiers.message, "addPose.consent.message")
        XCTAssertEqual(AddPoseConsentSheet.Identifiers.allowButton, "addPose.consent.allowButton")
        XCTAssertEqual(AddPoseConsentSheet.Identifiers.cancelButton, "addPose.consent.cancelButton")
        XCTAssertTrue(AddPoseConsentCopy.message.contains("third-party AI service"))
    }

    @MainActor
    func testTheFormPaintsAnInlineHeaderAndAPinnedAccentCallToAction() {
        let model = AddPoseViewModel(jobsService: StubJobsService())
        model.selectedImageData = Data("test_photo".utf8)
        model.selectedFileName = "photo.jpg"
        model.name = "Window light"
        model.tagsText = "standing, indoor"

        let size = CGSize(width: 393, height: 720)
        let probe = APViewProbe(
            AddPoseScreen(viewModel: model, posesModel: PosesViewModel(service: AddPoseEmptyPoseService())),
            size: size
        )
        defer { probe.tearDown() }
        let painted = probe.capture()

        // F2: the back control paints the neutral `controlFill` square in the header row.
        let controlFillRows = painted.rows(paintedWith: 0xECE5D8)
        XCTAssertFalse(
            controlFillRows.filter { $0 < 80 }.isEmpty,
            "the inline header must paint its back control"
        )

        // The CTA is pinned: the accent fill lives in the bottom band, not in the scrolling form.
        let accentRows = painted.rows(paintedWith: 0xE89CAE)
        XCTAssertFalse(accentRows.isEmpty, "the form must paint its accent CTA")
        XCTAssertGreaterThan(
            accentRows.first ?? 0, painted.height - 160,
            "the CTA is pinned at the bottom (starts at row \(accentRows.first ?? 0) of \(painted.height))"
        )
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

/// The catalogue is irrelevant to this screen; the probe only needs a model that does not reach the
/// network while the form is rendered.
private struct AddPoseEmptyPoseService: PoseServing {
    func poses(query: String?) async throws -> [NativePose] { [] }
    func pose(id: String) async throws -> NativePose { throw PoseAdapterError.poseNotFound(id) }
}
