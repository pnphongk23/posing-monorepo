import XCTest
@testable import iosApp

private final class ConsentSpyJobsService: ObservableObject, JobsServing, @unchecked Sendable {
    var inProgress: [JobRow] = []
    var finished: [JobRow] = []
    var activeCount: Int = 0
    var isOffline: Bool = false
    var loadState: JobsLoadState = .idle

    var submitResult: Result<String, Error> = .success("stub_job_consent")
    private(set) var submitCallCount = 0
    private(set) var submittedFileNames: [String] = []

    func refresh() async {}
    func startPolling() {}
    func stopPolling() {}

    func watchJob(id: String) -> AsyncStream<JobWatchEvent> {
        AsyncStream { $0.finish() }
    }

    func submit(image: Data, fileName: String, draft: PoseDraft) async throws -> String {
        submitCallCount += 1
        submittedFileNames.append(fileName)
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

/// The signed-in account, swappable mid-test the way a sign-out/sign-in does in the app.
private final class ScriptedAccount: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(_ value: String?) {
        self.value = value
    }

    var current: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

/// The consent step on Add pose (App Review 5.1.2(i)).
///
/// Every case goes through the real `AddPoseViewModel` and the real `AddPoseConsentStore` (on a scratch
/// `UserDefaults` suite); only the account identity and the Jobs call are stand-ins. The assertion that
/// matters is the call count, because "nothing is uploaded before Allow" is the whole requirement.
@MainActor
final class AddPoseConsentTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        AppConfig.shared.applyExtractPoseEnabled(true)
        suiteName = "ai-pose.consent.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        AppConfig.shared.applyExtractPoseEnabled(true)
        super.tearDown()
    }

    private func makeStore(
        account: ScriptedAccount,
        promptsEveryUpload: Bool = AddPoseConsentStore.promptEveryUpload
    ) -> AddPoseConsentStore {
        AddPoseConsentStore(
            defaults: defaults,
            promptsEveryUpload: promptsEveryUpload,
            accountIDProvider: { account.current }
        )
    }

    private func makeModel(
        store: AddPoseConsentStore,
        jobs: ConsentSpyJobsService
    ) -> AddPoseViewModel {
        let model = AddPoseViewModel(jobsService: jobs, consentStore: store)
        model.selectedImageData = Data("pose-photo-bytes".utf8)
        model.selectedFileName = "warrior.jpg"
        model.name = "Warrior One"
        model.tagsText = "standing, balance"
        model.descriptionText = "Keep the core tight"
        return model
    }

    // MARK: - (a) No acknowledgement, no request

    func testSubmitWithNoAckShowsAllowCancelBeforeAnyCall() async {
        let jobs = ConsentSpyJobsService()
        let model = makeModel(store: makeStore(account: ScriptedAccount("account-a")), jobs: jobs)

        let submitted = await model.submit()

        XCTAssertFalse(submitted, "submit must not report success while it is only asking for consent")
        XCTAssertTrue(model.isConsentPromptVisible, "the consent sheet must be the thing the user sees")
        XCTAssertEqual(jobs.submitCallCount, 0, "no upload may start before the user allows it")
        XCTAssertNil(model.submittedJobId, "no job may exist before consent")
        XCTAssertNil(model.submitError, "asking for consent is not an error state")

        // The two controls Maestro has to reach, and the copy it reads.
        XCTAssertEqual(AddPoseConsentSheet.Identifiers.message, "addPose.consent.message")
        XCTAssertEqual(AddPoseConsentSheet.Identifiers.allowButton, "addPose.consent.allowButton")
        XCTAssertEqual(AddPoseConsentSheet.Identifiers.cancelButton, "addPose.consent.cancelButton")
        XCTAssertEqual(AddPoseConsentCopy.allow, "Allow")
        XCTAssertEqual(AddPoseConsentCopy.cancel, "Cancel")
    }

    // MARK: - (b) Cancel sends nothing and keeps the form

