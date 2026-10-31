import SwiftUI

/// The two segments of the Jobs screen. Boards `09-board01/03` label them "Processing" / "Finished";
/// `rawValue` and `identifier` are kept from the previous header so the committed `jobs.tab.finish`
/// flows still tap the same control.
enum JobsTab: String, CaseIterable, Identifiable {
    case processing = "Processing"
    case finish = "Finish"

    var id: String { rawValue }

    /// Board label of the segment.
    var title: String {
        switch self {
        case .processing: return "Processing"
        case .finish: return "Finished"
        }
    }

    /// Existing accessibility identifier suffix (`jobs.tab.processing` / `jobs.tab.finish`).
    var identifier: String {
        switch self {
        case .processing: return "processing"
        case .finish: return "finish"
        }
    }
}

/// One filter set per segment, in board order: All / Queued / Processing while jobs run and
/// All / Done / Failed once they are finished. The identifier suffixes are the ones QA's flows ask for
/// (`jobs.filter.all|queued|processing|done|failed`).
enum JobsFilter: String, CaseIterable, Identifiable {
    case all
    case queued
    case processing
    case done
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .queued: return "Queued"
        case .processing: return "Processing"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }

    static func filters(for tab: JobsTab) -> [JobsFilter] {
        switch tab {
        case .processing: return [.all, .queued, .processing]
        case .finish: return [.all, .done, .failed]
        }
    }

    func matches(_ row: JobRow) -> Bool {
        switch self {
        case .all: return true
        case .queued: return row.status == .queued
        case .processing: return row.status == .processing
        case .done: return row.status == .succeeded
        case .failed: return row.status == .failed
        }
    }
}

struct JobsScreen<Service: JobsServing & ObservableObject>: View {
    @ObservedObject var jobsService: Service
    @ObservedObject var posesModel: PosesViewModel
    var onTryPose: (CameraPoseRequest) -> Void = { _ in }
    var onAddPose: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedTab: JobsTab = .processing
    @State private var filter: JobsFilter = .all
    @State private var detailedPose: NativePose?
    @State private var isFetchingGuide = false
    @State private var actionMessage: String?

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
            APPageHeader(title: "Jobs", onBack: { dismiss() })

