import SwiftUI

// MARK: - Copy

/// Every string the Add pose flow draws, in one place so the boards' wording is testable and the
/// frozen consent copy keeps living in `AddPoseConsentCopy` (App Review 5.1.2(i)).
enum AddPoseFormCopy {
    static let screenTitle = "Add pose"
    static let processingTitle = "Processing"

    static let nameLabel = "Name"
    static let namePlaceholder = "Pose name"
    static let tagsLabel = "Tags"
    static let tagPlaceholder = "Add tag"
    static let descriptionLabel = "Description"
    static let descriptionPlaceholder = "Describe the pose"

    static let changePhoto = "Change photo"
    static let choosePhoto = "Choose photo"
    static let chooseAnotherPhoto = "Choose another photo"

    static let addPose = "Add to Poses"
    static let addingPose = "Adding…"
    static let viewPose = "View pose"
    static let viewJobs = "View in Jobs"
    static let done = "Done"
    static let retry = "Try again"

    static let offlineBanner = "You're offline. Your draft is kept on this iPhone."
    static let photoRequiredHint = "Choose a photo to continue."
    static let leaveHint = "You can leave — it continues in Jobs."

    static let nameRequired = "Add a name for your pose."
    static let tagsRequired = "Pick at least one tag."
    static func descriptionTooLong(_ characters: Int) -> String {
        "\(characters) character\(characters == 1 ? "" : "s") too long."
    }

    static let photoErrorTitle = "Can't use this photo"
    static let extractionFailedTitle = "Couldn't add your pose"
    static let jobGoneTitle = "Job removed"
    static let jobGoneMessage = "This job was removed."
    static let extractOffTitle = "Pose extraction is off"
    static let extractOffMessage = "Pose extraction is currently unavailable."
    static let processingOffline = "You're offline. Status resumes when you're back online."
}

/// Failures the server reports about the photo itself. They are drawn on the photo block (board
/// `08-board08`) rather than in the transient toast, because the fix is another photo, not a retry.
enum AddPosePhotoError: String, Equatable {
    case unreadable
    case tooLarge

    var message: String {
        switch self {
        case .unreadable:
            return "This photo can't be used. Choose another photo."
        case .tooLarge:
            return "This photo is too large. Choose one under 20 MB."
        }
    }
}

/// The stage the processing card names. Derived from the status the server reports — never from
/// elapsed time — so the card cannot claim progress the backend did not report, and no percentage is
/// ever invented (B3c).
enum AddPoseStage: String, CaseIterable, Equatable {
    case queued
    case processing
    case ready
    case failed