    func testCancelSendsNoRequestAndKeepsFormFilled() async {
        let jobs = ConsentSpyJobsService()
        let account = ScriptedAccount("account-a")
        let store = makeStore(account: account)
        let model = makeModel(store: store, jobs: jobs)

        _ = await model.submit()
        XCTAssertTrue(model.isConsentPromptVisible)

        model.cancelConsent()

        XCTAssertFalse(model.isConsentPromptVisible, "Cancel closes the sheet")
        XCTAssertEqual(jobs.submitCallCount, 0, "Cancel must not reach the service")
        XCTAssertEqual(model.selectedImageData, Data("pose-photo-bytes".utf8), "the photo stays selected")
        XCTAssertEqual(model.name, "Warrior One")
        XCTAssertEqual(model.tagsText, "standing, balance")
        XCTAssertEqual(model.descriptionText, "Keep the core tight")
        XCTAssertNil(model.submittedJobId, "Cancel creates no job")
        XCTAssertFalse(store.hasAcknowledged(accountID: "account-a"), "Cancel is not an acknowledgement")

        // Asking again is the only thing a second submit can do on an unacknowledged account.
        _ = await model.submit()
        XCTAssertEqual(jobs.submitCallCount, 0)
        XCTAssertTrue(model.isConsentPromptVisible)
    }

    // MARK: - (c) Allow sends exactly one upload

    func testAllowSendsExactlyOneRequest() async {
        let jobs = ConsentSpyJobsService()
        let model = makeModel(store: makeStore(account: ScriptedAccount("account-a")), jobs: jobs)

        _ = await model.submit()
        XCTAssertEqual(jobs.submitCallCount, 0)

        let allowed = await model.allowConsent()

        XCTAssertTrue(allowed)
        XCTAssertEqual(jobs.submitCallCount, 1, "Allow must send the held photo exactly once")
        XCTAssertEqual(jobs.submittedFileNames, ["warrior.jpg"], "the held draft is what gets sent")
        XCTAssertEqual(model.submittedJobId, "stub_job_consent")
        XCTAssertFalse(model.isConsentPromptVisible)

        // A second Allow (double tap, or a sheet that dismissed twice) has nothing left to send.
        _ = await model.allowConsent()
        XCTAssertEqual(jobs.submitCallCount, 1, "an empty Allow must not re-send the photo")
    }

    // MARK: - (d) Once per account, including across launches

    func testAcknowledgedAccountIsNotPromptedAgain() async {
        let jobs = ConsentSpyJobsService()
        let account = ScriptedAccount("account-a")
        let model = makeModel(store: makeStore(account: account), jobs: jobs)

        _ = await model.submit()
        _ = await model.allowConsent()
        XCTAssertEqual(jobs.submitCallCount, 1)

        // Same account, second submit in the same launch: no sheet, one upload.
        let second = await model.submit()
        XCTAssertTrue(second)
        XCTAssertFalse(model.isConsentPromptVisible, "an acknowledged account is not asked again")
        XCTAssertEqual(jobs.submitCallCount, 2)

        // Same account, next launch: the record is read back from the store, still no sheet.
        let relaunched = makeModel(store: makeStore(account: account), jobs: jobs)
        let third = await relaunched.submit()
        XCTAssertTrue(third)
        XCTAssertFalse(relaunched.isConsentPromptVisible)
        XCTAssertEqual(jobs.submitCallCount, 3)
    }

    // MARK: - (e) A different account is asked again