            // Board `09-board08`: while nothing has loaded yet the tabs, the chips and the rows are all
            // placeholders, so the real chrome never pops in above a list that is still coming.
            if isFirstLoad {
                JobsLoadingSkeleton()
            } else {
                segmentControl

                if jobsService.isOffline {
                    offlineBanner
                }

                if showsFilterChips {
                    filterChips
                }

                content
            }
        }
        .background(AP.Color.background)
        .neoHiddenNavigationBar()
        .onAppear {
            jobsService.startPolling()
        }
        .onDisappear {
            jobsService.stopPolling()
        }
        // F5: a failed action lands in a bottom snackbar, never a mid-screen alert.
        .apSnackbar(actionMessage, tone: .error) {
            actionMessage = nil
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

    // MARK: - Segmented tabs

    /// Boards `09-board01/03/07`: one filled pill track, the selected segment on `selectedBackground`
    /// in accent ink. At the Accessibility sizes the two segments stack (`09-board02`).
    private var segmentControl: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    segment(.processing)
                    segment(.finish)
                }
            } else {
                HStack(spacing: 0) {
                    segment(.processing)
                    segment(.finish)
                }
            }
        }
        .padding(AP.Space.space4)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.controlFill)
        )
        .padding(.horizontal, AP.Space.space16)
        .padding(.bottom, AP.Space.space12)
    }

    private func segment(_ tab: JobsTab) -> some View {
        let isSelected = selectedTab == tab
        return HStack(spacing: AP.Space.space8) {
            // The title is the control a flow taps (`jobs.tab.processing`); the running badge is a
            // sibling element so `jobs.tab.processing.count` survives in the accessibility tree.
            Button {
                select(tab)
            } label: {
                Text(tab.title)
                    .font(AP.Font.heading)
                    .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: AP.HitTarget.minimum)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("jobs.tab.\(tab.identifier)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if tab == .processing, jobsService.activeCount > 0 {
                runningBadge(isSelected: isSelected)
            }
        }
        .padding(.horizontal, AP.Space.space12)
        .padding(.vertical, AP.Space.space8)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16 - AP.Space.space4, style: .continuous)
                .fill(isSelected ? AP.Color.selectedBackground : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { select(tab) }
    }

    /// F3: the running count is the ONLY number on this screen, and it is a badge.
    private func runningBadge(isSelected: Bool) -> some View {
        Text("\(jobsService.activeCount)")
            .font(AP.Font.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(AP.Color.selectedForeground)
            .padding(.horizontal, AP.Space.space8)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AP.Color.surface : AP.Color.selectedBackground)
            )
            .accessibilityLabel("\(jobsService.activeCount) running")
            .accessibilityIdentifier("jobs.tab.processing.count")
    }

    private func select(_ tab: JobsTab) {
        guard selectedTab != tab else { return }
        selectedTab = tab
        filter = .all
    }

    // MARK: - Filters

    private var showsFilterChips: Bool {
        !tabRows.isEmpty
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AP.Space.space8) {
                ForEach(JobsFilter.filters(for: selectedTab)) { candidate in
                    JobsFilterChip(
                        title: candidate.title,
                        isSelected: filter == candidate
                    ) {
                        filter = candidate
                    }
                    .accessibilityIdentifier("jobs.filter.\(candidate.rawValue)")
                }
            }
            .padding(.horizontal, AP.Space.space16)
        }
        .padding(.bottom, AP.Space.space12)
    }

    // MARK: - Offline

    /// Board `09-board07`: a flat `warningSurface` banner above the filters. Cached rows keep working
    /// underneath it, and the next successful poll clears it.
    private var offlineBanner: some View {
        HStack(alignment: .top, spacing: AP.Space.space12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AP.Color.warning)
                .accessibilityHidden(true)
            Text(JobsCopy.offlineBanner)
                .font(AP.Font.supporting)
                .foregroundStyle(AP.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AP.Space.space16)
        .background(
            RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                .fill(AP.Color.warningSurface)
        )
        .padding(.horizontal, AP.Space.space16)
        .padding(.bottom, AP.Space.space12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("jobs.offline.banner")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if tabRows.isEmpty {
            if case .failed(let message) = jobsService.loadState {
                APErrorStateView(
                    title: "Couldn't load jobs",
                    message: message,
                    retryTitle: "Try again",
                    retry: { Task { await jobsService.refresh() } },
                    style: .plain
                )
            } else {
                emptyState
            }
        } else if rows.isEmpty {
            filterEmptyState
        } else {
            jobList
        }
    }

    /// A first load has nothing to show anywhere yet. Every later poll also reports `.loading`, so the
    /// skeleton is scoped to this case — an idle segment must not flash placeholders every five seconds.
    private var isFirstLoad: Bool {
        guard case .loading = jobsService.loadState else { return false }
        return jobsService.inProgress.isEmpty && jobsService.finished.isEmpty
    }

    private var jobList: some View {
        let visible = rows
        return List {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                JobRowView(
                    row: row,
                    waitingForConnection: jobsService.isOffline,
                    groupPosition: .position(at: index, count: visible.count),
                    onAction: handleRowAction,
                    onHide: selectedTab == .finish ? { target in
                        hide(target)
                    } : nil
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if selectedTab == .finish {
                        // Board `09-board05`: the finished-list gesture is "Hide" — it drops the row
                        // from this list and never touches the pose the job produced.
                        Button {
                            hide(row)
                        } label: {
                            Label("Hide", systemImage: "eye.slash")
                        }
                        .tint(AP.Color.controlFill)
                        .accessibilityIdentifier("jobs.row.remove.\(row.jobId)")
                    }
                }
            }

            if selectedTab == .finish {
                hideHint
                    .listRowInsets(EdgeInsets(top: AP.Space.space12, leading: AP.Space.space16,
                                              bottom: AP.Space.space24, trailing: AP.Space.space16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .transparentListBackground()
        .padding(.top, AP.Space.space4)
        .background(AP.Color.background)
        .refreshable {
            await jobsService.refresh()
        }
    }

    /// Board `09-board05` footer: the swipe gesture has to be explained once, because hiding is a
    /// list-only operation with no separate undo surface.
    private var hideHint: some View {
        HStack(alignment: .top, spacing: AP.Space.space8) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(AP.Color.secondaryText)
                .accessibilityHidden(true)
            Text("Swipe a finished job left to hide it. Hiding only removes it from this list. VoiceOver users get “Hide” in the actions rotor.")
                .font(AP.Font.caption)
                .foregroundStyle(AP.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Rows of the current segment, before the filter chip narrows them.
    private var tabRows: [JobRow] {
        switch selectedTab {
        case .processing:
            return jobsService.inProgress
        case .finish:
            return jobsService.finished
        }
    }

    private var rows: [JobRow] {
        tabRows.filter { filter.matches($0) }
    }

    // MARK: - Empty states

    /// Three distinct empty states (boards `09-board10/11/12`), each with its own copy, glyph and way
    /// out. `FeatureStateView`'s F4 swap is still landing, so this uses the already-tokenised panel the
    /// Gallery, Camera and Poses screens share — same circle, title, body and secondary action.
    @ViewBuilder
    private var emptyState: some View {
        switch selectedTab {
        case .processing:
            APEmptyStateView(
                title: "No jobs running",
                message: "Poses you add are processed here.",
                actionTitle: "View finished",
                action: { select(.finish) },
                style: .plain,
                glyph: "list.bullet.indent",
                actionIdentifier: "jobs.empty.viewFinished"
            )
        case .finish:
            APEmptyStateView(
                title: "Nothing finished yet",
                message: "Finished jobs stay here for 30 days.",
                actionTitle: "Go to Processing",
                action: { select(.processing) },
                style: .plain,
                glyph: "list.bullet.indent",
                actionIdentifier: "jobs.empty.goToProcessing"
            )
        }
    }

    private var filterEmptyState: some View {
        APEmptyStateView(
            title: filterEmptyTitle,
            message: filterEmptyMessage,
            actionTitle: "Show all",
            action: { filter = .all },
            style: .plain,
            glyph: filterEmptyGlyph,
            actionIdentifier: "jobs.empty.showAll"
        )
    }

    private var filterEmptyTitle: String {
        switch filter {
        case .all: return "No jobs here"
        case .queued: return "Nothing in the queue"
        case .processing: return "Nothing processing now"
        case .done: return "Nothing done yet"
        case .failed: return "No failed jobs"
        }
    }

    private var filterEmptyMessage: String {
        switch filter {
        case .all: return "Poses you add show up here."
        case .queued: return "Jobs waiting for a worker appear here."
        case .processing: return "Jobs being extracted appear here."
        case .done: return "Finished poses appear here once a job succeeds."
        case .failed: return "Everything you added finished successfully."
        }
    }

    private var filterEmptyGlyph: String {
        switch filter {
        case .failed, .done: return "checkmark"
        case .queued, .processing, .all: return "hourglass"
        }
    }

    // MARK: - Actions

    private func hide(_ row: JobRow) {
        Task {
            do {
                try await jobsService.hide(id: row.jobId)
            } catch {
                actionMessage = error.localizedDescription
            }
        }
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
                    actionMessage = error.localizedDescription
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
                    actionMessage = error.localizedDescription
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

/// Filter chip: `controlFill` at rest, `selectedBackground` plus a check glyph when chosen — state is
/// never carried by colour alone. Same geometry as the catalogue chip, owned here so the Jobs screen
/// has no write dependency on another feature folder.
struct JobsFilterChip: View {
    let title: String
    var isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AP.Space.space8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(AP.Font.supporting)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AP.Space.space16)
            .frame(minHeight: AP.HitTarget.minimum)
        }
        .buttonStyle(JobsFilterChipStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct JobsFilterChipStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? AP.Color.selectedForeground : AP.Color.primaryText)
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(fill(isPressed: configuration.isPressed))
            )
    }

    private func fill(isPressed: Bool) -> SwiftUI.Color {
        if isSelected { return AP.Color.selectedBackground }
        return isPressed ? AP.Color.controlFillPressed : AP.Color.controlFill
    }
}

/// Board `09-board08`: placeholder bars for the segment track, the chip row and four job rows, so the
/// header never sits above real chrome that jumps when the list arrives.
struct JobsLoadingSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: AP.Space.space12) {
            APSkeletonBar(height: 56)
                .padding(.horizontal, AP.Space.space16)

            HStack(spacing: AP.Space.space8) {
                APSkeletonBar(width: 88, height: AP.HitTarget.minimum)
                APSkeletonBar(width: 96, height: AP.HitTarget.minimum)
                APSkeletonBar(width: 116, height: AP.HitTarget.minimum)
            }
            .padding(.horizontal, AP.Space.space16)

            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: AP.Space.space12) {
                        APSkeletonBar(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: AP.Space.space8) {
                            APSkeletonBar(width: 140)
                            APSkeletonBar(width: 200)
                            APSkeletonBar(width: 160)
                        }
                    }
                    .padding(AP.Space.space16)
                    .opacity(APSkeleton.opacity(isPulsing: isPulsing, reduceMotion: reduceMotion))

                    if index < 3 {
                        Rectangle()
                            .fill(AP.Color.separator)
                            .frame(height: 1)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AP.Radius.radius16, style: .continuous)
                    .fill(AP.Color.surface)
            )
            .padding(.horizontal, AP.Space.space16)

            Spacer(minLength: 0)
        }
        .padding(.top, AP.Space.space4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading jobs")
        .onAppear(perform: startPulse)
    }

    private func startPulse() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: APSkeleton.pulseDuration).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
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
