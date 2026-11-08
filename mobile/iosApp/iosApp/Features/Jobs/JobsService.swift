import Foundation
import SwiftUI

enum JobsError: LocalizedError, Sendable, Equatable {
    case signInRequired
    case offline
    case invalidImage
    case imageTooLarge
    case invalidMetadata
    case extractPoseDisabled
    case notFound
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .signInRequired:
            return "Sign-in required to manage jobs."
        case .offline:
            return "You're offline. Check your connection."
        case .invalidImage:
            return "Only JPEG and PNG images are supported. Choose another photo."
        case .imageTooLarge:
            return "Photo exceeds the 10 MB limit. Choose another photo."
        case .invalidMetadata:
            return "Please check the pose name and tags."
        case .extractPoseDisabled:
            return "Pose extraction is currently disabled."
        case .notFound:
            return "Job not found."
        case .serverError(let message):
            return message
        }
    }
}

enum JobRowStatus: String, Sendable, Equatable {
    case queued
    case processing
    case failed
    case succeeded
}

/// The words the boards fix for the Jobs surface. One place owns them so a row, its accessibility
/// summary and a test cannot drift into three slightly different status lines.
///
/// Boards (`09-board03/06`): a finished row reads `Done · added to Poses`, a failed row reads
/// `Failed · <server message>` and a queued row the poll cannot move reads
/// `Queued · waiting for connection`. There is no percentage and no progress figure anywhere: the
/// server reports a job's stage, not a number, so the row never invents one.
enum JobsCopy {
    static let queued = "Queued"
    static let processing = "Processing"
    static let failed = "Failed"
    static let done = "Done"
    /// The second half of a succeeded row's status line.
    static let doneDetail = "added to Poses"
    /// The second half of a queued row's status line while the list cannot reach the server.
    static let waitingForConnection = "waiting for connection"
    static let offlineBanner = "You're offline. Progress resumes when you reconnect."

    /// Board separator between the stage and its detail.
    static let statusSeparator = " · "