    func testDifferentAccountIsPromptedAgain() async {
        let jobs = ConsentSpyJobsService()
        let account = ScriptedAccount("account-a")
        let model = makeModel(store: makeStore(account: account), jobs: jobs)

        _ = await model.submit()
        _ = await model.allowConsent()
        XCTAssertEqual(jobs.submitCallCount, 1)

        // Sign out of A, sign in as B: B has never agreed to anything.
        account.current = "account-b"
        let switched = await model.submit()
        XCTAssertFalse(switched)
        XCTAssertTrue(model.isConsentPromptVisible, "a second account gets its own disclosure")
        XCTAssertEqual(jobs.submitCallCount, 1, "the photo is held, not sent, for the new account")

        _ = await model.allowConsent()
        XCTAssertEqual(jobs.submitCallCount, 2)

        // Back on A the earlier record still holds.
        account.current = "account-a"
        _ = await model.submit()
        XCTAssertFalse(model.isConsentPromptVisible)
        XCTAssertEqual(jobs.submitCallCount, 3)
    }

    // MARK: - (f) The frozen wording

    func testCopyConstantMatchesApprovedDisclosure() {
        XCTAssertEqual(
            AddPoseConsentCopy.message,
            "To extract the pose, your photo is sent to a third-party AI service. The pose created from it is saved privately to your account until you delete it."
        )
        // The copy describes the flow, never the vendor behind it.
        let forbidden = ["Higgsfield", "higgsfield", "OpenAI", "Gemini", "Replicate", "Fal", "vendor"]
        for name in forbidden {
            XCTAssertFalse(AddPoseConsentCopy.message.contains(name), "the disclosure must not name \(name)")
        }
    }

    // MARK: - The one-line policy switch

    func testPromptEveryUploadAsksAgainAfterAnAcknowledgement() async {
        let jobs = ConsentSpyJobsService()
        let model = makeModel(store: makeStore(account: ScriptedAccount("account-a"), promptsEveryUpload: true), jobs: jobs)

        _ = await model.submit()
        _ = await model.allowConsent()
        XCTAssertEqual(jobs.submitCallCount, 1)

        _ = await model.submit()
        XCTAssertTrue(model.isConsentPromptVisible, "the every-upload policy asks even after Allow")
        XCTAssertEqual(jobs.submitCallCount, 1)
    }

    func testSignedOutSubmitShowsSignInInsteadOfConsent() async {
        let jobs = ConsentSpyJobsService()
        jobs.submitResult = .failure(JobsError.signInRequired)
        let model = makeModel(store: makeStore(account: ScriptedAccount(nil)), jobs: jobs)

        let submitted = await model.submit()

        // No account id means no session: the upload is refused anyway, so the disclosure waits for a
        // real account instead of being shown against nobody.
        XCTAssertFalse(submitted)
        XCTAssertFalse(model.isConsentPromptVisible)
        XCTAssertEqual(jobs.submitCallCount, 1)
        XCTAssertEqual(model.submitError, "Sign in to add a pose.")
    }

    // MARK: - Identity source

    func testAccountIDIsReadFromTheStoredSessionToken() throws {
        let payload = try JSONSerialization.data(withJSONObject: ["sub": "account-a", "aud": "authenticated"])
        let token = "header.\(base64URL(payload)).signature"

        XCTAssertEqual(AddPoseConsentStore.accountID(fromAccessToken: token), "account-a")
        XCTAssertNil(AddPoseConsentStore.accountID(fromAccessToken: nil))
        XCTAssertNil(AddPoseConsentStore.accountID(fromAccessToken: "not-a-jwt"))
        XCTAssertNil(AddPoseConsentStore.accountID(fromAccessToken: "header.e30.signature"), "no subject, no account")
    }

    /// Records one acknowledgement per account id, so the ledger is proved to be keyed, not install-wide.
    func testStoreRecordsOneBooleanPerAccount() {
        let store = makeStore(account: ScriptedAccount("account-a"))

        XCTAssertFalse(store.hasAcknowledged(accountID: "account-a"))
        store.recordAcknowledgement(accountID: "account-a")

        XCTAssertTrue(store.hasAcknowledged(accountID: "account-a"))
        XCTAssertFalse(store.hasAcknowledged(accountID: "account-b"))
        XCTAssertEqual(
            defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(AddPoseConsentStore.keyPrefix) }.count,
            1,
            "one key per account, nothing more"
        )
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