    /// An unrecognised status is reported as in flight: the backend emits exactly these four states,
    /// and the card must never claim "ready" for a state it does not recognise.
    init(status: String) {
        switch status.lowercased() {
        case "queued": self = .queued
        case "succeeded": self = .ready
        case "failed": self = .failed
        default: self = .processing
        }
    }

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .processing: return "Processing · just now"
        case .ready: return "Pose ready"
        case .failed: return "Failed"
        }
    }

    var glyph: String {
        switch self {
        case .queued: return "clock"
        case .processing: return "sparkles"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var isInFlight: Bool { self == .queued || self == .processing }
}

@MainActor
final class AddPoseViewModel: ObservableObject {
    /// Tags and description limits from `isFormValid`. The screen draws both, so they are named here
    /// instead of restated in the view.
    static let maxTags = 10
    static let descriptionLimit = 150

    @Published var selectedImage: UIImage?
    @Published var selectedImageData: Data?
    @Published var selectedFileName: String?
    @Published var name = ""
    @Published var tagsText = ""
    @Published var descriptionText = ""

    @Published private(set) var isSubmitting = false
    @Published private(set) var submitError: String?
    @Published private(set) var isOffline = false

    // Processing surface state
    @Published var submittedJobId: String?
    @Published var currentJobStatus: String = "queued"
    @Published var currentPoseId: String?
    @Published var processingError: String?
    @Published var isProcessingOffline = false
    @Published var isJobGone = false

    /// Drives the consent sheet. The form stays mounted behind it, so Cancel leaves it filled.
    @Published var isConsentPromptVisible = false

    /// Board `08-board07`: the per-field errors appear once the user has tried to add the pose, so the
    /// form never accuses someone who has not started yet.
    @Published var showsFieldErrors = false

    /// The inline tag input. The tags themselves stay in `tagsText` (comma separated, the property the
    /// tests and `parsedTags` already read), so the chips and the field can never disagree.
    @Published var tagDraft = ""

    /// A photo-specific failure, drawn on the photo block instead of the transient snackbar.
    @Published private(set) var photoError: AddPosePhotoError?

    private let jobsService: any JobsServing
    private let consentStore: any AddPoseConsentStoring
    private var watchTask: Task<Void, Never>?
    /// The upload that was validated but held back for consent; it is never reconstructed from the form,
    /// so a later edit cannot change the photo the user is agreeing to send.
    private var pendingConsentUpload: PendingUpload?

    private struct PendingUpload {
        let imageData: Data
        let fileName: String
        let draft: PoseDraft
    }

    init(
        jobsService: any JobsServing = ServiceLocator.jobsService,
        consentStore: any AddPoseConsentStoring = AddPoseConsentStore.shared
    ) {
        self.jobsService = jobsService
        self.consentStore = consentStore
    }

    deinit {
        watchTask?.cancel()
    }

    // MARK: - Form state

    var parsedTags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isFormValid: Bool {
        guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else { return false }
        guard selectedImageData != nil else { return false }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let tags = parsedTags
        guard !tags.isEmpty && tags.count <= Self.maxTags else { return false }
        guard descriptionText.count <= Self.descriptionLimit else { return false }
        return true
    }

    var poseName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AddPoseFormCopy.namePlaceholder : trimmed
    }

    /// Keep the CTA retryable after a connection failure; the offline state itself is explained by
    /// the single banner, without an extra caption or a dead disabled button.
    var isSubmitEnabled: Bool { !isSubmitting }

    /// The reason under the footer CTA when it cannot do anything useful (boards `08-board06`,
    /// `08-board08`).
    var submitHint: String? {
        if isOffline { return nil }
        guard selectedImageData == nil else { return nil }
        return AddPoseFormCopy.photoRequiredHint
    }

    var nameFieldError: String? {
        guard showsFieldErrors, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return AddPoseFormCopy.nameRequired
    }

    var tagsFieldError: String? {
        guard showsFieldErrors, parsedTags.isEmpty else { return nil }
        return AddPoseFormCopy.tagsRequired
    }

    var descriptionOverflow: Int { max(0, descriptionText.count - Self.descriptionLimit) }

    /// Live, not gated on a submit attempt: the counter already turns red, and an over-long
    /// description blocks the CTA (board `08-board07`).
    var descriptionFieldError: String? {
        guard descriptionOverflow > 0 else { return nil }
        return AddPoseFormCopy.descriptionTooLong(descriptionOverflow)
    }

    /// Copy for the transient bottom snackbar (F5). Photo failures are not toasts.
    var snackbarMessage: String? {
        photoError == nil ? submitError : nil
    }

    // MARK: - Tags

    /// Adds the tag the inline field holds and clears the field. Duplicates and the eleventh tag are
    /// dropped instead of failing the form later.
    func commitTagDraft() {
        let parts = tagDraft.components(separatedBy: ",")
        var tags = parsedTags
        for part in parts {
            Self.append(part, to: &tags)
        }
        tagsText = tags.joined(separator: ", ")
        tagDraft = ""
    }

    /// Commits what the user has already finished typing (everything before the last comma) and keeps
    /// the word still in progress, so "standing, indoor" becomes two chips while it is typed.
    func commitCompletedTags() {
        guard tagDraft.contains(",") else { return }
        let parts = tagDraft.components(separatedBy: ",")
        var tags = parsedTags
        for part in parts.dropLast() {
            Self.append(part, to: &tags)
        }
        tagsText = tags.joined(separator: ", ")
        tagDraft = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func removeTag(_ tag: String) {
        var tags = parsedTags
        tags.removeAll { $0 == tag }
        tagsText = tags.joined(separator: ", ")
    }

    private static func append(_ raw: String, to tags: inout [String]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard tags.count < maxTags else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        tags.append(trimmed)
    }

    // MARK: - Submitting

    func submit() async -> Bool {
        guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else {
            submitError = "Pose extraction is currently disabled."
            return false
        }
        guard isFormValid, let imageData = selectedImageData, let fileName = selectedFileName else {
            return false
        }

        let draft = PoseDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: parsedTags,
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        // App Review 5.1.2(i): the photo leaves the device only after the user has been told where it
        // goes and has allowed it. Nothing is sent while the sheet is up — not even a prefetch.
        if await needsConsent() {
            pendingConsentUpload = PendingUpload(imageData: imageData, fileName: fileName, draft: draft)
            submitError = nil
            isOffline = false
            isConsentPromptVisible = true
            return false
        }

        return await performUpload(imageData: imageData, fileName: fileName, draft: draft)
    }

    /// The user allowed the upload: remember the answer for this account, then send the held photo once.
    @discardableResult
    func allowConsent() async -> Bool {
        guard let pending = pendingConsentUpload else {
            isConsentPromptVisible = false
            return false
        }
        pendingConsentUpload = nil
        isConsentPromptVisible = false
        if let accountID = await consentStore.accountID() {
            consentStore.recordAcknowledgement(accountID: accountID)
        }
        return await performUpload(imageData: pending.imageData, fileName: pending.fileName, draft: pending.draft)
    }

    /// The user cancelled: nothing is sent, nothing is remembered, and the filled form is untouched.
    func cancelConsent() {
        pendingConsentUpload = nil
        isConsentPromptVisible = false
    }

    private func needsConsent() async -> Bool {
        // `nil` means no usable session: `JobsService.submit` refuses without stored credentials and the
        // backend rejects any token without a `sub` claim, so there is no upload to disclose yet. A real
        // signed-in session always resolves, and then the sheet is authoritative.
        guard let accountID = await consentStore.accountID() else { return false }
        guard !consentStore.promptsEveryUpload else { return true }
        return !consentStore.hasAcknowledged(accountID: accountID)
    }

    /// Clears the snackbar and the photo banner: the user has seen them.
    func dismissSubmitError() {
        submitError = nil
        photoError = nil
    }

    /// A freshly chosen photo clears the previous photo failure, so an old banner cannot describe the
    /// new photo.
    func clearPhotoError() {
        photoError = nil
    }

    private func performUpload(imageData: Data, fileName: String, draft: PoseDraft) async -> Bool {
        isSubmitting = true
        submitError = nil
        photoError = nil
        isOffline = false
        defer { isSubmitting = false }

        do {
            let jobId = try await jobsService.submit(image: imageData, fileName: fileName, draft: draft)
            submittedJobId = jobId
            startWatching(jobId: jobId)
            return true
        } catch JobsError.signInRequired {
            submitError = "Sign in to add a pose."
            return false
        } catch JobsError.offline {
            isOffline = true
            submitError = "You're offline. Your draft is kept on this iPhone."
            return false
        } catch JobsError.invalidImage {
            photoError = .unreadable
            submitError = nil
            return false
        } catch JobsError.imageTooLarge {
            photoError = .tooLarge
            submitError = nil
            return false
        } catch JobsError.invalidMetadata {
            submitError = "Please check the pose name and tags."
            return false
        } catch {
            submitError = "Couldn't add your pose. Your draft is kept on this iPhone."
            return false
        }
    }

    // MARK: - Processing

    /// The stage the processing card names, from the status the server reported.
    var stage: AddPoseStage { AddPoseStage(status: currentJobStatus) }

    var isFailed: Bool { !isJobGone && stage == .failed }

    var isReady: Bool { !isJobGone && stage == .ready }

    /// The Jobs segment the processing footer's "View jobs" asks for, or `nil` while it asks for
    /// nothing. The screen turns it into a push on its own stack.
    ///
    /// It used to be handed to the Poses route instead, which swapped the pushed destination in the
    /// same update as the pop of this screen: the pop won and the user landed on Poses home (reported
    /// twice on build 16). The state stays here so the decision is testable without a view.
    @Published private(set) var requestedJobsTab: JobsTab?

    /// Bumped on every request, so each push gets a link with a fresh identity: a `NavigationLink` that
    /// has already been used once does not push again.
    @Published private(set) var jobsRequestCount = 0

    /// Board `08-board09` "View jobs": a job that is still running belongs on Processing, a settled one
    /// on Finished.
    func requestOpenJobs() {
        guard JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) else { return }
        requestedJobsTab = (stage == .ready || stage == .failed) ? .finish : .processing
        jobsRequestCount += 1
    }

    /// The pushed Jobs screen went away (Back): a second visit must be able to push it again.
    func clearJobsRequest() {
        requestedJobsTab = nil
    }

    func startWatching(jobId: String) {
        watchTask?.cancel()
        currentJobStatus = "queued"
        currentPoseId = nil
        processingError = nil
        isProcessingOffline = false
        isJobGone = false

        watchTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.jobsService.watchJob(id: jobId)
            for await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .status(let jobData):
                    self.currentJobStatus = jobData.status
                    self.currentPoseId = jobData.poseId
                    self.isProcessingOffline = false
                    if let err = jobData.error {
                        self.processingError = err.message ?? "Extraction failed."
                    }
                case .offline:
                    self.isProcessingOffline = true
                case .online:
                    self.isProcessingOffline = false
                case .gone:
                    self.isJobGone = true
                    self.currentJobStatus = "gone"
                }
            }
        }
    }

    func retryProcessing() async {
        guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else {
            processingError = JobsError.extractPoseDisabled.localizedDescription
            return
        }
        guard let jobId = submittedJobId else { return }
        do {
            try await jobsService.retry(id: jobId)
            startWatching(jobId: jobId)
        } catch {
            processingError = error.localizedDescription
        }
    }
}

