import Kingfisher
import SwiftUI

@MainActor
final class AddPoseViewModel: ObservableObject {
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

    private let jobsService: any JobsServing
    private var watchTask: Task<Void, Never>?

    init(jobsService: any JobsServing = ServiceLocator.jobsService) {
        self.jobsService = jobsService
    }

    deinit {
        watchTask?.cancel()
    }

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
        guard !tags.isEmpty && tags.count <= 10 else { return false }
        guard descriptionText.count <= 500 else { return false }
        return true
    }

    func submit() async -> Bool {
        guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else {
            submitError = "Pose extraction is currently disabled."
            return false
        }
        guard isFormValid, let imageData = selectedImageData, let fileName = selectedFileName else {
            return false
        }

        isSubmitting = true
        submitError = nil
        isOffline = false
        defer { isSubmitting = false }

        let draft = PoseDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: parsedTags,
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        )

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
            submitError = "You're offline. Check your connection."
            return false
        } catch JobsError.invalidImage {
            submitError = "Only JPEG and PNG images are supported. Choose another photo."
            return false
        } catch JobsError.imageTooLarge {
            submitError = "Photo exceeds the 10 MB limit. Choose another photo."
            return false
        } catch JobsError.invalidMetadata {
            submitError = "Please check the pose name and tags."
            return false
        } catch {
            submitError = "Couldn't send. Try again."
            return false
        }
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
    var onOpenJobs: (JobsTab) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var showsPhotoPicker = false
    @State private var pendingSignIn: SignInIntent?
    @State private var detailedPose: NativePose?
    @State private var isLoadingGuide = false

    init(
        viewModel: AddPoseViewModel = AddPoseViewModel(),
        posesModel: PosesViewModel,
        onTryPose: @escaping (CameraPoseRequest) -> Void = { _ in },
        onOpenJobs: @escaping (JobsTab) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.posesModel = posesModel
        self.onTryPose = onTryPose
        self.onOpenJobs = onOpenJobs
    }

    var body: some View {
        VStack(spacing: 0) {
            NeoSubscreenHeader(
                title: viewModel.submittedJobId == nil ? "Add Pose" : "Processing Pose",
                onBack: { dismiss() }
            )

            if !AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) && viewModel.submittedJobId == nil {
                VStack(spacing: AIPoseSpacing.md) {
                    FeatureStateView(
                        tone: .error,
                        title: "Pose Extraction Disabled",
                        message: "Pose extraction is currently unavailable."
                    )
                    .padding(.horizontal, AIPoseSpacing.lg)
                    Spacer()
                }
                .padding(.top, AIPoseSpacing.xl)
            } else if viewModel.submittedJobId == nil {
                formView
            } else {
                processingView
            }
        }
        .background(AIPoseColor.background)
        .neoHiddenNavigationBar()
        .sheet(isPresented: $showsPhotoPicker) {
            PhotoLibraryPicker(
                selectedImage: $viewModel.selectedImage,
                selectedImageData: $viewModel.selectedImageData,
                selectedFileName: $viewModel.selectedFileName
            )
        }
        .signInPrompt($pendingSignIn) { intent in
            if intent == .addPose {
                Task { await viewModel.submit() }
            }
        }
        .background(
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
        )
    }

    // MARK: - Form View
    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AIPoseSpacing.lg) {
                // Photo picker area
                photoPickerArea

                // Name field
                VStack(alignment: .leading, spacing: AIPoseSpacing.xs) {
                    Text("Pose Name *")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AIPoseColor.foreground)

                    TextField("e.g. Standing Hero Pose", text: $viewModel.name)
                        .font(.body)
                        .padding(.horizontal, AIPoseSpacing.md)
                        .frame(minHeight: 48)
                        .background(AIPoseColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AIPoseColor.foreground, lineWidth: 2))
                        .accessibilityIdentifier("addPose.nameField")
                }

                // Tags field
                VStack(alignment: .leading, spacing: AIPoseSpacing.xs) {
                    Text("Tags (1–10, comma-separated) *")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AIPoseColor.foreground)

                    TextField("e.g. standing, full body, beginner", text: $viewModel.tagsText)
                        .font(.body)
                        .padding(.horizontal, AIPoseSpacing.md)
                        .frame(minHeight: 48)
                        .background(AIPoseColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AIPoseColor.foreground, lineWidth: 2))
                        .accessibilityIdentifier("addPose.tagsField")
                }

                // Description field
                VStack(alignment: .leading, spacing: AIPoseSpacing.xs) {
                    HStack {
                        Text("Description (Optional)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AIPoseColor.foreground)
                        Spacer()
                        Text("\(viewModel.descriptionText.count)/500")
                            .font(.caption)
                            .foregroundStyle(viewModel.descriptionText.count > 500 ? AIPoseColor.error : AIPoseColor.subtext)
                    }

                    TextEditor(text: $viewModel.descriptionText)
                        .font(.body)
                        .frame(minHeight: 96)
                        .padding(AIPoseSpacing.sm)
                        .background(AIPoseColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AIPoseColor.foreground, lineWidth: 2))
                        .accessibilityIdentifier("addPose.descriptionField")
                }

                // Error card
                if let error = viewModel.submitError {
                    FeatureStateView(
                        tone: .error,
                        title: "Couldn't add pose",
                        message: error
                    )
                    .accessibilityIdentifier("addPose.errorView")
                }

                // Submit button
                Button {
                    Task {
                        let hasSession = await ServiceLocator.sessionBoundary.hasStoredSession()
                        if !hasSession {
                            pendingSignIn = .addPose
                        } else {
                            _ = await viewModel.submit()
                        }
                    }
                } label: {
                    HStack(spacing: AIPoseSpacing.sm) {
                        if viewModel.isSubmitting {
                            ProgressView().tint(AIPoseColor.foreground)
                        }
                        Text(viewModel.isSubmitting ? "Submitting…" : "Extract Pose")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(NeoButtonStyle(fill: viewModel.isFormValid && !viewModel.isOffline ? AIPoseColor.primary : AIPoseColor.surfaceVariant))
                .disabled(!viewModel.isFormValid || viewModel.isSubmitting || viewModel.isOffline)
                .accessibilityIdentifier("addPose.submitButton")
            }
            .padding(AIPoseSpacing.lg)
        }
    }

    private var photoPickerArea: some View {
        Button {
            showsPhotoPicker = true
        } label: {
            if let image = viewModel.selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AIPoseColor.foreground, lineWidth: 2))

                    Text("Change Photo")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AIPoseColor.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AIPoseColor.foreground, lineWidth: 1.5))
                        .padding(8)
                }
            } else {
                VStack(spacing: AIPoseSpacing.sm) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(AIPoseColor.foreground)
                    Text("Choose photo from library")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AIPoseColor.foreground)
                    Text("JPEG or PNG, max 10 MB")
                        .font(.caption)
                        .foregroundStyle(AIPoseColor.subtext)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(AIPoseColor.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AIPoseColor.foreground, style: StrokeStyle(lineWidth: 2, dash: [6]))
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addPose.photoPicker")
    }

    // MARK: - Processing View
    private var processingView: some View {
        ScrollView {
            VStack(spacing: AIPoseSpacing.lg) {
                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AIPoseColor.foreground, lineWidth: 2))
                }

                // Processing Status
                processingStatusCard

                // Action Buttons
                VStack(spacing: AIPoseSpacing.md) {
                    if viewModel.currentJobStatus.lowercased() == "succeeded", let poseId = viewModel.currentPoseId {
                        Button {
                            Task {
                                isLoadingGuide = true
                                defer { isLoadingGuide = false }
                                do {
                                    let guide = try await ServiceLocator.jobsService.getGuide(id: poseId)
                                    self.detailedPose = GuidePoseMapper.map(guide, baseURL: AppConfig.shared.SERVER_BASE_URL)
                                } catch {
                                    // fallback
                                }
                            }
                        } label: {
                            HStack {
                                if isLoadingGuide { ProgressView().tint(AIPoseColor.foreground) }
                                Text("View pose")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(NeoButtonStyle(fill: AIPoseColor.primary))
                        .accessibilityIdentifier("addPose.viewPoseButton")
                    }

                    if JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) {
                        Button {
                            guard JobsEntryPolicy.canOpen(extractPoseEnabled: AppConfig.shared.isExtractPoseEnabled) else { return }
                            let targetTab: JobsTab = (viewModel.currentJobStatus.lowercased() == "succeeded" || viewModel.currentJobStatus.lowercased() == "failed") ? .finish : .processing
                            onOpenJobs(targetTab)
                        } label: {
                            Text("View jobs")
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(NeoButtonStyle(fill: viewModel.currentJobStatus.lowercased() == "succeeded" ? AIPoseColor.surface : AIPoseColor.primary))
                        .accessibilityIdentifier("addPose.viewJobsButton")
                    }

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(NeoButtonStyle(fill: AIPoseColor.surface))
                    .accessibilityIdentifier("addPose.doneButton")
                }
            }
            .padding(AIPoseSpacing.lg)
        }
    }

    @ViewBuilder
    private var processingStatusCard: some View {
        if viewModel.isJobGone {
            FeatureStateView(
                tone: .empty,
                title: "Job Removed",
                message: "This job was removed."
            )
        } else if viewModel.currentJobStatus.lowercased() == "failed" {
            VStack(spacing: AIPoseSpacing.md) {
                FeatureStateView(
                    tone: .error,
                    title: "Extraction Failed",
                    message: viewModel.processingError ?? "Pose extraction could not be completed.",
                    actionTitle: AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) ? "Retry" : nil
                ) {
                    guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else { return }
                    Task { await viewModel.retryProcessing() }
                }
            }
        } else if viewModel.currentJobStatus.lowercased() == "succeeded" {
            FeatureStateView(
                tone: .success,
                title: "Pose Ready",
                message: "Pose extraction completed successfully."
            )
        } else {
            // Queued or Processing
            VStack(spacing: AIPoseSpacing.sm) {
                FeatureStateView(
                    tone: .loading,
                    title: viewModel.currentJobStatus.lowercased() == "queued" ? "Queued" : "Extracting Pose",
                    message: viewModel.isProcessingOffline
                        ? "You're offline — polling will resume when you're back online."
                        : "Detecting pose skeleton from your image. This usually takes a few seconds."
                )
            }
        }
    }
}
