import SwiftUI

enum JobsTab: String, CaseIterable, Identifiable {
    case processing = "Processing"
    case finish = "Finish"
    var id: String { rawValue }
}

enum FinishFilter: String, CaseIterable, Identifiable {
    case all = "All results"
    case success = "Success"
    case fail = "Fail"
    var id: String { rawValue }
}

struct JobsScreen<Service: JobsServing & ObservableObject>: View {
    @ObservedObject var jobsService: Service
    @ObservedObject var posesModel: PosesViewModel
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    var onAddPose: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: JobsTab = .processing
    @State private var finishFilter: FinishFilter = .all
    @State private var jobToHide: JobRow?
    @State private var detailedPose: NativePose?
    @State private var isFetchingGuide = false
    @State private var actionErrorMessage: String?

    init(
        jobsService: Service,
        posesModel: PosesViewModel,
        initialTab: JobsTab = .processing,
        onTryPose: @escaping (CameraPoseRequest) -> Void = { _ in },
        onAddPose: @escaping () -> Void = {}
    ) {
        self.jobsService = jobsService
        self.posesModel = posesModel
        self._selectedTab = State(initialValue: initialTab)
        self.onTryPose = onTryPose
        self.onAddPose = onAddPose
    }

    var body: some View {
        VStack(spacing: 0) {
            NeoSubscreenHeader(title: "Jobs", onBack: { dismiss() })

            tabSelector

            if selectedTab == .finish {
                finishFilterChips
            }

            content
        }
        .background(AIPoseColor.background)
        .neoHiddenNavigationBar()
        .onAppear {
            jobsService.startPolling()
        }
        .onDisappear {
            jobsService.stopPolling()
        }
        .confirmationDialog(
            "Remove job?",
            isPresented: Binding(
                get: { jobToHide != nil },
                set: { if !$0 { jobToHide = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let job = jobToHide {
                    Task {
                        do {
                            try await jobsService.hide(id: job.jobId)
                        } catch {
                            actionErrorMessage = error.localizedDescription
                        }
                    }
                }
                jobToHide = nil
            }
            Button("Keep", role: .cancel) {
                jobToHide = nil
            }
        } message: {
            Text("This removes the job from your list. It will not delete the created pose.")
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                actionErrorMessage = nil
            }
        } message: {
            if let actionErrorMessage {
                Text(actionErrorMessage)
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

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(JobsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Text(tab.rawValue)
                                .font(.system(size: 15, weight: .bold))
                            if tab == .processing && jobsService.activeCount > 0 {
                                Text("\(jobsService.activeCount)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AIPoseColor.accentBlue)
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundStyle(selectedTab == tab ? AIPoseColor.foreground : AIPoseColor.subtext)

                        Rectangle()
                            .fill(selectedTab == tab ? AIPoseColor.foreground : Color.clear)
                            .frame(height: 3)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("jobs.tab.\(tab.rawValue.lowercased())")
            }
        }
        .padding(.horizontal, AIPoseSpacing.lg)
        .padding(.top, AIPoseSpacing.xs)
    }

    private var finishFilterChips: some View {
        HStack(spacing: AIPoseSpacing.sm) {
            ForEach(FinishFilter.allCases) { filter in
                NeoFilterChip(
                    title: filter.rawValue,
                    isSelected: finishFilter == filter
                ) {
                    finishFilter = filter
                }
                .accessibilityIdentifier("jobs.filter.\(filter.rawValue.lowercased())")
            }
            Spacer()
        }
        .padding(.horizontal, AIPoseSpacing.lg)
        .padding(.vertical, AIPoseSpacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        let rows = currentRows
        if jobsService.isOffline && rows.isEmpty {
            VStack(spacing: AIPoseSpacing.md) {
                FeatureStateView(
                    tone: .offline,
                    title: "You're offline",
                    message: "You're offline — statuses update when you're back online."
                )
                .padding(.horizontal, AIPoseSpacing.lg)
                Spacer()
            }
            .padding(.top, AIPoseSpacing.md)
        } else if case .loading = jobsService.loadState, rows.isEmpty {
            VStack(spacing: AIPoseSpacing.md) {
                ProgressView()
                    .tint(AIPoseColor.foreground)
                    .scaleEffect(1.2)
                Text("Loading jobs...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AIPoseColor.subtext)
                Spacer()
            }
            .padding(.top, AIPoseSpacing.xl)
        } else if case .failed(let message) = jobsService.loadState, rows.isEmpty {
            VStack(spacing: AIPoseSpacing.md) {
                FeatureStateView(
                    tone: .error,
                    title: "Couldn't load jobs",
                    message: message,
                    actionTitle: "Try again"
                ) {
                    Task { await jobsService.refresh() }
                }
                .padding(.horizontal, AIPoseSpacing.lg)
                Spacer()
            }
            .padding(.top, AIPoseSpacing.lg)
        } else if rows.isEmpty {
            emptyState
        } else {
            List {
                if jobsService.isOffline {
                    FeatureStateView(
                        tone: .offline,
                        title: "You're offline",
                        message: "You're offline — statuses update when you're back online."
                    )
                    .listRowInsets(EdgeInsets(top: AIPoseSpacing.xs, leading: AIPoseSpacing.lg, bottom: AIPoseSpacing.xs, trailing: AIPoseSpacing.lg))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                ForEach(rows) { row in
                    JobRowView(
                        row: row,
                        onAction: handleRowAction,
                        onHide: selectedTab == .finish ? { target in
                            jobToHide = target
                        } : nil
                    )
                    .listRowInsets(EdgeInsets(top: AIPoseSpacing.xs, leading: AIPoseSpacing.lg, bottom: AIPoseSpacing.xs, trailing: AIPoseSpacing.lg))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if selectedTab == .finish {
                            Button(role: .destructive) {
                                jobToHide = row
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .accessibilityIdentifier("jobs.row.remove.\(row.jobId)")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .transparentListBackground()
            .background(AIPoseColor.background)
            .refreshable {
                await jobsService.refresh()
            }
        }
    }

    private var currentRows: [JobRow] {
        switch selectedTab {
        case .processing:
            return jobsService.inProgress
        case .finish:
            switch finishFilter {
            case .all:
                return jobsService.finished
            case .success:
                return jobsService.finished.filter { $0.status == .succeeded }
            case .fail:
                return jobsService.finished.filter { $0.status == .failed }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AIPoseSpacing.md) {
            FeatureStateView(
                tone: .empty,
                title: "No jobs yet",
                message: "Pose extraction jobs will appear here when you submit a pose.",
                actionTitle: AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) ? "Add pose" : nil
            ) {
                if AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) {
                    onAddPose()
                    dismiss()
                }
            }
            .padding(.horizontal, AIPoseSpacing.lg)
            Spacer()
        }
        .padding(.top, AIPoseSpacing.lg)
    }

    private func handleRowAction(_ row: JobRow) {
        switch row.action {
        case .none:
            break
        case .retry:
            guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else { return }
            Task {
                do {
                    try await jobsService.retry(id: row.jobId)
                } catch {
                    actionErrorMessage = error.localizedDescription
                }
            }
        case .viewPose:
            guard let poseId = row.poseId else { return }
            Task {
                isFetchingGuide = true
                defer { isFetchingGuide = false }
                do {
                    let guide = try await jobsService.getGuide(id: poseId)
                    self.detailedPose = GuidePoseMapper.map(guide, baseURL: AppConfig.shared.SERVER_BASE_URL)
                } catch {
                    actionErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

extension JobsScreen where Service == JobsService {
    init(
        jobsService: JobsService = ServiceLocator.jobsService,
        posesModel: PosesViewModel,
        initialTab: JobsTab = .processing,
        onTryPose: @escaping (CameraPoseRequest) -> Void = { _ in },
        onAddPose: @escaping () -> Void = {}
    ) {
        self.jobsService = jobsService
        self.posesModel = posesModel
        self._selectedTab = State(initialValue: initialTab)
        self.onTryPose = onTryPose
        self.onAddPose = onAddPose
    }
}

private extension View {
    @ViewBuilder
    func transparentListBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self.onAppear {
                UITableView.appearance().backgroundColor = .clear
            }
        }
    }
}