struct AddPoseScreen: View {
    @StateObject var viewModel: AddPoseViewModel
    @ObservedObject var posesModel: PosesViewModel
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    /// Superseded: the screen now pushes Jobs on its own stack (see `hiddenJobsLink`). Kept so the
    /// Poses route that constructs this screen keeps its contract until that call site is cleaned up.
    var onOpenJobs: (JobsTab) -> Void = { _ in }
    /// Builds the Jobs screen this flow pushes. Production inserts the real screen; a navigation test
    /// inserts a stand-in and still exercises the real push.
    private let jobsDestination: (JobsTab) -> AnyView
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showsPhotoPicker = false
    @State private var pendingSignIn: SignInIntent?
    @State private var detailedPose: NativePose?
    @State private var isLoadingGuide = false
    @FocusState private var isTagFieldFocused: Bool

    init(
        viewModel: AddPoseViewModel = AddPoseViewModel(),
        posesModel: PosesViewModel,
        onTryPose: @escaping (CameraPoseRequest) -> Void = { _ in },
        onOpenJobs: @escaping (JobsTab) -> Void = { _ in },
        jobsDestination: ((JobsTab) -> AnyView)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.posesModel = posesModel
        self.onTryPose = onTryPose
        self.onOpenJobs = onOpenJobs
        self.jobsDestination = jobsDestination ?? { tab in
            AnyView(
                JobsScreen(
                    jobsService: ServiceLocator.jobsService,
                    posesModel: posesModel,
                    initialTab: tab,
                    onTryPose: onTryPose
                )
            )
        }
    }