    static func statusLine(label: String, detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return label }
        return label + statusSeparator + detail
    }

    /// The server owns the failure phrase (`photo too dark`), so it is passed through — trimmed and
    /// collapsed to one line, and dropped entirely when the server sent nothing usable.
    static func failureDetail(_ message: String?) -> String? {
        guard let message else { return nil }
        let collapsed = message
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

enum JobRowAction: String, Sendable, Equatable {
    case none
    case retry = "Retry"
    case viewPose = "View pose"
}

struct JobRow: Identifiable, Sendable, Equatable {
    var id: String { jobId }
    let jobId: String
    let name: String
    let status: JobRowStatus
    let statusLabel: String
    /// The second half of the status line: `added to Poses` for a succeeded job, the server's reason
    /// for a failed one, `nil` while a job is only queued or processing.
    let statusDetail: String?
    let action: JobRowAction
    let thumbnailUrl: String?
    let poseId: String?
    let errorMessage: String?
    let createdAt: String

    init(
        jobId: String,
        name: String,
        status: JobRowStatus,
        thumbnailUrl: String? = nil,
        poseId: String? = nil,
        errorMessage: String? = nil,
        createdAt: String = ""
    ) {
        self.jobId = jobId
        self.name = name
        self.status = status
        self.thumbnailUrl = thumbnailUrl
        self.poseId = poseId
        self.errorMessage = errorMessage
        self.createdAt = createdAt

        switch status {
        case .queued:
            self.statusLabel = JobsCopy.queued
            self.statusDetail = nil
            self.action = .none
        case .processing:
            self.statusLabel = JobsCopy.processing
            self.statusDetail = nil
            self.action = .none
        case .failed:
            self.statusLabel = JobsCopy.failed
            self.statusDetail = JobsCopy.failureDetail(errorMessage)
            self.action = .retry
        case .succeeded:
            self.statusLabel = JobsCopy.done
            self.statusDetail = JobsCopy.doneDetail
            self.action = .viewPose
        }
    }

    /// The row's status line, e.g. `Done · added to Poses` or plain `Processing`.
    var statusText: String {
        JobsCopy.statusLine(label: statusLabel, detail: statusDetail)
    }

    init(item: ExtractionJobListItem) {
        let parsedStatus: JobRowStatus = {
            switch item.status.lowercased() {
            case "queued": return .queued
            case "processing": return .processing
            case "succeeded": return .succeeded
            case "failed": return .failed
            default: return .processing
            }
        }()
        let fallbackName: String = {
            if let name = item.poseDraft?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            return "Untitled Pose"
        }()
        self.init(
            jobId: item.jobId,
            name: fallbackName,
            status: parsedStatus,
            thumbnailUrl: item.thumbnailUrl,
            poseId: item.poseId,
            errorMessage: item.errorMessage,
            createdAt: item.createdAt
        )
    }
}

enum JobWatchEvent: Sendable, Equatable {
    case status(PoseExtractionJobData)
    case offline
    case online
    case gone
}

enum JobsLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
protocol JobsServing: ObservableObject, AnyObject, Sendable {
    var inProgress: [JobRow] { get }
    var finished: [JobRow] { get }
    var activeCount: Int { get }
    var isOffline: Bool { get }
    var loadState: JobsLoadState { get }

    func refresh() async
    func startPolling()
    func stopPolling()
    func watchJob(id: String) -> AsyncStream<JobWatchEvent>
    func submit(image: Data, fileName: String, draft: PoseDraft) async throws -> String
    func retry(id: String) async throws
    func hide(id: String) async throws
    func getGuide(id: String) async throws -> GuidePose
}

@MainActor
final class JobsService: ObservableObject, JobsServing, SessionScoped {
    nonisolated static let maxImageSizeMB = 10

    @Published private(set) var inProgress: [JobRow] = []
    @Published private(set) var finished: [JobRow] = []
    @Published private(set) var activeCount: Int = 0
    @Published private(set) var isOffline: Bool = false
    @Published private(set) var loadState: JobsLoadState = .idle

    private let api: PoseAPIService
    private let boundary: SessionBoundary
    /// One fan-out per boundary: this service is one of its adopted models, so a session change clears
    /// the rows and a request that crossed it can no longer write.
    private let scope: SessionScope
    private var pollingTask: Task<Void, Never>?

    init(
        api: PoseAPIService = ServiceLocator.makePoseAPIService(),
        boundary: SessionBoundary = ServiceLocator.sessionBoundary
    ) {
        self.api = api
        self.boundary = boundary
        self.scope = SessionScope.of(boundary)
        scope.adopt(self)
    }

    deinit {
        pollingTask?.cancel()
    }

    /// The jobs belong to the Account on the server, so a session change drops every row: nothing may
    /// answer for the previous Account. A sign-in re-reads through the normal path.
    func resetForSessionChange(_ event: SessionEvent) {
        switch event {
        case .signedOut, .signInRequired:
            stopPolling()
            inProgress = []
            finished = []
            activeCount = 0
            isOffline = false
            loadState = .idle
        case .signedIn:
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        // The extraction kill switch owns the whole surface: while it is off this service is a
        // no-op that never puts a request on the wire, and it cannot paint rows the flag says the
        // build may not show. Without this guard a flag-off install still called
        // `listMyExtractJobs` on every `.signedIn` and on every poll tick.
        guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else {
            activeCount = 0
            inProgress = []
            finished = []
            isOffline = false
            loadState = .idle
            return
        }
        // A refresh that was on the wire during a session change must not write the previous
        // Account's rows over the cleared state (the hand-written observer had no such check).
        let ticket = await scope.beginRequest()
        guard await boundary.hasStoredSession() else {
            guard await scope.isValid(ticket) else { return }
            activeCount = 0
            inProgress = []
            finished = []
            loadState = .idle
            return
        }
        guard await scope.isValid(ticket) else { return }

        loadState = .loading
        do {
            let response = try await api.listMyExtractJobs(limit: 50)
            guard await scope.isValid(ticket) else { return }
            isOffline = false
            let allRows = response.data.map(JobRow.init(item:))
            var nextInProgress: [JobRow] = []
            var nextFinished: [JobRow] = []
            for row in allRows {
                switch row.status {
                case .queued, .processing:
                    nextInProgress.append(row)
                case .succeeded, .failed:
                    nextFinished.append(row)
                }
            }
            inProgress = nextInProgress
            finished = nextFinished
            activeCount = inProgress.count
            loadState = .loaded
        } catch let error as PoseAPIError {
            guard await scope.isValid(ticket) else { return }
            if error.isUnauthorized {
                activeCount = 0
                inProgress = []
                finished = []
                loadState = .idle
            } else {
                loadState = .failed(error.message)
            }
        } catch is URLError {
            guard await scope.isValid(ticket) else { return }
            isOffline = true
            // Preserve cached inProgress and finished rows
            loadState = .loaded
        } catch {
            guard await scope.isValid(ticket) else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func startPolling() {
        // Flag off means no poll loop at all — not a loop whose body is skipped — so a kill-switched
        // build issues zero list requests while the Jobs surface is on screen. A flag that turns on
        // later starts polling from the next `startPolling()` (the Jobs screen on appear).
        guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else { return }
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    nonisolated func watchJob(id: String) -> AsyncStream<JobWatchEvent> {
        AsyncStream { continuation in
            let task = Task {
                var wasOffline = false
                while !Task.isCancelled {
                    let hasSession = await self.boundary.hasStoredSession()
                    guard hasSession else {
                        continuation.finish()
                        return
                    }

                    do {
                        let response = try await self.api.getPoseExtractionJob(jobId: id)
                        if wasOffline {
                            wasOffline = false
                            continuation.yield(.online)
                        }
                        let jobData = response.data
                        continuation.yield(.status(jobData))
                        let statusLower = jobData.status.lowercased()
                        if statusLower == "succeeded" || statusLower == "failed" {
                            continuation.finish()
                            return
                        }
                    } catch let error as PoseAPIError {
                        // NIT #1: Treat 404 / NOT_FOUND / JOB_NOT_FOUND as terminal .gone
                        if error.code == "404" || error.code == "NOT_FOUND" || error.code == "JOB_NOT_FOUND" {
                            continuation.yield(.gone)
                            continuation.finish()
                            return
                        }
                        if error.isUnauthorized {
                            continuation.finish()
                            return
                        }
                    } catch is URLError {
                        wasOffline = true
                        continuation.yield(.offline)
                    } catch {
                        // Other non-fatal errors: keep polling
                    }

                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func submit(image: Data, fileName: String, draft: PoseDraft) async throws -> String {
        guard await boundary.hasStoredSession() else {
            throw JobsError.signInRequired
        }

        do {
            let response = try await api.startPoseExtraction(imageBytes: image, fileName: fileName, draft: draft)
            Task { await self.refresh() }
            return response.data.jobId
        } catch is URLError {
            throw JobsError.offline
        } catch let apiError as PoseAPIError {
            if apiError.isUnauthorized {
                throw JobsError.signInRequired
            }
            switch apiError.code {
            case "INVALID_IMAGE":
                throw JobsError.invalidImage
            case "IMAGE_TOO_LARGE", "413":
                throw JobsError.imageTooLarge
            case "INVALID_METADATA":
                throw JobsError.invalidMetadata
            default:
                throw JobsError.serverError(apiError.message)
            }
        } catch {
            throw JobsError.serverError(error.localizedDescription)
        }
    }

    func retry(id: String) async throws {
        guard AppConfig.canExtractPose(isEnabled: AppConfig.shared.isExtractPoseEnabled) else {
            throw JobsError.extractPoseDisabled
        }
        guard await boundary.hasStoredSession() else {
            throw JobsError.signInRequired
        }
        guard !isOffline else {
            throw JobsError.offline
        }

        _ = try await api.retryExtractJob(id: id)
        await refresh()
    }

    func hide(id: String) async throws {
        guard await boundary.hasStoredSession() else {
            throw JobsError.signInRequired
        }
        guard !isOffline else {
            throw JobsError.offline
        }

        try await api.hideExtractJob(id: id)
        finished.removeAll { $0.jobId == id }
    }

    func getGuide(id: String) async throws -> GuidePose {
        try await api.getGuide(id: id)
    }
}