    /// The flow is one surface with two stages: the form, then the job the upload produced. Back and
    /// Done both pop to Poses, because that is where this screen is pushed from.
    private var isProcessingFlow: Bool { viewModel.submittedJobId != nil }

    var body: some View {
        VStack(spacing: 0) {
            // F1: the title and 79 pt Cancel action share one row.
            HStack(alignment: .center) {
                Text(AddPoseFormCopy.screenTitle)
                    .font(AP.Font.display)
                    .foregroundStyle(AP.Color.primaryText)
                    .accessibilityIdentifier("addPose.title")
                Spacer(minLength: AP.Space.space8)
                Button("Cancel") { dismiss() }
                    .font(AP.Font.heading)
                    .foregroundStyle(AP.Color.accentText)
                    .frame(minWidth: 79, minHeight: AP.HitTarget.minimum, alignment: .trailing)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("addPose.cancelButton")
            }
            .padding(.horizontal, AP.Space.space24)
            .padding(.top, AP.Space.space8)
            .padding(.bottom, AP.Space.space12)

            if !AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) && !isProcessingFlow {
                extractionDisabled
            } else if isProcessingFlow {
                processingBody
            } else if let photoError = viewModel.photoError {
                unusablePhotoBody(photoError)
            } else {
                formBody
            }
        }
        .background(AP.Color.background.ignoresSafeArea())
        .neoHiddenNavigationBar()
        .onAppear {
            // The Poses `+` begins with the system photo picker; cancelling it leaves the draft screen
            // available so the user can cancel or choose a photo later.
            if viewModel.selectedImage == nil && viewModel.submittedJobId == nil {
                showsPhotoPicker = true
            }
        }
        .sheet(isPresented: $showsPhotoPicker) {
            PhotoLibraryPicker(
                selectedImage: $viewModel.selectedImage,
                selectedImageData: $viewModel.selectedImageData,
                selectedFileName: $viewModel.selectedFileName
            )
        }
        .sheet(
            isPresented: $viewModel.isConsentPromptVisible,
            onDismiss: { viewModel.cancelConsent() }
        ) {
            AddPoseConsentSheet(
                onAllow: { Task { await viewModel.allowConsent() } },
                onCancel: { viewModel.cancelConsent() }
            )
        }
        .signInPrompt($pendingSignIn) { intent in
            if intent == .addPose {
                Task { await viewModel.submit() }
            }
        }
        .background(
            Group {
                hiddenDetailLink
                hiddenJobsLink
            }
        )
    }

    /// The processing footer's "View jobs" is a plain push on this screen's own stack, the same
    /// mechanism the pose detail above uses. Handing the tab to the Poses route instead swapped the
    /// pushed destination in the same update as this screen's pop, so the pop won and the user landed
    /// back on Poses home.
    ///
    /// The link stays in the hierarchy and only its `isActive` toggles, with a fresh identity per
    /// request: a link that is inserted already active fires once, and one that has already been used
    /// does not fire again, so a second "View jobs" would do nothing without the identity bump.
    private var hiddenJobsLink: some View {
        NavigationLink(
            destination: Group {
                if let tab = viewModel.requestedJobsTab {
                    jobsDestination(tab)
                }
            },
            isActive: Binding(
                get: { viewModel.requestedJobsTab != nil },
                set: { isPresented in
                    if !isPresented { viewModel.clearJobsRequest() }
                }
            )
        ) {
            EmptyView()
        }
        .id(viewModel.jobsRequestCount)
        .hidden()
    }

    private var hiddenDetailLink: some View {
        Group {
            if let detailedPose {
                NavigationLink(
                    destination: PoseDetailScreen(
                        pose: detailedPose,
                        model: posesModel,
                        onTryPose: onTryPose,
                        isPrivate: true
                    ),
                    isActive: Binding(
                        get: { true },
                        set: { if !$0 { self.detailedPose = nil } }
                    )
                ) {
                    EmptyView()
                }
                .hidden()
            }
        }
    }

    // MARK: - Extraction switched off

    private var extractionDisabled: some View {
        APErrorStateView(
            title: AddPoseFormCopy.extractOffTitle,
            message: AddPoseFormCopy.extractOffMessage,
            retry: nil,
            style: .plain
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func unusablePhotoBody(_ error: AddPosePhotoError) -> some View {
        VStack(alignment: .leading, spacing: AP.Space.space16) {
            APStatusBanner(tone: .error, title: AddPoseFormCopy.photoErrorTitle, message: error.message)
            Button(AddPoseFormCopy.chooseAnotherPhoto) {
                viewModel.clearPhotoError()
                showsPhotoPicker = true
            }
            .buttonStyle(APPrimaryButtonStyle())
            .accessibilityIdentifier("addPose.chooseAnotherPhoto")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Form

    private var formBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AP.Space.space24) {
                    if viewModel.isOffline {
                        offlineBanner
                    }
                    photoBlock
                    tagsBlock
                    descriptionBlock
                }
                .padding(.horizontal, AP.Space.space16)
                .padding(.top, AP.Space.space8)
                .padding(.bottom, AP.Space.space24)
            }
            // F5: a failed submit is announced at the bottom, right above the pinned CTA.
            .apSnackbar(viewModel.snackbarMessage, tone: .error) { viewModel.dismissSubmitError() }
            .onChange(of: viewModel.selectedImageData) { _ in viewModel.clearPhotoError() }
            .onChange(of: isTagFieldFocused) { isFocused in
                // Leaving the field keeps whatever was typed instead of silently dropping a tag.
                if !isFocused { viewModel.commitTagDraft() }
            }

            formFooter
        }
    }

    private var offlineBanner: some View {
        APOfflineBanner(
            message: AddPoseFormCopy.offlineBanner,
            retryTitle: nil,
            retry: nil
        )
        .accessibilityIdentifier("addPose.offlineBanner")
    }

    @ViewBuilder
    private var photoBlock: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AP.Space.space16) {
                photoTile
                nameColumn
            }
        } else {
            HStack(alignment: .top, spacing: AP.Space.space16) {
                photoTile
                nameColumn
            }
        }
    }

    private var photoTile: some View {
        Button {
            showsPhotoPicker = true
        } label: {
            Group {
                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        AP.Color.controlFill
                        Image(systemName: viewModel.photoError == nil ? "photo" : "exclamationmark.triangle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(viewModel.photoError == nil ? AP.Color.secondaryText : AP.Color.error)
                    }
                }
            }
            .frame(width: 88, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addPose.photoPicker")
        .accessibilityLabel(viewModel.selectedImage == nil ? AddPoseFormCopy.choosePhoto : AddPoseFormCopy.changePhoto)
    }

    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: AP.Space.space8) {
            fieldLabel(AddPoseFormCopy.nameLabel)
            nameField
            if let message = viewModel.nameFieldError {
                fieldError(message)
            }
            photoActionLink
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameField: some View {
        TextField(AddPoseFormCopy.namePlaceholder, text: $viewModel.name)
            .font(AP.Font.body)
            .foregroundStyle(AP.Color.primaryText)
            .submitLabel(.done)
            .padding(.horizontal, AP.Space.space16)
            .frame(minHeight: 52)
            .background(fieldBackground)
            .overlay(alignment: .trailing) {
                if viewModel.nameFieldError != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AP.Color.error)
                        .padding(.trailing, AP.Space.space16)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("addPose.nameField")
    }

    private var photoActionLink: some View {
        Button {
            showsPhotoPicker = true
        } label: {
            Text(photoActionTitle)
                .font(AP.Font.supporting.weight(.semibold))
                .foregroundStyle(AP.Color.accentText)
                .frame(minHeight: AP.HitTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addPose.changePhotoButton")
    }

    private var tagsBlock: some View {
        VStack(alignment: .leading, spacing: AP.Space.space12) {
            fieldLabel(AddPoseFormCopy.tagsLabel)
            if !viewModel.parsedTags.isEmpty {
                tagChips
            }
            tagField
            if let message = viewModel.tagsFieldError {
                fieldError(message)
            }
        }
    }

    @ViewBuilder
    private var tagChips: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AP.Space.space8) {
                ForEach(viewModel.parsedTags, id: \.self) { tag in
                    tagChip(tag, fillsWidth: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AP.Space.space8) {
                    ForEach(viewModel.parsedTags, id: \.self) { tag in
                        tagChip(tag, fillsWidth: false)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func tagChip(_ tag: String, fillsWidth: Bool) -> some View {
        APCategoryChip(title: tag, isSelected: true, usesNeutralSelection: true, fillsWidth: fillsWidth) {
            viewModel.removeTag(tag)
        }
        .accessibilityIdentifier("addPose.tag.\(tag)")
        .accessibilityHint("Removes this tag")
    }

    /// The tags are the chips; this field exists to add one. It commits on Return, on a comma, and when
    /// the field loses focus, so a typed tag is never lost.
    private var tagField: some View {
        HStack(spacing: AP.Space.space8) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AP.Color.primaryText)
                .accessibilityHidden(true)
            TextField(AddPoseFormCopy.tagPlaceholder, text: $viewModel.tagDraft)
                .font(AP.Font.body)
                .foregroundStyle(AP.Color.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isTagFieldFocused)
                .onSubmit { viewModel.commitTagDraft() }
                .onChange(of: viewModel.tagDraft) { _ in viewModel.commitCompletedTags() }
                .accessibilityIdentifier("addPose.tagsField")
        }
        .padding(.horizontal, AP.Space.space16)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(fieldBackground)
    }

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: AP.Space.space8) {
            HStack(alignment: .firstTextBaseline, spacing: AP.Space.space8) {
                fieldLabel(AddPoseFormCopy.descriptionLabel)
                Spacer(minLength: AP.Space.space8)
                Text("\(viewModel.descriptionText.count)/\(AddPoseViewModel.descriptionLimit)")
                    .font(AP.Font.caption)
                    .foregroundStyle(viewModel.descriptionFieldError == nil ? AP.Color.secondaryText : AP.Color.error)
                    .accessibilityIdentifier("addPose.descriptionCounter")
            }
            descriptionEditor
            if let message = viewModel.descriptionFieldError {
                fieldError(message)
            }
        }
    }

    private var descriptionEditor: some View {
        TextEditor(text: $viewModel.descriptionText)
            .font(AP.Font.body)
            .foregroundStyle(AP.Color.primaryText)
            .padding(AP.Space.space12)
            .frame(minHeight: 132)
            .background(fieldBackground)
            .apTransparentTextEditorBackground()
            .overlay(alignment: .topLeading) {
                if viewModel.descriptionText.isEmpty {
                    Text(AddPoseFormCopy.descriptionPlaceholder)
                        .font(AP.Font.body)
                        .foregroundStyle(AP.Color.secondaryText)
                        .padding(AP.Space.space16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("addPose.descriptionField")
    }

    private var formFooter: some View {
        VStack(spacing: AP.Space.space12) {
            if let hint = viewModel.submitHint {
                Text(hint)
                    .font(AP.Font.supporting)
                    .foregroundStyle(AP.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("addPose.submitHint")
            }

            Button { submitTapped() } label: {
                HStack(spacing: AP.Space.space8) {
                    if viewModel.isSubmitting {
                        ProgressView().tint(AP.Color.onAccent)
                    }
                    Text(viewModel.isSubmitting ? AddPoseFormCopy.addingPose : AddPoseFormCopy.addPose)
                }
            }
            .buttonStyle(APPrimaryButtonStyle())
            .disabled(!viewModel.isSubmitEnabled)
            .accessibilityIdentifier("addPose.submitButton")
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space12)
        .padding(.bottom, AP.Space.space4)
        .background(AP.Color.background)
    }

    // MARK: - Shared field chrome

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
            .fill(AP.Color.controlFill)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AP.Font.heading)
            .foregroundStyle(AP.Color.primaryText)
    }

    /// Glyph and copy together, so a field error never rests on colour alone.
    private func fieldError(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AP.Space.space8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(AP.Font.caption)
        .foregroundStyle(AP.Color.error)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The link under the photo names the next step: choose, change, or replace the photo that could
    /// not be read (board `08-board08`).
    private var photoActionTitle: String {
        if viewModel.photoError != nil { return AddPoseFormCopy.chooseAnotherPhoto }
        return viewModel.selectedImage == nil ? AddPoseFormCopy.choosePhoto : AddPoseFormCopy.changePhoto
    }

    // MARK: - Actions

    private func submitTapped() {
        guard viewModel.isSubmitEnabled else { return }
        viewModel.showsFieldErrors = true
        // Without a photo there is nothing to upload: send the user straight to the picker instead of
        // showing an error about a control they have not used yet.
        guard viewModel.selectedImageData != nil else {
            showsPhotoPicker = true
            return
        }
        Task {
            let hasSession = await ServiceLocator.sessionBoundary.hasStoredSession()
            if !hasSession {
                pendingSignIn = .addPose
            } else {
                _ = await viewModel.submit()
            }
        }
    }

    private func loadGuide(poseId: String) {
        Task {
            isLoadingGuide = true
            defer { isLoadingGuide = false }
            do {
                let guide = try await ServiceLocator.jobsService.getGuide(id: poseId)
                self.detailedPose = GuidePoseMapper.map(guide, baseURL: AppConfig.shared.SERVER_BASE_URL)
            } catch {
                // The processing card already reports the job's own failure; a guide that will not load
                // leaves the user on this screen with View jobs and Done.
            }
        }
    }

    // MARK: - Processing

    private var processingBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AP.Space.space16) {
                    if viewModel.isJobGone {
                        APEmptyStateView(
                            title: AddPoseFormCopy.jobGoneTitle,
                            message: AddPoseFormCopy.jobGoneMessage
                        )
                    } else if viewModel.isFailed {
                        APErrorStateView(
                            title: AddPoseFormCopy.extractionFailedTitle,
                            message: "Your draft is kept on this iPhone.",
                            retryTitle: AddPoseFormCopy.retry,
                            retry: canRetry ? { Task { await viewModel.retryProcessing() } } : nil,
                            actionIdentifier: "addPose.retryButton"
                        )
                    } else {
                        AddPoseProcessingCard(
                            name: viewModel.poseName,
                            stage: viewModel.stage,
                            image: viewModel.selectedImage
                        )
                        if viewModel.isProcessingOffline {
                            APStatusBanner(tone: .warning, title: AddPoseFormCopy.processingOffline)
                                .accessibilityIdentifier("addPose.processingOfflineBanner")
                        }
                    }
                }
                .padding(.horizontal, AP.Space.space16)
                .padding(.top, AP.Space.space8)
                .padding(.bottom, AP.Space.space24)
            }

            processingFooter
        }
    }

    private var canRetry: Bool {
        AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled)
    }

    private var processingFooter: some View {
        VStack(spacing: AP.Space.space12) {
            if viewModel.isReady, let poseId = viewModel.currentPoseId {
                Button {
                    loadGuide(poseId: poseId)
                } label: {
                    HStack(spacing: AP.Space.space8) {
                        if isLoadingGuide {
                            ProgressView().tint(AP.Color.onAccent)
                        }
                        Text(AddPoseFormCopy.viewPose)
                    }
                }
                .buttonStyle(APPrimaryButtonStyle())
                .accessibilityIdentifier("addPose.viewPoseButton")
            }

            if JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) {
                Button(AddPoseFormCopy.viewJobs) { viewModel.requestOpenJobs() }
                    .buttonStyle(APButtonStyleForKind(kind: viewJobsKind))
                    .accessibilityIdentifier("addPose.viewJobsButton")
            }

            Button(AddPoseFormCopy.done) { dismiss() }
                .buttonStyle(APSecondaryButtonStyle())
                .accessibilityIdentifier("addPose.doneButton")
        }
        .padding(.horizontal, AP.Space.space16)
        .padding(.top, AP.Space.space12)
        .padding(.bottom, AP.Space.space8)
        .background(AP.Color.background)
    }

    /// While the job is still running, View jobs is the one useful action; once it settles, marking it
    /// secondary keeps the quieter "Done — status continues in Jobs" reading of the board.
    private var viewJobsKind: APButtonKind {
        (viewModel.isReady || viewModel.isFailed) ? .secondary : .primary
    }
}

// MARK: - Processing card

/// The job as a share card: the photo, its name, the stage the server reported and an indeterminate
/// bar. No percentage and no ETA — the backend reports a state, not a fraction.
struct AddPoseProcessingCard: View {
    let name: String
    let stage: AddPoseStage
    var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space12) {
            HStack(alignment: .top, spacing: AP.Space.space16) {
                thumbnail
                VStack(alignment: .leading, spacing: AP.Space.space4) {
                    Text(name)
                        .font(AP.Font.heading)
                        .foregroundStyle(AP.Color.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: AP.Space.space8) {
                        Image(systemName: stage.glyph)
                            .font(AP.Font.caption)
                            .foregroundStyle(stage.tint)
                            .accessibilityHidden(true)
                        Text(stage.label)
                            .font(AP.Font.supporting)
                            .foregroundStyle(AP.Color.secondaryText)
                            .accessibilityIdentifier("addPose.stageStatus")
                    }
                }
                Spacer(minLength: 0)
            }

            AddPoseIndeterminateBar()

            Text(AddPoseFormCopy.leaveHint)
                .font(AP.Font.caption)
                .foregroundStyle(AP.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AP.Space.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius24, style: .continuous)
                .fill(AP.Color.surface)
        )
        .apElevation(.e1, cornerRadius: AP.Radius.radius24)
        .accessibilityElement(children: .contain)
    }

    private var thumbnail: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    AP.Color.controlFill
                    Image(systemName: "photo")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AP.Color.secondaryText)
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous))
        .accessibilityHidden(true)
    }
}

private extension AddPoseStage {
    var tint: SwiftUI.Color {
        switch self {
        case .queued, .processing: return AP.Color.secondaryText
        case .ready: return AP.Color.success
        case .failed: return AP.Color.error
        }
    }
}

/// Indeterminate progress: accent stripes that slide, never a number. Reduce Motion keeps the stripes
/// still — the stage word beside the bar carries the state.
struct AddPoseIndeterminateBar: View {
    static let height: CGFloat = 10
    static let stripeWidth: CGFloat = 12
    static let cycleDuration: Double = 0.9

    /// `nil` under Reduce Motion, so nothing sweeps across the screen.
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .linear(duration: cycleDuration).repeatForever(autoreverses: false)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shift: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let stripe = Self.stripeWidth
            let period = stripe * 2
            var offset = -size.height + shift.truncatingRemainder(dividingBy: period)
            while offset < size.width {
                var path = Path()
                path.move(to: CGPoint(x: offset, y: size.height))
                path.addLine(to: CGPoint(x: offset + stripe, y: size.height))
                path.addLine(to: CGPoint(x: offset + stripe + size.height, y: 0))
                path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                path.closeSubpath()
                context.fill(path, with: .color(AP.Color.accentText))
                offset += period
            }
        }
        .frame(height: Self.height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
        .onAppear(perform: start)
    }

    private func start() {
        guard let animation = Self.animation(reduceMotion: reduceMotion) else { return }
        withAnimation(animation) { shift = Self.stripeWidth * 2 }
    }
}

// MARK: - iOS 15 text editor background

private extension View {
    /// iOS 15's `TextEditor` paints its own opaque system background, which would cover the
    /// `controlFill` field the board draws; iOS 16 hides it declaratively.
    @ViewBuilder
    func apTransparentTextEditorBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self.onAppear { UITextView.appearance().backgroundColor = .clear }
        }
    }
}
